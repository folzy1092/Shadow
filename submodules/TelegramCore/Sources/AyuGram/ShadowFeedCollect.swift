import Foundation
import Postbox
import SwiftSignalKit

// Shadow: data of «Лента» (ShadowFeed.swift). Only what is stored on the
// device: the newest posts of the channels in the chat list (no history
// requests). `index` sorts lightweight references of the posts of a chip,
// `posts` builds a page of them for the page, `markRead` reads them in the
// channels. Posts hidden on this device (ads, filters — ShadowLocalHide.swift)
// never get in; nor do channels that are locked or hidden in the space.
public enum ShadowFeedCollect {
    // Per channel: at most this many newest posts, not older than this.
    public static let postsPerChannel = 40
    public static let maxAge: Int32 = 21 * 86400

    public struct Ref: Equatable {
        public var id: MessageId
        public var timestamp: Int32
        public var unread: Bool

        public var postId: String {
            return "\(self.id.peerId.toInt64()):\(self.id.namespace):\(self.id.id)"
        }
    }

    public struct Channel: Equatable {
        public var peerId: PeerId
        public var title: String
        public var isMuted: Bool
        public var isArchived: Bool
    }

    public struct Folder: Equatable {
        public var id: Int32
        public var title: String
        public var peerIds: [PeerId]
    }

    // What a media key of the page points to.
    public enum MediaSource {
        case resource(reference: MediaResourceReference, resource: MediaResource, peerId: PeerId, kind: String, fileExtension: String, size: Int64?)
    }

    public struct Page {
        public var posts: [ShadowFeed.Post]
        public var media: [String: MediaSource]
    }

    // MARK: - Channels and folders

    public static func channels(account: Account, includeArchived: Bool) -> Signal<([Channel], [Folder]), NoError> {
        let accountPeerId = account.peerId.toInt64()
        return account.postbox.transaction { transaction -> ([Channel], [Folder]) in
            let now = Int32(Date().timeIntervalSince1970)
            var result: [Channel] = []
            var groups: [(PeerGroupId, Bool)] = [(.root, false)]
            if includeArchived {
                groups.append((Namespaces.PeerGroup.archive, true))
            }
            for (group, archived) in groups {
                for peerId in transaction.chatListGetAllPeerIds(groupId: group) {
                    guard let channel = transaction.getPeer(peerId) as? TelegramChannel, case .broadcast = channel.info else {
                        continue
                    }
                    if ShadowChatLockStore.shared.requiresUnlock(accountPeerId: accountPeerId, peerId: peerId.toInt64()) || ShadowSpaceStore.shared.isHidden(accountPeerId: accountPeerId, peerId: peerId.toInt64()) {
                        continue
                    }
                    var muted = false
                    if let settings = transaction.getPeerNotificationSettings(id: peerId) as? TelegramPeerNotificationSettings, case let .muted(until) = settings.muteState, until > now {
                        muted = true
                    }
                    result.append(Channel(peerId: peerId, title: channel.title, isMuted: muted, isArchived: archived))
                }
            }
            let channelIds = Set(result.map { $0.peerId })
            var folders: [Folder] = []
            for filter in _internal_currentChatListFilters(transaction: transaction) {
                guard case let .filter(id, title, _, data) = filter else {
                    continue
                }
                var ids = Set<PeerId>()
                if data.categories.contains(.channels) {
                    ids = channelIds
                }
                for peerId in data.includePeers.peers where channelIds.contains(peerId) {
                    ids.insert(peerId)
                }
                for peerId in data.excludePeers {
                    ids.remove(peerId)
                }
                if !ids.isEmpty {
                    folders.append(Folder(id: id, title: title.text, peerIds: Array(ids)))
                }
            }
            return (result, folders)
        }
    }

    // MARK: - Index

    static func isPost(_ message: Message) -> Bool {
        for media in message.media {
            if media is TelegramMediaAction {
                return false
            }
        }
        return true
    }

    public static func index(account: Account, peerIds: [PeerId], unreadOnly: Bool, settings: AyuGramSettings) -> Signal<[Ref], NoError> {
        let accountPeerId = account.peerId
        return account.postbox.transaction { transaction -> [Ref] in
            let since = Int32(Date().timeIntervalSince1970) - ShadowFeedCollect.maxAge
            var refs: [Ref] = []
            for peerId in peerIds {
                let readState = transaction.getCombinedPeerReadState(peerId)
                var seenGroups = Set<Int64>()
                var count = 0
                transaction.scanTopMessages(peerId: peerId, namespace: Namespaces.Message.Cloud, limit: ShadowFeedCollect.postsPerChannel * 3, { message in
                    if message.timestamp < since || count >= ShadowFeedCollect.postsPerChannel {
                        return false
                    }
                    guard ShadowFeedCollect.isPost(message) else {
                        return true
                    }
                    if shadowLocalHideReason(message, settings: settings, accountPeerId: accountPeerId) != nil {
                        return true
                    }
                    // An album is one post: its newest message stands for it.
                    if let groupingKey = message.groupingKey {
                        if seenGroups.contains(groupingKey) {
                            return true
                        }
                        seenGroups.insert(groupingKey)
                    }
                    let unread = !(readState?.isIncomingMessageIndexRead(message.index) ?? true)
                    if unreadOnly && !unread {
                        return true
                    }
                    refs.append(Ref(id: message.id, timestamp: message.timestamp, unread: unread))
                    count += 1
                    return true
                })
            }
            refs.sort(by: { lhs, rhs in
                if lhs.timestamp != rhs.timestamp {
                    return lhs.timestamp > rhs.timestamp
                }
                return lhs.id > rhs.id
            })
            return refs
        }
    }

    // MARK: - Posts

    static func entities(_ message: Message) -> [ShadowFeed.Entity] {
        guard let attribute = message.attributes.first(where: { $0 is TextEntitiesMessageAttribute }) as? TextEntitiesMessageAttribute else {
            return []
        }
        let text = message.text as NSString
        var result: [ShadowFeed.Entity] = []
        for entity in attribute.entities {
            let location = entity.range.lowerBound
            let length = entity.range.upperBound - entity.range.lowerBound
            let kind: ShadowFeed.EntityKind
            switch entity.type {
            case .Bold:
                kind = .bold
            case .Italic:
                kind = .italic
            case .Underline:
                kind = .underline
            case .Strikethrough:
                kind = .strikethrough
            case .Code:
                kind = .code
            case .Pre:
                kind = .pre
            case .Spoiler:
                kind = .spoiler
            case .BlockQuote:
                kind = .blockquote
            case let .TextUrl(url):
                kind = .link(url)
            case .Url:
                guard location >= 0, location + length <= text.length else {
                    continue
                }
                let raw = text.substring(with: NSRange(location: location, length: length))
                kind = .link(raw.contains("://") ? raw : "https://" + raw)
            case .Email:
                guard location >= 0, location + length <= text.length else {
                    continue
                }
                kind = .link("mailto:" + text.substring(with: NSRange(location: location, length: length)))
            default:
                continue
            }
            result.append(ShadowFeed.Entity(location: location, length: length, kind: kind))
        }
        return result
    }

    static func mediaKey(_ id: MessageId, _ index: Int) -> String {
        return "m\(id.peerId.toInt64())_\(id.namespace)_\(id.id)_\(index)"
    }

    static func describe(message: Message, startIndex: Int, into media: inout [ShadowFeed.Media], sources: inout [String: MediaSource]) {
        var index = startIndex
        let reference: (Media) -> AnyMediaReference = { item in
            return .message(message: MessageReference(message), media: item)
        }
        for item in message.media {
            let key = mediaKey(message.id, index)
            index += 1
            switch item {
            case let image as TelegramMediaImage:
                let representation = imageRepresentationLargerThan(image.representations, size: PixelDimensions(width: 1000, height: 1000)) ?? largestImageRepresentation(image.representations)
                guard let representation else {
                    continue
                }
                media.append(ShadowFeed.Media(key: key, kind: "photo", width: Int(representation.dimensions.width), height: Int(representation.dimensions.height)))
                sources[key] = .resource(reference: .media(media: reference(image), resource: representation.resource), resource: representation.resource, peerId: message.id.peerId, kind: "photo", fileExtension: "jpg", size: nil)
            case let file as TelegramMediaFile:
                let dimensions = file.dimensions
                let duration = file.duration.map { Int($0) }
                if file.isInstantVideo {
                    media.append(ShadowFeed.Media(key: key, kind: "round", duration: duration))
                } else if file.isVoice {
                    media.append(ShadowFeed.Media(key: key, kind: "voice", duration: duration))
                } else if file.isSticker || file.isAnimatedSticker || file.isVideoSticker {
                    media.append(ShadowFeed.Media(key: key, kind: "sticker"))
                } else if file.isVideo || file.isAnimated {
                    let kind = file.isAnimated ? "gif" : "video"
                    media.append(ShadowFeed.Media(key: key, kind: kind, width: Int(dimensions?.width ?? 16), height: Int(dimensions?.height ?? 9), duration: duration))
                    sources[key] = .resource(reference: .media(media: reference(file), resource: file.resource), resource: file.resource, peerId: message.id.peerId, kind: kind, fileExtension: "mp4", size: file.size)
                    if let poster = largestImageRepresentation(file.previewRepresentations) {
                        sources[key + ":poster"] = .resource(reference: .media(media: reference(file), resource: poster.resource), resource: poster.resource, peerId: message.id.peerId, kind: "poster", fileExtension: "jpg", size: nil)
                    }
                } else if file.isMusic {
                    media.append(ShadowFeed.Media(key: key, kind: "audio", duration: duration, title: file.fileName))
                } else {
                    media.append(ShadowFeed.Media(key: key, kind: "file", title: file.fileName))
                }
            case let poll as TelegramMediaPoll:
                media.append(ShadowFeed.Media(key: key, kind: "poll", title: poll.text))
            case is TelegramMediaMap:
                media.append(ShadowFeed.Media(key: key, kind: "location"))
            default:
                break
            }
        }
    }

    static func reactionKey(_ value: MessageReaction.Reaction) -> String {
        return ShadowChatStatsCollect.reactionKey(value)
    }

    public static func posts(account: Account, refs: [Ref]) -> Signal<Page, NoError> {
        return account.postbox.transaction { transaction -> Page in
            var posts: [ShadowFeed.Post] = []
            var sources: [String: MediaSource] = [:]
            for ref in refs {
                guard let message = transaction.getMessage(ref.id), let peer = transaction.getPeer(ref.id.peerId) else {
                    continue
                }
                var group = [message]
                if message.groupingKey != nil, let messages = transaction.getMessageGroup(ref.id), !messages.isEmpty {
                    group = messages.sorted(by: { $0.id < $1.id })
                }
                let textMessage = group.first(where: { !$0.text.isEmpty }) ?? message
                var media: [ShadowFeed.Media] = []
                for item in group {
                    describe(message: item, startIndex: media.count, into: &media, sources: &sources)
                }
                var views: Int?
                var reactions: [ShadowFeed.Reaction] = []
                var comments: Int?
                var edited = false
                for attribute in message.attributes {
                    if let attribute = attribute as? ViewCountMessageAttribute {
                        views = attribute.count
                    } else if let attribute = attribute as? ReactionsMessageAttribute {
                        reactions = attribute.reactions.map { ShadowFeed.Reaction(key: reactionKey($0.value), count: Int($0.count), mine: $0.chosenOrder != nil) }
                    } else if let attribute = attribute as? ReplyThreadMessageAttribute, attribute.commentsPeerId != nil {
                        comments = Int(attribute.count)
                    } else if let attribute = attribute as? EditedMessageAttribute, !attribute.isHidden {
                        edited = true
                    }
                }
                var forwardFrom: String?
                if let forwardInfo = message.forwardInfo {
                    forwardFrom = forwardInfo.author?.debugDisplayTitle ?? forwardInfo.authorSignature ?? "скрытый пользователь"
                }
                let title = peer.debugDisplayTitle
                let html = ShadowFeed.html(text: textMessage.text, entities: entities(textMessage))
                if let avatar = peer.smallProfileImage, let peerReference = PeerReference(peer) {
                    sources["avatar:\(peer.id.toInt64())"] = .resource(reference: .avatar(peer: peerReference, resource: avatar.resource), resource: avatar.resource, peerId: peer.id, kind: "avatar", fileExtension: "jpg", size: nil)
                }
                posts.append(ShadowFeed.Post(
                    id: ref.postId,
                    peerId: ref.id.peerId.toInt64(),
                    namespace: ref.id.namespace,
                    messageId: ref.id.id,
                    channel: title,
                    color: Int(abs(ref.id.peerId.id._internalGetInt64Value() % 7)),
                    initials: ShadowFeed.initials(title),
                    timestamp: message.timestamp,
                    html: html,
                    textLength: (textMessage.text as NSString).length,
                    forwardFrom: forwardFrom,
                    media: media,
                    views: views,
                    reactions: reactions,
                    comments: comments,
                    unread: ref.unread,
                    edited: edited
                ))
            }
            return Page(posts: posts, media: sources)
        }
    }

    // MARK: - Reading

    // Reads the channels up to the given posts (the newest per channel). Ghost
    // Mode rules still apply inside applyMaxReadIndexInteractively.
    public static func markRead(account: Account, ids: [MessageId]) -> Signal<Void, NoError> {
        return account.postbox.transaction { transaction -> [MessageIndex] in
            var newest: [PeerId: MessageIndex] = [:]
            for id in ids {
                guard let message = transaction.getMessage(id) else {
                    continue
                }
                if let current = newest[id.peerId], current >= message.index {
                    continue
                }
                newest[id.peerId] = message.index
            }
            return Array(newest.values)
        }
        |> mapToSignal { indices -> Signal<Void, NoError> in
            let engine = TelegramEngine(account: account)
            return combineLatest(indices.map { engine.messages.applyMaxReadIndexInteractively(index: $0) })
            |> map { _ in Void() }
        }
    }

    // The newest stored message of each channel, for «Прочитать всё».
    public static func topMessageIds(account: Account, peerIds: [PeerId]) -> Signal<[MessageId], NoError> {
        return account.postbox.transaction { transaction -> [MessageId] in
            return peerIds.compactMap { transaction.getTopPeerMessageIndex(peerId: $0, namespace: Namespaces.Message.Cloud)?.id }
        }
    }

    // https://t.me link of a post.
    public static func link(account: Account, id: MessageId) -> Signal<String?, NoError> {
        return account.postbox.transaction { transaction -> String? in
            guard let peer = transaction.getPeer(id.peerId) else {
                return nil
            }
            if let username = peer.addressName {
                return "https://t.me/\(username)/\(id.id)"
            }
            return "https://t.me/c/\(id.peerId.id._internalGetInt64Value())/\(id.id)"
        }
    }
}

import Foundation
import Postbox
import SwiftSignalKit

// Shadow: data for «Итоги чата» (ShadowChatStats.swift). Two steps:
//  1. `loadHistory` downloads the part of the period that is not on the device
//     yet — the same history requests as scrolling the chat up, one at a time;
//  2. `report` reads the period from the local database, counts it and adds the
//     pictures of the top stickers and custom-emoji reactions.
public enum ShadowChatStatsCollect {
    public struct LoadProgress: Equatable {
        // Messages of the period downloaded in this run.
        public var downloaded: Int
        // The oldest message reached so far (0 — nothing downloaded yet).
        public var reachedTimestamp: Int32
        public var done: Bool

        public init(downloaded: Int, reachedTimestamp: Int32, done: Bool) {
            self.downloaded = downloaded
            self.reachedTimestamp = reachedTimestamp
            self.done = done
        }
    }

    // A pause between requests, like a person scrolling up.
    static let requestPause: Double = 0.35

    static func canLoad(peerId: PeerId) -> Bool {
        return peerId.namespace != Namespaces.Peer.SecretChat
    }

    public static func loadHistory(account: Account, peerId: PeerId, since: Int32) -> Signal<LoadProgress, NoError> {
        guard canLoad(peerId: peerId) else {
            return .single(LoadProgress(downloaded: 0, reachedTimestamp: 0, done: true))
        }
        return Signal { subscriber in
            let disposable = MetaDisposable()
            let queue = Queue()
            var downloaded = 0
            var reached: Int32 = 0
            var lastHole: ClosedRange<Int32>?
            var stalls = 0

            func finish() {
                subscriber.putNext(LoadProgress(downloaded: downloaded, reachedTimestamp: reached, done: true))
                subscriber.putCompletion()
            }

            func step() {
                let topHole: Signal<ClosedRange<Int32>?, NoError> = account.postbox.transaction { transaction -> ClosedRange<Int32>? in
                    let holes = transaction.getHoles(peerId: peerId, namespace: Namespaces.Message.Cloud)
                    guard let range = holes.rangeView.last, range.upperBound > range.lowerBound else {
                        return nil
                    }
                    return Int32(range.lowerBound) ... Int32(range.upperBound - 1)
                }
                disposable.set((topHole
                |> mapToSignal { hole -> Signal<(ClosedRange<Int32>?, [Int32]), NoError> in
                    guard let hole else {
                        return .single((nil, []))
                    }
                    let direction: MessageHistoryViewRelativeHoleDirection = .range(start: MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: hole.upperBound), end: MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: hole.lowerBound))
                    return fetchMessageHistoryHole(accountPeerId: account.peerId, source: .network(account.network), postbox: account.postbox, peerInput: .direct(peerId: peerId, threadId: nil), namespace: Namespaces.Message.Cloud, direction: direction, space: .everywhere, count: 100)
                    |> mapToSignal { result -> Signal<(ClosedRange<Int32>?, [Int32]), NoError> in
                        let ids = result?.ids ?? []
                        return account.postbox.transaction { transaction -> (ClosedRange<Int32>?, [Int32]) in
                            return (hole, ids.compactMap { transaction.getMessage($0)?.timestamp })
                        }
                    }
                }
                |> deliverOn(queue)).start(next: { hole, timestamps in
                    guard let hole else {
                        finish()
                        return
                    }
                    if timestamps.isEmpty {
                        // Nothing came back: the hole is gone or cannot be filled.
                        stalls += (lastHole == hole) ? 2 : 1
                        if stalls >= 2 {
                            finish()
                            return
                        }
                    } else {
                        stalls = 0
                    }
                    lastHole = hole
                    downloaded += timestamps.filter { $0 >= since }.count
                    if let oldest = timestamps.min() {
                        reached = reached == 0 ? oldest : min(reached, oldest)
                        if oldest < since {
                            finish()
                            return
                        }
                    }
                    subscriber.putNext(LoadProgress(downloaded: downloaded, reachedTimestamp: reached, done: false))
                    queue.after(ShadowChatStatsCollect.requestPause, {
                        step()
                    })
                }))
            }

            queue.async {
                step()
            }
            return disposable
        }
    }

    // MARK: - Items

    static func reactionKey(_ reaction: MessageReaction.Reaction) -> String {
        switch reaction {
        case let .builtin(value):
            return value
        case let .custom(fileId):
            return "custom:\(fileId)"
        case .stars:
            return "stars"
        }
    }

    static func stickerLabel(_ file: TelegramMediaFile) -> String? {
        for attribute in file.attributes {
            if case let .Sticker(displayText, _, _) = attribute, !displayText.isEmpty {
                return displayText
            }
        }
        return nil
    }

    static func item(message: Message, accountPeerId: PeerId, chatPeerId: PeerId, isGroup: Bool) -> ShadowChatStats.Item? {
        let authorId: Int64
        if let author = message.author {
            authorId = author.id.toInt64()
        } else {
            authorId = message.flags.contains(.Incoming) ? chatPeerId.toInt64() : accountPeerId.toInt64()
        }
        var item = ShadowChatStats.Item(timestamp: message.timestamp, authorId: authorId, text: message.text)
        for media in message.media {
            switch media {
            case let action as TelegramMediaAction:
                if case let .phoneCall(_, _, duration, _) = action.action {
                    item.kind = .call
                    item.duration = duration ?? 0
                } else {
                    // Other service messages are not counted.
                    return nil
                }
            case is TelegramMediaImage:
                item.kind = .photo
            case let file as TelegramMediaFile:
                if file.isInstantVideo {
                    item.kind = .round
                    item.duration = Int32(file.duration ?? 0)
                } else if file.isVoice {
                    item.kind = .voice
                    item.duration = Int32(file.duration ?? 0)
                } else if file.isSticker || file.isAnimatedSticker || file.isVideoSticker {
                    item.kind = .sticker
                    item.stickerKey = "sticker:\(file.fileId.id)"
                    item.stickerLabel = stickerLabel(file)
                } else if file.isAnimated {
                    item.kind = .gif
                } else if file.isVideo {
                    item.kind = .video
                } else {
                    item.kind = .file
                }
            case is TelegramMediaWebpage:
                item.hasLink = true
            default:
                break
            }
        }
        item.isForward = message.forwardInfo != nil
        for attribute in message.attributes {
            if attribute is DeletedMessageAttribute {
                item.isDeleted = true
            } else if let attribute = attribute as? EditedMessageAttribute, !attribute.isHidden {
                item.isEdited = true
            } else if attribute is ReplyMessageAttribute {
                item.isReply = true
            } else if let attribute = attribute as? TextEntitiesMessageAttribute {
                if attribute.entities.contains(where: { entity in
                    switch entity.type {
                    case .Url, .TextUrl:
                        return true
                    default:
                        return false
                    }
                }) {
                    item.hasLink = true
                }
            } else if let attribute = attribute as? ReactionsMessageAttribute {
                if !attribute.recentPeers.isEmpty {
                    item.reactions = attribute.recentPeers.map { ShadowChatStats.Reaction(authorId: $0.peerId.toInt64(), key: reactionKey($0.value)) }
                } else {
                    for reaction in attribute.reactions {
                        let mine = reaction.chosenOrder != nil
                        if mine {
                            item.reactions.append(ShadowChatStats.Reaction(authorId: accountPeerId.toInt64(), key: reactionKey(reaction.value)))
                        }
                        // A private chat has only one other person to react.
                        if !isGroup && Int(reaction.count) - (mine ? 1 : 0) > 0 {
                            item.reactions.append(ShadowChatStats.Reaction(authorId: chatPeerId.toInt64(), key: reactionKey(reaction.value)))
                        }
                    }
                }
            }
        }
        return item
    }

    // MARK: - Report

    public static func report(account: Account, peerId: PeerId, period: ShadowChatStats.Period, now: Int32) -> Signal<ShadowChatStats.Report?, NoError> {
        let since = period.start(now: now)
        let accountPeerId = account.peerId
        let counted: Signal<(ShadowChatStats.Report, [Int64: (TelegramMediaFile, MessageReference)])?, NoError> = account.postbox.transaction { transaction -> (ShadowChatStats.Report, [Int64: (TelegramMediaFile, MessageReference)])? in
            guard let peer = transaction.getPeer(peerId) else {
                return nil
            }
            let isGroup: Bool
            if peer is TelegramGroup {
                isGroup = true
            } else if let channel = peer as? TelegramChannel, case .group = channel.info {
                isGroup = true
            } else if peer is TelegramUser || peer is TelegramSecretChat {
                isGroup = false
            } else {
                return nil
            }
            var chatPeerId = peerId
            if let secret = peer as? TelegramSecretChat {
                chatPeerId = secret.regularPeerId
            }
            var names: [Int64: String] = [accountPeerId.toInt64(): "Я"]
            if !isGroup {
                let other = transaction.getPeer(chatPeerId) ?? peer
                names[chatPeerId.toInt64()] = other.debugDisplayTitle
            }
            let title = isGroup ? peer.debugDisplayTitle : (transaction.getPeer(chatPeerId) ?? peer).debugDisplayTitle

            var items: [ShadowChatStats.Item] = []
            var stickerFiles: [Int64: (TelegramMediaFile, MessageReference)] = [:]
            let namespaces = peerId.namespace == Namespaces.Peer.SecretChat ? [Namespaces.Message.SecretIncoming] : [Namespaces.Message.Cloud]
            for namespace in namespaces {
                transaction.scanTopMessages(peerId: peerId, namespace: namespace, limit: 2_000_000, { message in
                    if message.timestamp < since {
                        return false
                    }
                    if message.timestamp > now {
                        return true
                    }
                    if let author = message.author, names[author.id.toInt64()] == nil {
                        names[author.id.toInt64()] = author.debugDisplayTitle
                    }
                    if let item = ShadowChatStatsCollect.item(message: message, accountPeerId: accountPeerId, chatPeerId: chatPeerId, isGroup: isGroup) {
                        items.append(item)
                        if item.kind == .sticker, let file = message.media.first(where: { $0 is TelegramMediaFile }) as? TelegramMediaFile, stickerFiles[file.fileId.id] == nil {
                            stickerFiles[file.fileId.id] = (file, MessageReference(message))
                        }
                    }
                    return true
                })
            }

            let countDeleted = currentAyuGramSettings(transaction: transaction).chatStatsCountDeleted
            let builder = ShadowChatStats.Builder(accountPeerId: accountPeerId.toInt64(), peerId: peerId.toInt64(), title: title, isGroup: isGroup, period: period, from: since, to: now, names: names)
            for item in items where countDeleted || !item.isDeleted {
                builder.add(item)
            }
            var report = builder.build(generated: now)
            report.countsDeleted = countDeleted
            return (report, stickerFiles)
        }

        return counted
        |> mapToSignal { value -> Signal<ShadowChatStats.Report?, NoError> in
            guard let value else {
                return .single(nil)
            }
            let (report, stickerFiles) = value
            var stickerKeys = Set<String>()
            var customIds = Set<Int64>()
            for person in report.people {
                person.topStickers.forEach { stickerKeys.insert($0.key) }
                for reaction in person.reactions where reaction.key.hasPrefix("custom:") {
                    if let id = Int64(reaction.key.dropFirst("custom:".count)) {
                        customIds.insert(id)
                    }
                }
            }
            var signals: [Signal<(String, String?), NoError>] = []
            for key in stickerKeys {
                guard let id = Int64(key.dropFirst("sticker:".count)), let entry = stickerFiles[id] else {
                    continue
                }
                let (file, messageReference) = entry
                signals.append(imageDataURI(account: account, peerId: peerId, file: file, reference: .message(message: messageReference, media: file)) |> map { (key, $0) })
            }
            let customs: Signal<[(String, String?)], NoError>
            if customIds.isEmpty {
                customs = .single([])
            } else {
                customs = TelegramEngine(account: account).stickers.resolveInlineStickers(fileIds: Array(customIds))
                |> take(1)
                |> mapToSignal { files -> Signal<[(String, String?)], NoError> in
                    let images = files.map { id, file in
                        return imageDataURI(account: account, peerId: peerId, file: file, reference: .customEmoji(media: file)) |> map { ("custom:\(id)", $0) }
                    }
                    return combineLatest(images)
                }
            }
            return combineLatest(combineLatest(signals), customs)
            |> map { stickers, customs -> ShadowChatStats.Report? in
                var report = report
                for (key, uri) in stickers + customs {
                    if let uri {
                        report.images[key] = uri
                    }
                }
                return report
            }
        }
    }

    // MARK: - Pictures

    static func mimeType(_ data: Data) -> String? {
        let bytes = [UInt8](data.prefix(12))
        if bytes.count >= 12 && bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 && bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50 {
            return "image/webp"
        }
        if bytes.count >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
            return "image/jpeg"
        }
        if bytes.count >= 4 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 {
            return "image/png"
        }
        return nil
    }

    // A small static picture of a sticker or custom emoji as a data: URI, or
    // nil (animated-only, too big, not downloaded in time) — then the page
    // shows the sticker's emoji instead.
    static func imageDataURI(account: Account, peerId: PeerId, file: TelegramMediaFile, reference: AnyMediaReference) -> Signal<String?, NoError> {
        let resource: MediaResource
        if let thumbnail = file.previewRepresentations.max(by: { $0.dimensions.width < $1.dimensions.width }) {
            resource = thumbnail.resource
        } else if !file.isAnimatedSticker && !file.isVideoSticker, (file.size ?? 0) < 300_000 {
            resource = file.resource
        } else {
            return .single(nil)
        }
        let mediaBox = account.postbox.mediaBox
        let picture: Signal<String?, NoError> = Signal { subscriber in
            let fetch = fetchedMediaResource(mediaBox: mediaBox, userLocation: .peer(peerId), userContentType: .sticker, reference: .media(media: reference, resource: resource)).start()
            let data = (mediaBox.resourceData(resource)
            |> filter { $0.complete }
            |> take(1)).start(next: { data in
                var result: String?
                if let contents = try? Data(contentsOf: URL(fileURLWithPath: data.path)), contents.count < 300_000, let mime = ShadowChatStatsCollect.mimeType(contents) {
                    result = "data:\(mime);base64,\(contents.base64EncodedString())"
                }
                subscriber.putNext(result)
                subscriber.putCompletion()
            })
            return ActionDisposable {
                fetch.dispose()
                data.dispose()
            }
        }
        return picture |> timeout(10.0, queue: Queue.concurrentDefaultQueue(), alternate: .single(nil))
    }
}

// MARK: - Days in a row

extension ShadowChatStatsCollect {
    // How many times «Общаемся N дней подряд» may load older history while the
    // run still reaches the oldest stored message (100 messages a time).
    static let streakMaxRounds = 40

    // Walks the stored messages of a private chat from the newest (calls and
    // service messages do not count). When the run reaches the oldest stored
    // message and older history exists, loads more like scrolling up and
    // walks again.
    public static func chatStreak(account: Account, peerId: PeerId) -> Signal<Int, NoError> {
        let clock = ShadowChatStats.Clock.current
        let today = clock.day(Int32(Date().timeIntervalSince1970))
        let accountPeerId = account.peerId

        func walk() -> Signal<(days: Int, finished: Bool, oldest: Int32?), NoError> {
            return account.postbox.transaction { transaction -> (days: Int, finished: Bool, oldest: Int32?) in
                var walker = ShadowChatStreak.Walker(today: today)
                var oldest: Int32?
                var oldestId: Int32?
                transaction.scanTopMessages(peerId: peerId, namespace: Namespaces.Message.Cloud, limit: 1_000_000, { message in
                    oldest = message.timestamp
                    oldestId = message.id.id
                    guard let item = ShadowChatStatsCollect.item(message: message, accountPeerId: accountPeerId, chatPeerId: peerId, isGroup: false), item.kind != .call else {
                        return true
                    }
                    return walker.add(day: clock.day(message.timestamp), isMine: item.authorId == accountPeerId.toInt64())
                })
                if !walker.finished {
                    let holes = transaction.getHoles(peerId: peerId, namespace: Namespaces.Message.Cloud)
                    var olderHistory = false
                    if let oldestId, let first = holes.rangeView.first {
                        olderHistory = first.lowerBound < Int(oldestId)
                    }
                    if !olderHistory {
                        walker.finishAtEnd()
                    }
                }
                return (walker.days, walker.finished, oldest)
            }
        }

        func round(_ index: Int) -> Signal<Int, NoError> {
            return walk()
            |> mapToSignal { result -> Signal<Int, NoError> in
                guard !result.finished, index < ShadowChatStatsCollect.streakMaxRounds, let oldest = result.oldest else {
                    return .single(result.days)
                }
                return ShadowChatStatsCollect.loadHistory(account: account, peerId: peerId, since: oldest - 86400)
                |> filter { $0.done }
                |> take(1)
                |> mapToSignal { _ -> Signal<Int, NoError> in
                    return round(index + 1)
                }
            }
        }

        return round(0)
    }
}

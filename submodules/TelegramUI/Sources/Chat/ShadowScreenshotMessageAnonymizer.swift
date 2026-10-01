import Foundation
import Postbox
import TelegramCore

// These are render-only copies. No messages, peers or identities are written back.
final class ShadowScreenshotMessageAnonymizer {
    private let text = ShadowScreenshotAnonymizer()
    private let options: ShadowMessageScreenshotSettings
    private let accountPeerId: Int64
    private var participantIds = Set<PeerId>()
    private(set) var participants: [Peer] = []
    private var hideUnknown: Bool { self.options.anonymizeOwn && self.options.anonymizeOthers }

    init(messages: [Message], accountPeer: Peer?, accountPeerId: PeerId, options: ShadowMessageScreenshotSettings) {
        self.options = options
        self.accountPeerId = accountPeerId.toInt64()
        for message in messages {
            if let author = message.author ?? (!message.flags.contains(.Incoming) ? accountPeer : nil) { self.register(author) }
        }
        if let accountPeer { self.register(accountPeer) }
        var visited = Set<MessageId>()
        func collect(_ message: Message, depth: Int) {
            guard visited.insert(message.id).inserted else { return }
            if let peer = message.author { self.register(peer) }
            if let peer = message.forwardInfo?.author { self.register(peer) }
            if let peer = message.forwardInfo?.source { self.register(peer) }
            for (_, peer) in message.peers.sorted(by: { $0.0 < $1.0 }) { self.register(peer) }
            if depth > 0 {
                for (_, associated) in message.associatedMessages.sorted(by: { $0.0 < $1.0 }) { collect(associated, depth: depth - 1) }
            }
        }
        for message in messages { collect(message, depth: 3) }
    }

    private func hides(_ id: PeerId) -> Bool { self.options.anonymizes(peerId: id.toInt64(), accountPeerId: self.accountPeerId) }
    func hides(_ peer: Peer?) -> Bool { peer.map { self.hides($0.id) } ?? false }
    func label(for peer: Peer) -> String { self.text.label(for: peer.id.toInt64()) }

    private func register(_ peer: Peer) {
        guard self.participantIds.insert(peer.id).inserted else { return }
        self.participants.append(peer)
        if let user = peer as? TelegramUser {
            let names = [user.firstName, user.lastName].compactMap { $0 }
            self.text.register(id: peer.id.toInt64(), names: [names.joined(separator: " ")] + names, usernames: [user.username].compactMap { $0 } + user.usernames.map { $0.username }, phone: user.phone, redact: self.hides(peer))
        } else if let channel = peer as? TelegramChannel {
            self.text.register(id: peer.id.toInt64(), names: [channel.title], usernames: [channel.username].compactMap { $0 } + channel.usernames.map { $0.username }, phone: nil, redact: self.hides(peer))
        } else if let group = peer as? TelegramGroup {
            self.text.register(id: peer.id.toInt64(), names: [group.title], usernames: [], phone: nil, redact: self.hides(peer))
        }
    }

    func anonymousPeer(_ peer: Peer) -> Peer {
        guard self.hides(peer) else { return peer }
        let name = self.label(for: peer)
        if let user = peer as? TelegramUser {
            return TelegramUser(id: user.id, accessHash: user.accessHash, firstName: name, lastName: nil, username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
        } else if let channel = peer as? TelegramChannel {
            return TelegramChannel(id: channel.id, accessHash: channel.accessHash, title: name, username: nil, photo: [], creationDate: channel.creationDate, version: channel.version, participationStatus: channel.participationStatus, info: channel.info, flags: [], restrictionInfo: nil, adminRights: channel.adminRights, bannedRights: channel.bannedRights, defaultBannedRights: channel.defaultBannedRights, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, emojiStatus: nil, approximateBoostLevel: nil, subscriptionUntilDate: nil, verificationIconFileId: nil, sendPaidMessageStars: nil, linkedMonoforumId: channel.linkedMonoforumId)
        } else if let group = peer as? TelegramGroup {
            return TelegramGroup(id: group.id, title: name, photo: [], participantCount: group.participantCount, role: group.role, membership: group.membership, flags: group.flags, defaultBannedRights: group.defaultBannedRights, migrationReference: group.migrationReference, creationDate: group.creationDate, version: group.version)
        }
        return peer
    }

    private func redact(_ value: String, entities: [MessageTextEntity] = []) -> String {
        let replacements: [ShadowScreenshotAnonymizer.Replacement] = entities.compactMap { entity in
            let replacement: String
            switch entity.type {
            case let .TextMention(peerId):
                guard self.hides(peerId) else { return nil }
                replacement = self.text.label(for: peerId.toInt64())
            case .PhoneNumber:
                guard self.hideUnknown else { return nil }
                replacement = "[номер скрыт]"
            default: return nil
            }
            return .init(range: NSRange(location: entity.range.lowerBound, length: entity.range.count), text: replacement)
        }
        return self.text.redact(value, replacements: replacements, redactUnknownIdentifiers: self.hideUnknown)
    }

    private func quote(_ quote: EngineMessageReplyQuote?) -> EngineMessageReplyQuote? {
        return quote.map { EngineMessageReplyQuote(text: self.redact($0.text, entities: $0.entities), offset: $0.offset, entities: [], media: $0.media.flatMap(self.media)) }
    }

    private func media(_ media: Media) -> Media? {
        if let contact = media as? TelegramMediaContact {
            if let id = contact.peerId, !self.hides(id) { return contact }
            let details = contact.firstName + " " + contact.lastName + " " + contact.phoneNumber
            if contact.peerId == nil && !self.hideUnknown && self.redact(details) == details { return contact }
            return TelegramMediaContact(firstName: contact.peerId.map { self.text.label(for: $0.toInt64()) } ?? "[контакт скрыт]", lastName: "", phoneNumber: "[номер скрыт]", peerId: nil, vCardData: nil)
        }
        if let file = media as? TelegramMediaFile {
            return file.withUpdatedAttributes(file.attributes.map {
                if case let .FileName(name) = $0 { return .FileName(fileName: self.redact(name)) }
                if case let .Audio(voice, duration, title, performer, waveform) = $0 { return .Audio(isVoice: voice, duration: duration, title: title.map { self.redact($0) }, performer: performer.map { self.redact($0) }, waveform: waveform) }
                return $0
            })
        }
        if let poll = media as? TelegramMediaPoll {
            let solution = poll.results.solution.map { TelegramMediaPollResults.Solution(text: self.redact($0.text, entities: $0.entities), entities: [], media: $0.media.flatMap(self.media)) }
            let results = TelegramMediaPollResults(voters: poll.results.voters?.map { TelegramMediaPollOptionVoters(selected: $0.selected, opaqueIdentifier: $0.opaqueIdentifier, count: $0.count, isCorrect: $0.isCorrect, recentVoters: $0.recentVoters.filter { !self.hides($0) }) }, totalVoters: poll.results.totalVoters, recentVoters: poll.results.recentVoters.filter { !self.hides($0) }, solution: solution, hasUnseenVotes: poll.results.hasUnseenVotes, canViewStats: false)
            let options = poll.options.map { TelegramMediaPollOption(text: self.redact($0.text, entities: $0.entities), entities: [], opaqueIdentifier: $0.opaqueIdentifier, media: $0.media.flatMap(self.media), date: $0.date, addedBy: $0.addedBy.flatMap { self.hides($0) ? nil : $0 }) }
            return TelegramMediaPoll(pollId: poll.pollId, publicity: poll.publicity, kind: poll.kind, text: self.redact(poll.text, entities: poll.textEntities), textEntities: [], options: options, correctAnswers: poll.correctAnswers, results: results, isClosed: poll.isClosed, deadlineTimeout: poll.deadlineTimeout, deadlineDate: poll.deadlineDate, pollHash: poll.pollHash, openAnswers: poll.openAnswers, revotingDisabled: poll.revotingDisabled, shuffleAnswers: poll.shuffleAnswers, hideResultsUntilClose: poll.hideResultsUntilClose, isCreator: poll.isCreator, attachedMedia: poll.attachedMedia.flatMap(self.media), restrictToSubscribers: poll.restrictToSubscribers, countries: poll.countries)
        }
        // Other rich cards can contain identities outside message text/entities.
        if media is TelegramMediaImage || media is TelegramMediaDice { return media }
        return nil
    }

    func message(_ message: Message, depth: Int = 3) -> Message {
        var peers = SimpleDictionary<PeerId, Peer>()
        for (id, peer) in message.peers { peers[id] = self.anonymousPeer(peer) }
        var associated = SimpleDictionary<MessageId, Message>()
        if depth > 0 { for (id, value) in message.associatedMessages { associated[id] = self.message(value, depth: depth - 1) } }
        var entities: [MessageTextEntity] = []
        var attributes: [MessageAttribute] = []
        for attribute in message.attributes {
            if let value = attribute as? TextEntitiesMessageAttribute {
                entities = value.entities
            } else if let value = attribute as? ReplyMessageAttribute {
                if depth > 0 { attributes.append(ReplyMessageAttribute(messageId: value.messageId, threadMessageId: value.threadMessageId, quote: self.quote(value.quote), isQuote: value.isQuote, innerSubject: nil)) }
            } else if let value = attribute as? QuotedReplyMessageAttribute {
                let author: String?
                if let peerId = value.peerId {
                    author = self.hides(peerId) ? self.text.label(for: peerId.toInt64()) : value.authorName
                } else {
                    author = value.authorName.map { self.hideUnknown ? "[автор скрыт]" : self.redact($0) }
                }
                attributes.append(QuotedReplyMessageAttribute(peerId: value.peerId, authorName: author, quote: self.quote(value.quote), isQuote: value.isQuote))
            } else if !(attribute is AuthorSignatureMessageAttribute || attribute is ReplyStoryAttribute || attribute is ReactionsMessageAttribute || attribute is PendingReactionsMessageAttribute || attribute is PendingStarsReactionsMessageAttribute) {
                attributes.append(attribute)
            }
        }
        let media = message.media.compactMap(self.media)
        var body = self.redact(message.text, entities: entities)
        if media.isEmpty && !message.media.isEmpty && body.isEmpty { body = "[карточка скрыта]" }
        let forward = message.forwardInfo.map { info in
            let hideSignature = self.hideUnknown || self.hides(info.author) || self.hides(info.source)
            return MessageForwardInfo(author: info.author.map(self.anonymousPeer), source: info.source.map(self.anonymousPeer), sourceMessageId: info.sourceMessageId, date: info.date, authorSignature: info.authorSignature.map { hideSignature ? "[автор скрыт]" : self.redact($0) }, psaType: info.psaType, flags: info.flags)
        }
        return Message(stableId: message.stableId, stableVersion: message.stableVersion, id: message.id, globallyUniqueId: message.globallyUniqueId, groupingKey: message.groupingKey, groupInfo: message.groupInfo, threadId: message.threadId, timestamp: message.timestamp, flags: message.flags, tags: message.tags, globalTags: message.globalTags, localTags: message.localTags, customTags: message.customTags, forwardInfo: forward, author: message.author.map(self.anonymousPeer), text: body, attributes: attributes, media: media, peers: peers, associatedMessages: associated, associatedMessageIds: message.associatedMessageIds, associatedMedia: message.associatedMedia.compactMapValues(self.media), associatedThreadInfo: nil, associatedStories: [:])
    }
}

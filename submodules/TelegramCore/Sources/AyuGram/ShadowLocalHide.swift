import Foundation
import Postbox

// Shadow: why a message is hidden on this device — the shadow ban, a message
// filter or an ad (ShadowAdFilter.swift). One check for every place that
// shows messages: the chat (ChatHistoryEntriesForView) and the chat list
// preview (ChatListItem), so both always agree.
public enum ShadowLocalHideReason: Equatable {
    case shadowBan
    case filter
    case ad

    public var placeholderText: String {
        switch self {
        case .shadowBan:
            return "Скрыто: теневой бан"
        case .filter:
            return "Скрыто локальным фильтром"
        case .ad:
            return "Скрыта реклама"
        }
    }

    // false: the message leaves no trace instead of turning into a stub.
    public func showsPlaceholder(settings: AyuGramSettings) -> Bool {
        switch self {
        case .shadowBan, .filter:
            return settings.messageFilterShowPlaceholder
        case .ad:
            return !settings.adHideCompletely
        }
    }
}

public func shadowAdPlace(peer: Peer?) -> ShadowAdPlace {
    if let channel = peer as? TelegramChannel {
        if case .broadcast = channel.info {
            return .channel
        }
        return .group
    }
    if peer is TelegramGroup {
        return .group
    }
    return .privateChat
}

// Text the ad markers are matched against: the visible text plus the URLs that
// are not part of it (hidden links, URL buttons, the link preview).
func shadowAdSearchTexts(_ message: Message) -> [String] {
    var texts: [String] = [message.text]
    for attribute in message.attributes {
        if let attribute = attribute as? TextEntitiesMessageAttribute {
            for entity in attribute.entities {
                if case let .TextUrl(url) = entity.type {
                    texts.append(url)
                }
            }
        } else if let attribute = attribute as? ReplyMarkupMessageAttribute {
            for row in attribute.rows {
                for button in row.buttons {
                    switch button.action {
                    case let .url(url):
                        texts.append(url)
                    case let .urlAuth(url, _):
                        texts.append(url)
                    default:
                        break
                    }
                }
            }
        }
    }
    for media in message.media {
        if let webpage = media as? TelegramMediaWebpage, case let .Loaded(content) = webpage.content {
            texts.append(content.url)
        }
    }
    return texts
}

public func shadowMessageIsHiddenAd(_ message: Message, settings: AyuGramSettings) -> Bool {
    let scope = settings.adScope
    guard scope.isEnabled, message.flags.contains(.Incoming) else {
        return false
    }
    let place = shadowAdPlace(peer: message.peers[message.id.peerId])
    guard scope.applies(place: place, isForwarded: message.forwardInfo != nil) else {
        return false
    }
    return ShadowAdMarkersStore.shared.matcher.isAd(texts: shadowAdSearchTexts(message))
}

public func shadowLocalHideReason(_ message: Message, settings: AyuGramSettings, accountPeerId: PeerId) -> ShadowLocalHideReason? {
    // Shadow ban: other people's messages from a banned user; own messages stay.
    if !settings.shadowBannedPeerIds.isEmpty, let authorId = message.author?.id, authorId != accountPeerId, settings.isShadowBanned(peerId: authorId.toInt64()) {
        return .shadowBan
    }
    if settings.matchesMessageFilter(text: message.text) {
        return .filter
    }
    if shadowMessageIsHiddenAd(message, settings: settings) {
        return .ad
    }
    return nil
}

public func shadowLocalHideReason(_ message: EngineMessage, settings: AyuGramSettings, accountPeerId: EnginePeer.Id) -> ShadowLocalHideReason? {
    return shadowLocalHideReason(message._asMessage(), settings: settings, accountPeerId: accountPeerId)
}

// Anything to check at all — lets hot paths skip the per-message work.
public func shadowLocalHideIsActive(settings: AyuGramSettings) -> Bool {
    return !settings.messageFilters.isEmpty || !settings.shadowBannedPeerIds.isEmpty || settings.adScope.isEnabled
}

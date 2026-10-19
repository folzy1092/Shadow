import Foundation
import Postbox
import SwiftSignalKit

// Shadow: stores the «Подарок для розыгрыша» card (ShadowFakeGift.swift) as a
// local message: the Local namespace and no .Unsent flag, so the pending
// message manager never sends it. Outgoing, from the account, right now.
public enum ShadowFakeGiftError {
    case notFound
    case notPrivateChat
}

// `stars` — the price in «Вы отправили подарок за N звёзд».
public func shadowAddFakeGift(account: Account, peerId: EnginePeer.Id, slug: String, stars: Int64) -> Signal<Never, ShadowFakeGiftError> {
    guard peerId.namespace == Namespaces.Peer.CloudUser, peerId != account.peerId else {
        return .fail(.notPrivateChat)
    }
    return _internal_getUniqueStarGift(account: account, slug: slug)
    |> mapError { _ -> ShadowFakeGiftError in
        return .notFound
    }
    |> mapToSignal { gift -> Signal<Never, ShadowFakeGiftError> in
        let shown = gift.withOwner(.peerId(peerId))
        return account.postbox.transaction { transaction -> Void in
            let action = TelegramMediaAction(action: .starGiftUnique(
                gift: .unique(shown),
                isUpgrade: false,
                isTransferred: true,
                savedToProfile: false,
                canExportDate: nil,
                transferStars: stars,
                isRefunded: false,
                isPrepaidUpgrade: false,
                peerId: peerId,
                senderId: account.peerId,
                savedId: nil,
                resaleAmount: nil,
                canTransferDate: nil,
                canResaleDate: nil,
                dropOriginalDetailsStars: nil,
                assigned: false,
                fromOffer: false,
                canCraftAt: nil,
                isCrafted: false
            ))
            let timestamp = Int32(Date().timeIntervalSince1970)
            let message = StoreMessage(peerId: peerId, namespace: Namespaces.Message.Local, customStableId: nil, globallyUniqueId: nil, groupingKey: nil, threadId: nil, timestamp: timestamp, flags: [], tags: [], globalTags: [], localTags: [], forwardInfo: nil, authorId: account.peerId, text: "", attributes: [], media: [action])
            let _ = transaction.addMessages([message], location: .Random)
        }
        |> castError(ShadowFakeGiftError.self)
        |> ignoreValues
    }
}

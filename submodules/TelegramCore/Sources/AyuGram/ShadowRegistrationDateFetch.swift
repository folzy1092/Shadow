import Foundation
import Postbox
import SwiftSignalKit
import TelegramApi

// Shadow: asks @ayugrambot for a user's registration date with the inline
// query `regdate <id>` — the same request AyuGram Desktop makes
// (messages.getInlineBotResults with an empty peer, so no chat is involved and
// nothing is sent). The answer is a JSON text result, parsed and cached by
// ShadowRegistrationDateStore; an open profile refreshes via its notification.
//
// The bot learns which user id was looked up — the setting's footer says so.

private let shadowRegistrationDateBotId: Int64 = 6247153446
private let shadowRegistrationDateBotUsername = "ayugrambot"

private func shadowRegistrationDateBotPeer(account: Account) -> Signal<Peer?, NoError> {
    let botPeerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(shadowRegistrationDateBotId))
    return account.postbox.transaction { transaction -> Peer? in
        return transaction.getPeer(botPeerId)
    }
    |> mapToSignal { peer -> Signal<Peer?, NoError> in
        if let peer {
            return .single(peer)
        }
        return _internal_resolvePeerByName(account: account, name: shadowRegistrationDateBotUsername, referrer: nil)
        |> mapToSignal { result -> Signal<PeerId?, NoError> in
            switch result {
            case .progress:
                return .complete()
            case let .result(peerId):
                return .single(peerId)
            }
        }
        |> take(1)
        |> mapToSignal { peerId -> Signal<Peer?, NoError> in
            guard let peerId else {
                return .single(nil)
            }
            return account.postbox.transaction { transaction -> Peer? in
                return transaction.getPeer(peerId)
            }
        }
    }
}

// Fire-and-forget: does nothing if a fetch for this user is running or a
// cached answer is still fresh.
public func shadowRequestRegistrationDate(account: Account, userId: Int64, store: ShadowRegistrationDateStore = .shared) -> Signal<Never, NoError> {
    guard store.beginBotFetch(userId: userId, now: Date().timeIntervalSince1970) else {
        return .complete()
    }
    let query = "regdate \(userId)"
    let finished = Atomic<Bool>(value: false)
    return shadowRegistrationDateBotPeer(account: account)
    |> mapToSignal { bot -> Signal<ShadowRegistrationDate.BotAnswer?, NoError> in
        guard let bot, let inputBot = apiInputUser(bot) else {
            return .single(nil)
        }
        return account.network.request(Api.functions.messages.getInlineBotResults(flags: 0, bot: inputBot, peer: .inputPeerEmpty, geoPoint: nil, query: query, offset: ""))
        |> map(Optional.init)
        |> `catch` { _ -> Signal<Api.messages.BotResults?, NoError> in
            return .single(nil)
        }
        |> map { result -> ShadowRegistrationDate.BotAnswer? in
            guard let result else {
                return nil
            }
            let collection = ChatContextResultCollection(apiResults: result, botId: bot.id, peerId: bot.id, query: query, geoPoint: nil)
            for item in collection.results {
                if case let .text(text, _, _, _, _, _) = item.message, let answer = ShadowRegistrationDate.parseBotAnswer(text) {
                    return answer
                }
            }
            return nil
        }
    }
    |> timeout(20.0, queue: Queue.concurrentDefaultQueue(), alternate: .single(nil))
    |> take(1)
    |> afterNext { answer in
        if finished.swap(true) == false {
            store.finishBotFetch(userId: userId, answer: answer, now: Date().timeIntervalSince1970)
        }
    }
    // Ended without an answer (cancelled, no bot): release the in-flight
    // mark so a later profile open can try again.
    |> afterDisposed {
        if finished.swap(true) == false {
            store.finishBotFetch(userId: userId, answer: nil, now: Date().timeIntervalSince1970)
        }
    }
    |> ignoreValues
}

// Called where Telegram's own peer settings arrive: remembers the official
// registration month so it is shown on the profile and improves the local
// estimate for other ids.
func shadowRecordOfficialRegistrationMonth(peerId: PeerId, settings: PeerStatusSettings) {
    guard peerId.namespace == Namespaces.Peer.CloudUser, let month = settings.registrationDate else {
        return
    }
    ShadowRegistrationDateStore.shared.recordOfficial(userId: peerId.id._internalGetInt64Value(), month: month)
}

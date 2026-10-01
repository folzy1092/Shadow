import Foundation
import Postbox
import SwiftSignalKit

// Shadow: applies a second-space visibility change (spec section 6).
// A chat that becomes "only in the second space" is muted forever on the
// server, so it sends no notifications at all; the mute state it had before is
// remembered and restored when the chat leaves the second space.
private func shadowEncodeMuteState(_ state: PeerMuteState) -> String {
    switch state {
    case .default:
        return "default"
    case .unmuted:
        return "unmuted"
    case let .muted(until):
        return "muted:\(until)"
    }
}

// The muteInterval argument of _internal_updatePeerMuteSetting for a saved state.
private func shadowMuteInterval(saved: String, now: Int32) -> Int32? {
    if saved == "unmuted" {
        return 0
    }
    if saved.hasPrefix("muted:"), let until = Int32(saved.dropFirst("muted:".count)) {
        if until == Int32.max {
            return Int32.max
        }
        let remaining = until - now
        return remaining > 0 ? remaining : nil
    }
    return nil
}

public func shadowApplySpaceVisibility(account: Account, peerIds: [EnginePeer.Id], visibility: ShadowSpaceStore.Visibility) -> Signal<Void, NoError> {
    let store = ShadowSpaceStore.shared
    let accountPeerId = account.peerId.toInt64()
    let peerIds = peerIds.filter { $0 != account.peerId }
    return account.postbox.transaction { transaction -> Void in
        let now = Int32(Date().timeIntervalSince1970)
        for peerId in peerIds {
            let previous = store.visibility(accountPeerId: accountPeerId, peerId: peerId.toInt64())
            if visibility == .secondOnly && previous != .secondOnly {
                var notificationPeerId = peerId
                if let peer = transaction.getPeer(peerId), peer is TelegramSecretChat, let associatedPeerId = peer.associatedPeerId {
                    notificationPeerId = associatedPeerId
                }
                let current = (transaction.getPeerNotificationSettings(id: notificationPeerId) as? TelegramPeerNotificationSettings) ?? .defaultSettings
                store.saveMuteState(shadowEncodeMuteState(current.muteState), accountPeerId: accountPeerId, peerId: peerId.toInt64())
                _internal_updatePeerMuteSetting(account: account, transaction: transaction, peerId: peerId, threadId: nil, muteInterval: Int32.max)
            } else if visibility != .secondOnly && previous == .secondOnly {
                if let saved = store.takeSavedMuteState(accountPeerId: accountPeerId, peerId: peerId.toInt64()) {
                    _internal_updatePeerMuteSetting(account: account, transaction: transaction, peerId: peerId, threadId: nil, muteInterval: shadowMuteInterval(saved: saved, now: now))
                }
            }
        }
    }
    |> deliverOnMainQueue
    |> map { _ -> Void in
        store.setVisibility(visibility, accountPeerId: accountPeerId, peerIds: peerIds.map { $0.toInt64() })
        return Void()
    }
}

// Removes the second code: every chat of this account goes back to
// "everywhere" (with its mute state restored) before the store is cleared.
public func shadowRemoveSecondSpace(account: Account) -> Signal<Void, NoError> {
    let store = ShadowSpaceStore.shared
    let peerIds = store.customVisibilities(accountPeerId: account.peerId.toInt64()).keys.map { EnginePeer.Id($0) }
    return shadowApplySpaceVisibility(account: account, peerIds: peerIds, visibility: .everywhere)
    |> map { _ -> Void in
        store.removeCode()
        return Void()
    }
}

import Foundation
import SwiftSignalKit

// Shadow: system notifications of a locked chat never show its text. Telegram's
// own per-chat "show preview" setting (server side, so the push itself carries
// no text) is turned off while the chat is locked and restored when the lock is
// removed. Only previews hidden here are restored; Saved Messages has no pushes.
public enum ShadowChatLockPreviews {
    private static func key(accountPeerId: Int64) -> String {
        return "shadow.chatLock.hiddenPreviews.v1.\(accountPeerId)"
    }

    // Brings the server setting in line with the current locks of this account.
    public static func sync(engine: TelegramEngine, accountPeerId: EnginePeer.Id) {
        // The Full disguise reads every lock as off; leave the server alone.
        if ShadowDisguise.shared.isFull {
            return
        }
        let account = accountPeerId.toInt64()
        let defaults = UserDefaults.standard
        let hidden = Set((defaults.stringArray(forKey: self.key(accountPeerId: account)) ?? []).compactMap(Int64.init))
        let locked = Set(ShadowChatLockStore.shared.lockedPeerIds(accountPeerId: account)).subtracting([account])
        if hidden == locked {
            return
        }
        for peerId in locked.subtracting(hidden) {
            let _ = engine.peers.updatePeerDisplayPreviewsSetting(peerId: EnginePeer.Id(peerId), threadId: nil, displayPreviews: .hide).startStandalone()
        }
        for peerId in hidden.subtracting(locked) {
            let _ = engine.peers.updatePeerDisplayPreviewsSetting(peerId: EnginePeer.Id(peerId), threadId: nil, displayPreviews: .default).startStandalone()
        }
        defaults.set(locked.sorted().map { String($0) }, forKey: self.key(accountPeerId: account))
    }
}

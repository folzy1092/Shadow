import Foundation

@main
struct DuressTests {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            count += 1
        }
        let suite = "shadow-duress-tests-\(UInt64.random(in: 0 ... UInt64.max))"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let duress = ShadowDuress(defaults: defaults)

        // Code
        check(!duress.hasCode, "No code initially")
        check(!duress.verifyCode("1357"), "Nothing verifies without a code")
        check(duress.setCode("1357"), "Code set")
        check(duress.hasCode, "Has code")
        check(duress.verifyCode("1357"), "Code verifies")
        check(duress.verifyCode("١٣٥٧"), "Arabic-Indic digits verify")
        check(!duress.verifyCode("1358"), "Wrong code rejected")
        let stored = defaults.dictionary(forKey: "shadow.duress.code.v1")
        check((stored?["hash"] as? Data) != nil && stored?["code"] == nil, "Only the hash is stored")

        check(ShadowDuress.validationError(code: "1357", format: .digits(4), mainCode: "1111", matchesSecondCode: { _ in false }) == nil, "Valid duress code")
        check(ShadowDuress.validationError(code: "1111", format: .digits(4), mainCode: "1111", matchesSecondCode: { _ in false }) != nil, "Must differ from the main code")
        check(ShadowDuress.validationError(code: "2468", format: .digits(4), mainCode: "1111", matchesSecondCode: { $0 == "2468" }) != nil, "Must differ from the second code")
        check(ShadowDuress.validationError(code: "12", format: .digits(4), mainCode: "1111", matchesSecondCode: { _ in false }) != nil, "Format follows the passcode")

        // Accounts
        duress.setLogout(true, accountPeerId: 42)
        duress.setLogout(true, accountPeerId: 7)
        duress.setLogout(true, accountPeerId: 42)
        check(duress.logoutAccountPeerIds == [7, 42], "Logout accounts are a sorted set")
        duress.setLogout(false, accountPeerId: 7)
        check(ShadowDuress(defaults: defaults).logoutAccountPeerIds == [42], "Logout accounts persist")
        duress.removeCode()
        check(!duress.hasCode, "Code removed")
        check(duress.logoutAccountPeerIds.isEmpty, "Removing the code clears the accounts")

        // Panic gesture settings
        check(duress.panicGesture == .off, "Gesture off by default")
        check(duress.panicAction == .hideSecondSpace, "Default action hides the second space")
        check(!duress.isPanicGestureActive, "Inactive while off")
        check(!duress.panic(), "Panic does nothing while off")
        duress.setPanicGesture(.faceDown)
        duress.setPanicAction(.clean)
        check(ShadowDuress(defaults: defaults).panicGesture == .faceDown, "Gesture persists")
        check(ShadowDuress(defaults: defaults).panicAction == .clean, "Action persists")
        check(duress.isPanicGestureActive, "Active once chosen")

        // Clean session through the shared stores (standard defaults of this
        // test process; reset at the end).
        let spaces = ShadowSpaceStore.shared
        spaces.setVisibility(.secondOnly, accountPeerId: 1, peerIds: [10])
        spaces.setVisibility(.mainOnly, accountPeerId: 1, peerIds: [20])
        check(!ShadowDisguise.shared.isDuressActive, "No duress session at start")
        check(!ShadowDisguise.shared.hidesSettings || ShadowDisguise.shared.mode != .off, "Settings visible without a session")

        var notified = 0
        let token = NotificationCenter.default.addObserver(forName: ShadowSpaceStore.didChangeNotification, object: nil, queue: nil, using: { _ in
            notified += 1
        })
        spaces.setActiveSpace(.second)
        notified = 0
        check(duress.panic(), "Clean panic runs")
        check(ShadowDisguise.shared.isDuressActive, "Clean panic starts the session")
        check(spaces.activeSpace == .main, "Clean panic returns to the main space")
        check(notified >= 1, "Chat list is told to re-filter")
        check(ShadowDisguise.shared.hidesSettings, "Session hides the settings")
        check(spaces.isHidden(accountPeerId: 1, peerId: 10), "Second-only chat hidden in the session")
        check(!spaces.isHidden(accountPeerId: 1, peerId: 20), "Main-only chat stays")
        check(!spaces.isHidden(accountPeerId: 1, peerId: 30), "Ordinary chat stays")
        check(spaces.hiddenPeerIds(accountPeerId: 1) == [10], "Hidden list in the session")
        check(!duress.panic(), "Second clean panic has nothing to do")

        spaces.setDuressActive(false)
        check(!ShadowDisguise.shared.isDuressActive, "Session ends")
        check(!spaces.isHidden(accountPeerId: 1, peerId: 20), "Main-only chat visible after the session")

        var triggeredIds: [Int64]?
        let triggerToken = NotificationCenter.default.addObserver(forName: ShadowDuress.didTriggerNotification, object: nil, queue: nil, using: { notification in
            triggeredIds = notification.userInfo?[ShadowDuress.logoutAccountPeerIdsKey] as? [Int64]
        })
        duress.setLogout(true, accountPeerId: 5)
        spaces.setActiveSpace(.second)
        duress.trigger()
        check(ShadowDisguise.shared.isDuressActive, "Duress code starts the session")
        check(spaces.activeSpace == .main, "Duress code opens the main space")
        check(triggeredIds == [5], "Trigger carries the accounts to log out of")
        spaces.setDuressActive(false)

        // hideSecondSpace
        duress.setPanicAction(.hideSecondSpace)
        check(!duress.panic(), "Nothing to hide in the main space")
        spaces.setActiveSpace(.second)
        check(duress.panic(), "Hides the second space")
        check(spaces.activeSpace == .main, "Back in the main space")
        check(!ShadowDisguise.shared.isDuressActive, "Hiding the second space is not a clean session")

        // fullDisguise
        let previousMode = ShadowDisguise.shared.mode
        duress.setPanicAction(.fullDisguise)
        check(duress.panic(), "Full panic runs")
        check(ShadowDisguise.shared.isFull, "Full panic turns Full on")
        check(!duress.isPanicGestureActive, "No gesture in Full")
        check(!duress.panic(), "Panic does nothing in Full")
        duress.setCode("9753")
        check(!duress.verifyCode("9753"), "Duress code is off in Full")
        ShadowDisguise.shared.setMode(previousMode)

        NotificationCenter.default.removeObserver(token)
        NotificationCenter.default.removeObserver(triggerToken)
        spaces.setVisibility(.everywhere, accountPeerId: 1, peerIds: [10, 20])
        print("Shadow duress: \(count) checks passed")
    }
}

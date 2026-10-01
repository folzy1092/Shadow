import Foundation

@main
struct SpacesTests {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            count += 1
        }
        let suite = "shadow-spaces-tests-\(UInt64.random(in: 0 ... UInt64.max))"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ShadowSpaceStore(defaults: defaults)

        check(store.activeSpace == .main, "Starts in the main space")
        check(store.visibility(accountPeerId: 1, peerId: 10) == .everywhere, "Default visibility")
        check(!store.isHidden(accountPeerId: 1, peerId: 10), "Nothing hidden by default")

        store.setVisibility(.secondOnly, accountPeerId: 1, peerIds: [10])
        store.setVisibility(.mainOnly, accountPeerId: 1, peerIds: [20])
        check(store.isHidden(accountPeerId: 1, peerId: 10), "Second-only hidden in main")
        check(!store.isHidden(accountPeerId: 1, peerId: 20), "Main-only visible in main")
        check(!store.isHidden(accountPeerId: 2, peerId: 10), "Visibility is per account")
        check(store.hiddenPeerIds(accountPeerId: 1) == [10], "Hidden list in main")
        store.setActiveSpace(.second)
        check(store.hiddenPeerIds(accountPeerId: 1) == [20], "Hidden list in second")
        check(!store.isHidden(accountPeerId: 1, peerId: 10), "Second-only visible in second")
        check(store.isHidden(accountPeerId: 1, peerId: 20), "Main-only hidden in second")
        check(!store.isHidden(accountPeerId: 1, peerId: 30), "Everywhere visible in second")
        store.setSecondSpaceExclusive(true)
        check(store.isHidden(accountPeerId: 1, peerId: 30), "Exclusive second space hides everywhere-chats")
        check(!store.isHidden(accountPeerId: 1, peerId: 10), "Exclusive second space keeps second-only chats")
        store.setActiveSpace(.main)
        check(!store.isHidden(accountPeerId: 1, peerId: 30), "Exclusive mode does not affect the main space")
        check(ShadowSpaceStore(defaults: defaults).secondSpaceExclusive, "Exclusive mode persists")
        store.setSecondSpaceExclusive(false)

        let reloaded = ShadowSpaceStore(defaults: defaults)
        check(reloaded.visibility(accountPeerId: 1, peerId: 10) == .secondOnly, "Visibility persists")
        check(reloaded.activeSpace == .main, "Active space is not persisted")
        check(reloaded.customVisibilities(accountPeerId: 1).count == 2, "Custom list")
        store.setVisibility(.everywhere, accountPeerId: 1, peerIds: [20])
        check(store.customVisibilities(accountPeerId: 1) == [10: .secondOnly], "Everywhere is not stored")

        store.saveMuteState("unmuted", accountPeerId: 1, peerId: 10)
        store.saveMuteState("muted:5", accountPeerId: 1, peerId: 10)
        check(store.takeSavedMuteState(accountPeerId: 1, peerId: 10) == "unmuted", "First saved mute state wins")
        check(store.takeSavedMuteState(accountPeerId: 1, peerId: 10) == nil, "Saved mute state is taken once")

        check(ShadowSpaceStore.normalize("١٢٣٤") == "1234", "Arabic-Indic digits normalized")
        check(ShadowSpaceStore.validationError(code: "1234", format: .digits(4), mainCode: "1111") == nil, "Valid 4-digit code")
        check(ShadowSpaceStore.validationError(code: "123", format: .digits(4), mainCode: "1111") != nil, "Wrong length")
        check(ShadowSpaceStore.validationError(code: "12a4", format: .digits(4), mainCode: "1111") != nil, "Digits only")
        check(ShadowSpaceStore.validationError(code: "1111", format: .digits(4), mainCode: "1111") != nil, "Must differ from main code")
        check(ShadowSpaceStore.validationError(code: "secret", format: .text, mainCode: "other") == nil, "Valid text code")
        check(ShadowSpaceStore.validationError(code: "abc", format: .text, mainCode: "other") != nil, "Text code too short")

        check(!store.hasCode, "No code initially")
        check(store.setCode("2468"), "Code set")
        check(store.hasCode, "Has code")
        check(store.verifyCode("2468"), "Code verifies")
        check(store.verifyCode("٢٤٦٨"), "Code verifies with Arabic-Indic digits")
        check(!store.verifyCode("2469"), "Wrong code rejected")
        check(!store.verifyCode(""), "Empty code rejected")
        let stored = defaults.dictionary(forKey: "shadow.spaces.code.v1")
        check((stored?["hash"] as? Data) != nil && stored?["code"] == nil, "Only the hash is stored")

        store.setActiveSpace(.second)
        store.removeCode()
        check(!store.hasCode, "Code removed")
        check(store.activeSpace == .main, "Removing the code returns to main")
        check(store.customVisibilities(accountPeerId: 1).isEmpty, "Removing the code clears visibilities")

        print("Shadow spaces: \(count) checks passed")
    }
}

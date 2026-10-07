import Foundation

@main
struct ChatVoiceSpeedTests {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            count += 1
        }

        let suite = "shadow-chat-voice-speed-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ShadowChatVoiceSpeed(defaults: defaults)
        let friend = ShadowChatVoiceSpeed.chatKey(accountPeerId: 1, peerId: 42)
        let other = ShadowChatVoiceSpeed.chatKey(accountPeerId: 1, peerId: 7)
        let secondAccount = ShadowChatVoiceSpeed.chatKey(accountPeerId: 2, peerId: 42)

        check(store.rate(chat: friend) == nil, "No speed by default")
        store.set(chat: friend, rate: 1500)
        store.set(chat: other, rate: 2000)
        store.set(chat: secondAccount, rate: 1000)
        check(store.rate(chat: friend) == 1500, "Chat keeps its speed")
        check(ShadowChatVoiceSpeed(defaults: defaults).rate(chat: friend) == 1500, "Survives a restart")
        check(store.entries(accountPeerId: 1) == [.init(peerId: 7, rate: 2000), .init(peerId: 42, rate: 1500)], "Entries of one account")
        store.set(chat: friend, rate: 0)
        check(store.rate(chat: friend) == 1500, "Zero is ignored")

        store.remove(chat: friend)
        check(store.rate(chat: friend) == nil && store.rate(chat: other) == 2000, "Reset one chat")
        store.removeAll(accountPeerId: 1)
        check(store.entries(accountPeerId: 1).isEmpty, "Reset all of an account")
        check(store.rate(chat: secondAccount) == 1000, "Other accounts keep theirs")

        store.currentChat = friend
        check(store.currentChat == friend, "Current chat")
        store.currentChat = nil
        check(store.currentChat == nil, "No current chat")

        check(ShadowChatVoiceSpeed.title(rate: 1500) == "1.5x", "Title 1.5x")
        check(ShadowChatVoiceSpeed.title(rate: 1000) == "1x", "Title 1x")
        check(ShadowChatVoiceSpeed.title(rate: 1250) == "1.25x", "Title 1.25x")
        check(ShadowChatVoiceSpeed.title(rate: 2000) == "2x", "Title 2x")

        print("Chat voice speed: \(count) checks passed")
    }
}

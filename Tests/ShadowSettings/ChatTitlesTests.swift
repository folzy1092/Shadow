import Foundation

@main
struct ChatTitlesTests {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            count += 1
        }

        let suite = "shadow-chat-titles-tests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = ShadowChatTitleStore(defaults: defaults)

        check(store.title(accountPeerId: 1, peerId: 2) == nil, "No title at first")
        store.setTitle("  Работа  ", accountPeerId: 1, peerId: 2)
        check(store.title(accountPeerId: 1, peerId: 2) == "Работа", "Trimmed")
        check(store.title(accountPeerId: 1, peerId: 3) == nil && store.title(accountPeerId: 7, peerId: 2) == nil, "Per account and chat")
        check(ShadowChatTitleStore(defaults: defaults).title(accountPeerId: 1, peerId: 2) == "Работа", "Persisted")
        store.setTitle("   ", accountPeerId: 1, peerId: 2)
        check(store.title(accountPeerId: 1, peerId: 2) == nil, "Empty gives the real name back")
        check(ShadowChatTitleStore.normalized("a\nb") == "a b", "One line")
        check(ShadowChatTitleStore.normalized(String(repeating: "x", count: 100))?.count == ShadowChatTitleStore.maxLength, "Length limit")
        check(ShadowChatTitleStore.normalized(nil) == nil, "Nil")

        defaults.removePersistentDomain(forName: suite)
        print("Chat titles: \(count) checks passed")
    }
}

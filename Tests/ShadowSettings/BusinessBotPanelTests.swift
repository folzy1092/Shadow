import Foundation

@main
struct BusinessBotPanelTests {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            count += 1
        }

        typealias Panel = ShadowBusinessBotPanel

        // Only one of the two: it is shown as is, whatever the settings.
        check(Panel.arrangement(enabled: true, layout: 0, hasBot: false, hasPinned: false) == nil, "Nothing to show")
        check(Panel.arrangement(enabled: true, layout: 0, hasBot: true, hasPinned: false) == .bot, "Bot alone")
        check(Panel.arrangement(enabled: true, layout: 3, hasBot: true, hasPinned: false) == .bot, "Pinned only without a pin shows the bot")
        check(Panel.arrangement(enabled: false, layout: 0, hasBot: false, hasPinned: true) == .pinned, "Pinned alone")

        // Both.
        check(Panel.arrangement(enabled: false, layout: 0, hasBot: true, hasPinned: true) == .bot, "Off: stock Telegram, the bot wins")
        check(Panel.arrangement(enabled: true, layout: 0, hasBot: true, hasPinned: true) == .combined(.split), "Split")
        check(Panel.arrangement(enabled: true, layout: 1, hasBot: true, hasPinned: true) == .combined(.stacked), "Stacked")
        check(Panel.arrangement(enabled: true, layout: 2, hasBot: true, hasPinned: true) == .combined(.icon), "Icon")
        check(Panel.arrangement(enabled: true, layout: 3, hasBot: true, hasPinned: true) == .pinned, "Pinned only")
        check(Panel.arrangement(enabled: true, layout: 42, hasBot: true, hasPinned: true) == .combined(.split), "Unknown layout is split")

        check(Panel.Layout.normalized(-1) == .split && Panel.Layout.normalized(2) == .icon, "Normalized")
        check(Panel.layouts == [0, 1, 2, 3], "Four layouts")
        check(Set(Panel.Layout.allCases.map { $0.title }).count == 4, "Distinct titles")

        // Widths of a split row.
        check(Panel.splitBotWidth(totalWidth: 358.0, compact: false, contentWidth: 120.0) == 179.0, "Halves")
        check(Panel.splitBotWidth(totalWidth: 359.0, compact: false, contentWidth: 120.0) == 179.0, "Halves round down")
        check(Panel.splitBotWidth(totalWidth: 358.0, compact: true, contentWidth: 120.0) == 120.0, "Compact takes its content")
        check(Panel.splitBotWidth(totalWidth: 200.0, compact: true, contentWidth: 150.0) == 80.0, "The pinned message keeps its minimum")
        check(Panel.splitBotWidth(totalWidth: 100.0, compact: false, contentWidth: 50.0) == 0.0, "Too narrow: no bot")

        // A chat's own layout.
        check(Panel.effective(enabled: true, layout: 1, chatLayout: nil) == (true, 1), "No chat layout: global")
        check(Panel.effective(enabled: false, layout: 1, chatLayout: 3) == (true, 3), "Chat layout works with the toggle off")
        check(Panel.effective(enabled: false, layout: 1, chatLayout: 9) == (false, 1), "Unknown chat layout: global")
        let suite = "shadow-business-bot-chat-tests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = ShadowBusinessBotChatLayoutStore(defaults: defaults)
        check(store.layout(accountPeerId: 1, peerId: 2) == nil, "Nothing at first")
        store.setLayout(3, accountPeerId: 1, peerId: 2)
        check(store.layout(accountPeerId: 1, peerId: 2) == 3 && store.layout(accountPeerId: 1, peerId: 5) == nil, "Per chat")
        store.setLayout(nil, accountPeerId: 1, peerId: 2)
        check(store.layout(accountPeerId: 1, peerId: 2) == nil, "Back to global")
        defaults.removePersistentDomain(forName: suite)

        print("Business bot panel: \(count) checks passed")
    }
}

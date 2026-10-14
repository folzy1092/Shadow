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

        print("Business bot panel: \(count) checks passed")
    }
}

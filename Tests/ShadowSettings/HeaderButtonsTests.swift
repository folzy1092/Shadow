import Foundation

@main
struct HeaderButtonsTests {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            count += 1
        }

        let stock = ShadowHeaderButtons.stock
        check(stock.isStock, "Stock layout is stock")
        check(stock.left.map { $0.tap } == [.edit], "Stock left: edit")
        check(stock.right.map { $0.tap } == [.newStory, .ghostMode, .compose], "Stock right: story, ghost, compose")
        check(stock.right[1].longPress == .ghostSettings, "Ghost long press opens its settings")

        // JSON round-trip (the same Codable is stored in Postbox).
        var custom = ShadowHeaderButtons(left: [], right: [
            ShadowHeaderButton(tap: .readAllLocal, longPress: .readAllServer),
            ShadowHeaderButton(tap: .customLink, tapLink: "@durov", icon: "star")
        ])
        let data = try! JSONEncoder().encode(custom)
        let decoded = try! JSONDecoder().decode(ShadowHeaderButtons.self, from: data)
        check(decoded == custom, "Round-trip")
        check(!decoded.isStock, "Custom layout is not stock")

        // Unknown actions from a newer build read as none and are dropped.
        let future = "{\"left\":[{\"tap\":\"teleport\"}],\"right\":[{\"tap\":\"compose\",\"longPress\":\"fly\"}]}".data(using: .utf8)!
        let parsed = try! JSONDecoder().decode(ShadowHeaderButtons.self, from: future).normalized()
        check(parsed.left.isEmpty, "Unknown tap action is dropped")
        check(parsed.right.first?.tap == .compose && parsed.right.first?.longPress == ShadowHeaderAction.none, "Unknown long press reads as none")

        // Limits.
        custom.left = Array(repeating: ShadowHeaderButton(tap: .search), count: 5)
        custom.right = Array(repeating: ShadowHeaderButton(tap: .search), count: 5)
        let limited = custom.normalized()
        check(limited.left.count == ShadowHeaderButtons.maxLeft && limited.right.count == ShadowHeaderButtons.maxRight, "Limits enforced")

        // Missing keys fall back to the stock layout.
        let empty = try! JSONDecoder().decode(ShadowHeaderButtons.self, from: "{}".data(using: .utf8)!)
        check(empty.isStock, "Empty object is stock")

        // Identity changes with the configuration.
        check(ShadowHeaderButton(tap: .search).identityKey != ShadowHeaderButton(tap: .search, longPress: .compose).identityKey, "Identity includes long press")

        // Links.
        check(ShadowHeaderButtons.normalizedLink("@durov") == "https://t.me/durov", "@username")
        check(ShadowHeaderButtons.normalizedLink("durov") == "https://t.me/durov", "Bare username")
        check(ShadowHeaderButtons.normalizedLink("t.me/durov") == "https://t.me/durov", "t.me")
        check(ShadowHeaderButtons.normalizedLink("shadow://deleted") == "shadow://deleted", "shadow://")
        check(ShadowHeaderButtons.normalizedLink("tg://resolve?domain=durov") == "tg://resolve?domain=durov", "tg://")
        check(ShadowHeaderButtons.normalizedLink("https://example.com") == "https://example.com", "https")
        check(ShadowHeaderButtons.normalizedLink("") == nil, "Empty")
        check(ShadowHeaderButtons.normalizedLink("not a link") == nil, "Spaces")
        check(ShadowHeaderButtons.normalizedLink("ab") == nil, "Too short username")

        check(Set(ShadowHeaderAction.selectable).count == ShadowHeaderAction.selectable.count, "No duplicate actions")
        check(!ShadowHeaderAction.selectable.contains(.none), "None is not selectable as a tap")
        check(ShadowHeaderAction.selectable.count == ShadowHeaderAction.allCases.count - 4, "Every action except none and the three legacy toggles is offered")
        check(ShadowHeaderAction.selectable.contains(.setting), "Toggles can be put on a button")

        // Several steps per gesture.
        var multi = ShadowHeaderButton(tapSteps: [ShadowHeaderStep(.setting, link: "shadow://ghost/typing?switch"), ShadowHeaderStep(.setting, link: "shadow://ghost/scheduled?switch")], icon: "pencil.circle")
        let multiData = try! JSONEncoder().encode(multi)
        check(try! JSONDecoder().decode(ShadowHeaderButton.self, from: multiData) == multi, "Steps round-trip")
        let legacyView = try! JSONSerialization.jsonObject(with: multiData) as! [String: Any]
        check(legacyView["tap"] as? String == "setting", "First step is also written the 1.1.0 way")
        let old = "{\"tap\":\"readAllLocal\",\"longPress\":\"compose\"}".data(using: .utf8)!
        let oldButton = try! JSONDecoder().decode(ShadowHeaderButton.self, from: old)
        check(oldButton.tapSteps.map { $0.action } == [.readAllLocal] && oldButton.longPressSteps.map { $0.action } == [.compose], "1.1.0 buttons decode")
        multi.tapSteps = Array(repeating: ShadowHeaderStep(.search), count: 9)
        check(multi.normalized().tapSteps.count == ShadowHeaderButton.maxSteps, "Step limit")
        multi.tap = .compose
        check(multi.tapSteps.first?.action == .compose, "Setting tap replaces the first step")
        check(ShadowHeaderButtons.iconPresets.count >= 12 && ShadowHeaderButtons.iconPresets.contains("shadow"), "Icon presets include the Shadow logo")

        print("Header buttons: \(count) checks passed")
    }
}

import Foundation

@main
struct DisguiseTests {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            count += 1
        }
        let suite = "shadow-disguise-tests-\(UInt64.random(in: 0 ... UInt64.max))"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let disguise = ShadowDisguise(defaults: defaults)
        check(disguise.mode == .off, "Off by default")
        check(!disguise.hidesSettings && !disguise.isFull, "Nothing hidden by default")

        disguise.setMode(.settings)
        check(disguise.hidesSettings && !disguise.isFull, "Settings mode hides only the settings")
        disguise.setMode(.full)
        check(disguise.hidesSettings && disguise.isFull, "Full mode hides everything")
        check(ShadowDisguise(defaults: defaults).mode == .full, "Mode persists")

        defaults.set(99, forKey: "shadow.disguise.mode.v1")
        check(ShadowDisguise(defaults: defaults).mode == .off, "Unknown stored value reads as off")

        check(!ShadowDisguise.requiresAuthentication(from: .off, to: .off), "No change, no prompt")
        check(!ShadowDisguise.requiresAuthentication(from: .off, to: .settings), "Hiding the settings needs no prompt")
        check(ShadowDisguise.requiresAuthentication(from: .off, to: .full), "Entering Full asks")
        check(ShadowDisguise.requiresAuthentication(from: .settings, to: .full), "Entering Full from settings asks")
        check(ShadowDisguise.requiresAuthentication(from: .settings, to: .off), "Showing the settings again asks")
        check(ShadowDisguise.requiresAuthentication(from: .full, to: .off), "Leaving Full asks")
        check(ShadowDisguise.requiresAuthentication(from: .full, to: .settings), "Leaving Full for settings asks")

        print("Shadow disguise: \(count) checks passed")
    }
}

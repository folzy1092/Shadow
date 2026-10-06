import Foundation

@main
struct SettingLinksTests {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            count += 1
        }

        let all = ShadowSettingLinks.all
        check(all.count >= 70, "Every toggle has a link")
        check(Set(all.map { $0.screen + "/" + $0.slug }).count == all.count, "Paths are unique")
        check(Set(all.map { $0.screen + "#" + String($0.entryId) }).count == all.count, "Entry ids are unique per screen")
        for link in all {
            check(link.slug == link.slug.lowercased(), "Slug is lowercase: \(link.slug)")
            check(ShadowSettingLinks.screenTitles[link.screen] != nil, "Screen has a title: \(link.screen)")
            check(ShadowLinks.parse(link.path)?.command == link.screen, "Path parses: \(link.path)")
            if link.isProtected {
                check(!link.isSwitchable, "Protected never switches: \(link.slug)")
            }
        }

        check(ShadowSettingLinks.mode(query: [:]) == .open, "No query opens")
        check(ShadowSettingLinks.mode(query: ["on": ""]) == .on, "?on")
        check(ShadowSettingLinks.mode(query: ["off": ""]) == .off, "?off")
        check(ShadowSettingLinks.mode(query: ["switch": ""]) == .toggle, "?switch")
        check(ShadowSettingLinks.mode(query: ["state": "on"]) == .on, "?state=on")

        let typing = ShadowSettingLinks.resolve("shadow://ghost/typing?switch")
        check(typing?.0.key == "hideTyping" && typing?.1 == .toggle, "Ghost typing switch")
        check(ShadowSettingLinks.resolve("tg://shadow/ghost/typing?off")?.1 == .off, "tg://shadow form")
        check(ShadowSettingLinks.resolve("SHADOW://Ghost/Typing")?.1 == .open, "Case-insensitive")
        check(ShadowSettingLinks.resolve("shadow://ghost") == nil, "Screen alone is not a toggle")
        check(ShadowSettingLinks.resolve("shadow://ghost/nope") == nil, "Unknown toggle")
        check(ShadowSettingLinks.find(screen: "ghost", entryId: 3)?.slug == "typing", "Find by entry id")
        check(ShadowSettingLinks.find(screen: "locks", slug: "hide-preview")?.isSwitchable == false, "Locks only open")
        check(typing?.0.link(.on) == "shadow://ghost/typing?on", "Link with mode")

        check(ShadowSettingLinks.groupTarget(currentValues: [true, true]) == false, "All on → off")
        check(ShadowSettingLinks.groupTarget(currentValues: [true, false]) == true, "Mixed → on")
        check(ShadowSettingLinks.groupTarget(currentValues: [false, false]) == true, "All off → on")

        print("Setting links: \(count) checks passed")
    }
}

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

        // Links of newer settings carry the version they need (?v=).
        let timecode = ShadowSettingLinks.resolve("shadow://customization/reply-timecode?on&v=1.4.4")
        check(timecode?.0.key == "replyTimecode" && timecode?.1 == .on, "?v= does not change the mode")
        check(timecode?.0.link(.on) == "shadow://customization/reply-timecode?on&v=1.4.4", "Link carries the version")
        check(timecode?.0.link(.open) == "shadow://customization/reply-timecode?v=1.4.4", "Open link carries the version")
        check(ShadowSettingLinks.resolve("shadow://customization/reply-timecode-mode?value=0")?.1 == .value(0), "Timecode mode choice")
        check(ShadowSettingLinks.compareVersions("1.4.10", "1.4.9") == .orderedDescending, "Versions compare by number")
        check(ShadowSettingLinks.compareVersions("1.4", "1.4.0") == .orderedSame, "Missing parts are zero")
        check(ShadowSettingLinks.needsUpdate(linkVersion: "1.4.4", current: "1.4.3"), "Newer link needs an update")
        check(!ShadowSettingLinks.needsUpdate(linkVersion: "1.4.3", current: "1.4.3") && !ShadowSettingLinks.needsUpdate(linkVersion: nil, current: "1.4.3"), "Same or unknown version")
        check(ShadowSettingLinks.unsupportedText(isSetting: true, linkVersion: "1.4.4", current: "1.4.3") == "Эта настройка работает с Shadow 1.4.4. У вас 1.4.3 — обновите Shadow.", "Needs a newer version")
        check(ShadowSettingLinks.unsupportedText(isSetting: true, linkVersion: nil, current: "1.4.3").hasPrefix("Такой настройки нет в Shadow 1.4.3."), "Unknown setting")
        check(ShadowSettingLinks.unsupportedText(isSetting: false, linkVersion: "1.4.3", current: "1.4.3").hasPrefix("Такой ссылки нет в Shadow 1.4.3."), "Unknown link")
        check(ShadowSettingLinks.isScreen("Customization") && !ShadowSettingLinks.isScreen("gift"), "Settings screens")

        let voice = ShadowSettingLinks.resolve("shadow://customization/voice-time?value=2")
        check(voice?.0.isChoice == true && voice?.1 == .value(2), "Choice with ?value")
        check(voice?.0.choiceTitle(2) == "Прошло / всего", "Choice title")
        check(voice?.0.isSwitchable == false, "A choice is not a toggle")
        check(ShadowSettingLinks.resolve("shadow://customization/voice-time?value=9")?.1 == .open, "Unknown value only opens")
        check(ShadowSettingLinks.resolve("shadow://customization/voice-time?switch")?.1 == .open, "?switch on a choice only opens")
        check(ShadowSettingLinks.resolve("shadow://ghost/typing?value=1")?.1 == .open, "?value on a toggle only opens")
        check(ShadowSettingLinks.mode(query: ["set": "3"]) == .value(3), "?set=N")
        check(voice?.0.link(.value(4)) == "shadow://customization/voice-time?value=4", "Link with a value")
        check(ShadowSettingLinks.resolve("shadow://customization/bottom-bar-hiding?value=3")?.1 == .value(3), "Bottom bar hiding choice")
        check(ShadowSettingLinks.resolve("shadow://customization/header-buttons")?.0.key == nil, "Open-only setting")
        check(ShadowSettingLinks.resolve("shadow://customization/voice-time-player?on")?.1 == .on, "Player time toggle")

        check(ShadowSettingLinks.groupTarget(currentValues: [true, true]) == false, "All on → off")
        check(ShadowSettingLinks.groupTarget(currentValues: [true, false]) == true, "Mixed → on")
        check(ShadowSettingLinks.groupTarget(currentValues: [false, false]) == true, "All off → on")

        print("Setting links: \(count) checks passed")
    }
}

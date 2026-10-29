import Foundation

@main
struct ActivityImitationTests {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            count += 1
        }

        typealias Mode = ShadowActivityImitationMode

        check(Mode.menuOrder.count == Mode.allCases.count, "Every mode is in the menu")
        check(Set(Mode.menuOrder.map { $0.rawValue }).count == Mode.menuOrder.count, "No duplicates in the menu")
        check(Mode.menuOrder.first == .typing && Mode.menuOrder.last == .random, "Typing first, random last")
        check(!Mode.concrete.contains(.random) && Mode.concrete.count == Mode.allCases.count - 1, "Random picks concrete actions")
        check(Mode.allCases.allSatisfy { !$0.title.isEmpty && !$0.icon.isEmpty }, "Titles and icons")

        check(Mode.available(secretChat: true) == [.typing], "Secret chats only type")
        check(Mode.available(secretChat: false) == Mode.menuOrder, "Other chats get everything")

        check(Mode.recordingVoice.resolved(randomIndex: 5) == .recordingVoice, "Concrete stays")
        check(Mode.random.resolved(randomIndex: 0) == Mode.concrete[0], "Random index 0")
        check(Mode.random.resolved(randomIndex: Mode.concrete.count) == Mode.concrete[0], "Random wraps")
        check(Mode.random.resolved(randomIndex: -1) == Mode.concrete[Mode.concrete.count - 1], "Negative index wraps")
        check((0 ..< 200).allSatisfy { Mode.random.resolved(randomIndex: $0) != .random }, "Random never resolves to random")

        check(Mode.progress(tick: 0) == 0 && Mode.progress(tick: 1) == 7, "Progress climbs")
        check((0 ..< 100).allSatisfy { (0 ..< 100).contains(Mode.progress(tick: $0)) }, "Progress stays a percentage")
        check(Mode.progress(tick: -3) == 0, "Negative tick")
        check(Mode.sendingPhoto.hasProgress && Mode.importingHistory.hasProgress && !Mode.typing.hasProgress && !Mode.recordingRound.hasProgress, "Progress only for uploads")
        check(Mode.repeatInterval > 1.0 && Mode.repeatInterval < 6.0, "Repeats before the action expires")

        // Paperclip menu (ShadowPaperclip).
        typealias Clip = ShadowPaperclip
        check(Clip.parseActions(Clip.defaultActions) == [.imitation(.typing), .imitation(.recordingVoice), .imitation(.recordingRound)], "Default actions")
        check(Clip.parseActions("a1,a1,zz,a99,,pkartinki5222/93,pKARTINKI5222/93,p/1,pbad/x") == [.imitation(.recordingVoice), .prank(id: "kartinki5222/93")], "Bad, unknown and duplicate actions dropped")
        let many = (0 ..< 30).map { "a\($0 % 15)" }.joined(separator: ",") + "," + (1 ... 30).map { "pchannel/\($0)" }.joined(separator: ",")
        check(Clip.parseActions(many).count == Clip.maxActions, "At most 20 actions")
        check(Clip.normalizedActions(" a2 ,a0") == "a2,a0", "Order kept, spaces trimmed")
        let full = Clip.parseActions(many)
        check(Clip.toggled(full, .imitation(.playingGame)) == nil || full.contains(.imitation(.playingGame)), "No 21st action")
        check(Clip.toggled([.imitation(.typing)], .imitation(.typing)) == [], "Uncheck")
        check(Clip.toggled([.imitation(.typing)], .prank(id: "a/1")) == [.imitation(.typing), .prank(id: "a/1")], "Check appends")
        check(Clip.encodeActions([.imitation(.recordingRound), .prank(id: "kartinki5222/93")]) == "a2,pkartinki5222/93", "Encode")
        // 1.15.0: chat tools.
        check(Clip.parseActions("t0,t1,t2,t9,tx,t1") == [.tool(.scrollToStart), .tool(.mentionAll), .tool(.translate)], "Tools parsed, unknown and duplicate dropped")
        check(Clip.encodeActions([.tool(.mentionAll), .imitation(.typing)]) == "t1,a0", "Tools encoded")
        check(Clip.menuActions([.tool(.scrollToStart), .prank(id: "gone/1")], pranks: []) == [.tool(.scrollToStart)], "Tools always stay in the menu")

        check(Clip.parsePrankLink("https://t.me/kartinki5222/93").map { "\($0.channel)/\($0.messageId)" } == "kartinki5222/93", "Plain link")
        check(Clip.parsePrankLink(" t.me/kartinki5222/93?single ").map { "\($0.channel)/\($0.messageId)" } == "kartinki5222/93", "Query dropped")
        check(Clip.parsePrankLink("@kartinki5222/93/").map { "\($0.channel)/\($0.messageId)" } == "kartinki5222/93", "At sign and slash")
        check(Clip.parsePrankLink("https://t.me/c/123456/7") == nil, "Private link refused")
        check(Clip.parsePrankLink("https://t.me/kartinki5222") == nil, "Channel without a post")
        check(Clip.parsePrankLink("https://t.me/abc/1") == nil, "Too short a username")
        check(Clip.parsePrankLink("https://t.me/kartinki5222/0") == nil, "Post 0")

        let pranks = Clip.parsePranks([["title": "Долгое голосовое", "url": "https://t.me/kartinki5222/93"], ["title": "Дубль", "url": "t.me/Kartinki5222/93"], ["url": "https://t.me/ayugram_easter/5"], ["title": "Плохая", "url": "nope"]])
        check(pranks.count == 2, "Bad and duplicate pranks dropped")
        check(pranks[0].title == "Долгое голосовое" && pranks[0].id == "kartinki5222/93" && pranks[0].url == "https://t.me/kartinki5222/93", "Prank fields")
        check(pranks[1].title == "Прикол", "Untitled prank")
        check(Clip.parsePranks(Clip.encodePranks(pranks)) == pranks, "Pranks round-trip")
        check(Clip.parsePranks(nil).isEmpty && Clip.parsePranks("x").isEmpty, "No catalog")
        check(Clip.menuActions([.prank(id: "gone/1"), .imitation(.typing), .prank(id: "kartinki5222/93")], pranks: pranks) == [.imitation(.typing), .prank(id: "kartinki5222/93")], "Removed pranks leave the menu")

        check(Clip.normalizedPrankSeconds(0) == 1 && Clip.normalizedPrankSeconds(5) == 5 && Clip.normalizedPrankSeconds(500) == 60, "Seconds clamped")
        check(Clip.imitationMode(for: .voice) == .recordingVoice && Clip.imitationMode(for: .roundVideo) == .recordingRound && Clip.imitationMode(for: .text) == .typing, "Prank imitation by media")

        // 1.14.0: «отправляет…» after «записывает…», and the user's own pranks.
        check(Clip.normalizedPrankSendSeconds(-1) == 0 && Clip.normalizedPrankSendSeconds(2) == 2 && Clip.normalizedPrankSendSeconds(90) == 60, "Sending seconds clamped, 0 allowed")
        check(Clip.sendingMode(for: .voice) == .sendingAudio && Clip.sendingMode(for: .roundVideo) == .sendingRound, "Voice and round video are then sent")
        check(Clip.sendingMode(for: .photo) == nil && Clip.sendingMode(for: .text) == nil, "Other pranks have no second phase")
        var mine: [Clip.Prank] = []
        if case let .success(updated) = Clip.addingUserPrank(mine, title: "  Моё гс  ", link: "https://t.me/MyChannel/7?single") {
            mine = updated
        }
        check(mine.count == 1 && mine[0].title == "Моё гс" && mine[0].id == "mychannel/7", "User prank added from a link")
        check(Clip.addingUserPrank(mine, title: "", link: "t.me/mychannel/7") == .failure(.duplicate), "Same post twice")
        check(Clip.addingUserPrank(mine, title: "x", link: "https://t.me/c/123/4") == .failure(.badLink), "Private channel links are refused")
        check(Clip.addingUserPrank(mine, title: "x", link: "hello") == .failure(.badLink), "Not a link")
        if case let .success(updated) = Clip.addingUserPrank(mine, title: "", link: "@other_chan/2") {
            check(updated[1].title == "Прикол", "Untitled user prank")
        } else {
            check(false, "Second user prank")
        }
        let fullPranks = (1 ... Clip.maxPranks).map { Clip.Prank(title: "p", channel: "chan_\($0)", messageId: 1) }
        check(Clip.addingUserPrank(fullPranks, title: "x", link: "t.me/another/1") == .failure(.full), "At most maxPranks")
        let merged = Clip.mergedPranks(user: mine, catalog: [Clip.Prank(title: "Каталог", channel: "MyChannel", messageId: 7), Clip.Prank(title: "Другой", channel: "kartinki5222", messageId: 93)])
        check(merged.map { $0.id } == ["mychannel/7", "kartinki5222/93"] && merged[0].title == "Моё гс", "User pranks first, catalog duplicates dropped")
        check(Clip.removingUserPrank(mine, id: "mychannel/7").isEmpty, "User prank removed")

        print("ActivityImitationTests: \(count) checks passed")
    }
}

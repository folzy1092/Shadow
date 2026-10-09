import Foundation

@main
struct ChatStatsTests {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            count += 1
        }
        typealias S = ShadowChatStats
        let me: Int64 = 1
        let friend: Int64 = 2
        let utc = S.Clock(offset: 0)
        // 2026-10-05 00:00 UTC is a Monday.
        let monday: Int32 = 1_791_158_400

        // Clock.
        check(utc.weekday(monday) == 0, "Monday is 0")
        check(utc.weekday(monday + 6 * 86400) == 6, "Sunday is 6")
        check(utc.hour(monday + 23 * 3600 + 59) == 23, "Hour")
        check(utc.day(monday + 86399) == utc.day(monday), "Same day until midnight")
        check(utc.morningDay(monday + 3 * 3600) == utc.day(monday) - 1, "Before 4:00 belongs to the previous day")
        let moscow = S.Clock(offset: 3 * 3600)
        check(moscow.day(monday - 2 * 3600) == utc.day(monday), "22:00 UTC is already the next day in Moscow")
        check(utc.day(-1) == -1, "Negative timestamps floor")
        let (year, month) = utc.yearMonth(day: utc.day(monday))
        check(year == 2026 && month == 10, "Year and month")

        // Text.
        check(S.words(in: "Го завтра в кино, https://x.ru @bob 42") == ["го", "завтра", "в", "кино"], "Words skip links, mentions, numbers")
        check(S.emoji(in: "ахах 😂😂 ❤️ 1 #") == ["😂", "😂", "❤️"], "Emoji, not digits or #")
        check(S.isEmoji("👍🏽"), "Skin tone emoji")
        check(!S.isEmoji("a") && !S.isEmoji("5"), "Letters and digits are not emoji")

        // Streaks.
        let today: Int32 = 100
        check(S.streaks(days: [98, 99, 100], today: today) == (3, 3), "Run ending today")
        check(S.streaks(days: [97, 98, 99], today: today) == (3, 3), "Today not over yet keeps the run")
        check(S.streaks(days: [90, 91, 92, 93, 97, 98], today: today) == (0, 4), "Broken run")
        check(S.streaks(days: [], today: today) == (0, 0), "Empty")

        check(S.median([5, 1, 3]) == 3 && S.median([1, 2, 3, 10]) == 2 && S.median([]) == nil, "Median")

        // Builder.
        let builder = S.Builder(accountPeerId: me, peerId: friend, title: "Матвей", isGroup: false, period: .week, from: monday, to: monday + 7 * 86400 - 1, names: [me: "Я", friend: "Матвей"], clock: utc)
        // Day 1: friend starts at 10:00, I answer 2 min later, he answers 10 min later.
        builder.add(S.Item(timestamp: monday + 10 * 3600, authorId: friend, text: "Привет 😂 го завтра"))
        builder.add(S.Item(timestamp: monday + 10 * 3600 + 120, authorId: me, text: "го", isReply: true, reactions: [S.Reaction(authorId: friend, key: "👍")]))
        builder.add(S.Item(timestamp: monday + 10 * 3600 + 720, authorId: friend, kind: .voice, duration: 45))
        // Day 2: only me writes, then he answers after 7 hours (not a reply time).
        builder.add(S.Item(timestamp: monday + 86400 + 9 * 3600, authorId: me, kind: .sticker, stickerKey: "sticker:7", stickerLabel: "🐸"))
        builder.add(S.Item(timestamp: monday + 86400 + 16 * 3600, authorId: friend, text: "ок", isForward: true))
        // Day 3: a night message from me (02:00), a deleted one, a call.
        builder.add(S.Item(timestamp: monday + 2 * 86400 + 2 * 3600, authorId: me, text: "не сплю", hasLink: false, isDeleted: true))
        builder.add(S.Item(timestamp: monday + 2 * 86400 + 12 * 3600, authorId: friend, kind: .call, duration: 300))
        builder.add(S.Item(timestamp: monday + 2 * 86400 + 13 * 3600, authorId: friend, kind: .round, duration: 20, isEdited: true))
        // Out of the period: ignored.
        builder.add(S.Item(timestamp: monday - 10, authorId: me, text: "старое"))

        let report = builder.build(generated: monday + 2 * 86400 + 20 * 3600)
        check(report.people.first?.id == me, "Me first in a private chat")
        check(report.total == 7, "Calls are not messages, old messages ignored")
        guard let mine = report.me, let his = report.other else {
            preconditionFailure("Both people present")
        }
        check(mine.messages == 3 && his.messages == 4, "Messages per person")
        check(his.calls == 1 && his.callSeconds == 300, "Calls")
        check(his.voiceCount == 1 && his.voiceSeconds == 45, "Voice")
        check(his.roundCount == 1 && his.roundSeconds == 20 && his.edited == 1, "Round video, edited")
        check(mine.stickers == 1 && mine.topStickers == [S.Count(key: "sticker:7", count: 1, label: "🐸")], "Sticker with its emoji")
        check(his.forwards == 1, "Forward")
        check(his.words == 3, "Forwarded text is not his words")
        check(mine.replies == 1 && mine.deleted == 1 && mine.night == 1, "Reply, deleted, night")
        check(his.reactions == [S.Count(key: "👍", count: 1)], "Reaction counted for who reacted")
        check(his.emoji == [S.Count(key: "😂", count: 1)], "Emoji")
        check(his.topWords.map { $0.key }.contains("привет") && !his.topWords.map { $0.key }.contains("в"), "Top words without stop words")
        // Reply times: mine 120 s; his 600 s (the 7 h pause is not a reply time).
        check(mine.replySeconds == 120 && mine.replySamples == 1, "My reply time")
        check(his.replySeconds == 600 && his.replySamples == 1, "His reply time, long pauses skipped")
        // First of the day: day 1 him, day 2 me, day 3 him (02:00 still belongs to day 2).
        check(his.firstOfDay == 2 && mine.firstOfDay == 1 && report.firstOfDayDays == 3, "First message of the day")
        check(report.daysWithMessages == 3, "Days with messages")
        check(report.daysInPeriod == 7, "Days in a week")
        check(report.streakCurrent == 3 && report.streakBest == 3, "Both wrote on all three days")
        check(report.longestBreak == 82080 && report.longestBreakFrom == monday + 10 * 3600 + 720, "Longest break: day 1 10:12 to day 2 9:00")
        check(report.timelineLabels.count == 7 && mine.timeline.reduce(0, +) == mine.messages, "Daily timeline")
        check(report.heatmap.count == 7 && report.heatmap[0].count == 24 && report.heatmap.flatMap { $0 }.reduce(0, +) == 7, "Heatmap")
        check(report.bestDay?.count == 3, "Best day")

        // Year: monthly buckets.
        let yearBuilder = S.Builder(accountPeerId: me, peerId: friend, title: "Матвей", isGroup: false, period: .year, from: monday - 364 * 86400, to: monday, names: [me: "Я", friend: "Матвей"], clock: utc)
        yearBuilder.add(S.Item(timestamp: monday - 100 * 86400, authorId: me, text: "a"))
        let yearReport = yearBuilder.build(generated: monday)
        check(yearReport.timelineLabels.count == 13, "Year spans 13 calendar months")
        check(yearReport.me?.timeline.reduce(0, +) == 1, "Monthly timeline")

        // Group: everyone who wrote, sorted by messages.
        let group = S.Builder(accountPeerId: me, peerId: -5, title: "Группа", isGroup: true, period: .week, from: monday, to: monday + 7 * 86400, names: [me: "Я", 3: "Глеб"], clock: utc)
        group.add(S.Item(timestamp: monday + 100, authorId: 3, text: "a"))
        group.add(S.Item(timestamp: monday + 200, authorId: 3, text: "b"))
        group.add(S.Item(timestamp: monday + 300, authorId: me, text: "c"))
        group.add(S.Item(timestamp: monday + 400, authorId: 4, text: "d"))
        let groupReport = group.build(generated: monday + 500)
        check(groupReport.people.map { $0.id } == [3, me, 4], "Group leaderboard order")
        check(groupReport.people.last?.name == "Участник", "Unknown name")
        check(groupReport.streakBest == 0, "No streak in groups")

        // Anonymous copy and storage.
        let anonymous = S.anonymized(report)
        check(anonymous.other?.name == "Собеседник" && anonymous.me?.name == "Я" && anonymous.title == "Собеседник", "Anonymous names")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("shadow-chat-stats-tests-\(UUID().uuidString)")
        let store = ShadowChatStatsStore(directory: directory)
        store.save(report)
        var second = report
        second.peerId = 9
        second.generated += 10
        store.save(second)
        store.save(report)
        check(store.reports(accountPeerId: me).count == 2, "One report per chat")
        check(store.reports(accountPeerId: me).first?.peerId == 9, "Newest first")
        check(store.report(accountPeerId: me, peerId: friend) == report, "Round trip")
        store.remove(accountPeerId: me, peerId: 9)
        check(store.reports(accountPeerId: me).count == 1, "Remove")
        try? FileManager.default.removeItem(at: directory)

        // The page: data inside, placeholders replaced, script not closable.
        var hostile = report
        hostile.title = "</script><b>Матвей</b>"
        let page = ShadowChatStatsPage.render(hostile, options: ShadowChatStatsPage.Options(mode: .file))
        check(!page.contains("__REPORT__") && !page.contains("__CONFIG__") && !page.contains("__TITLE__"), "Placeholders replaced")
        check(page.contains("const R = {") && page.contains("\"mode\":\"file\""), "Data and config embedded")
        check(!page.contains("</script><b>"), "Data cannot close the script")
        check(page.contains("<title>Итоги — &lt;/script&gt;"), "Title escaped")
        let card = ShadowChatStatsPage.render(report, options: ShadowChatStatsPage.Options(mode: .card, dark: true, card: .other, hideName: true))
        check(card.contains("\"card\":\"other\"") && card.contains("\"hideName\":true") && card.contains("\"theme\":\"dark\""), "Card config")
        let fileName = ShadowChatStatsPage.fileName(hostile)
        check(fileName.hasPrefix("Итоги — ") && fileName.hasSuffix(".html") && !fileName.dropLast(5).contains("<") && !fileName.contains("/"), "File name without forbidden characters")
        // 1.11.0: records. Longest text is his "Привет 😂 го завтра" (18
        // characters; the forwarded "ок" does not count), the busiest hour is
        // day 1 10:00 with 3 messages.
        func rec(_ kind: String) -> S.Record? { return report.records?.first(where: { $0.kind == kind }) }
        check(rec("text") == S.Record(kind: "text", authorId: friend, value: 18, timestamp: monday + 10 * 3600), "Longest message")
        check(rec("voice")?.value == 45 && rec("round")?.value == 20 && rec("call") == S.Record(kind: "call", authorId: friend, value: 300, timestamp: monday + 2 * 86400 + 12 * 3600), "Longest voice, round, call")
        check(rec("hour") == S.Record(kind: "hour", authorId: 0, value: 3, timestamp: monday + 10 * 3600), "Busiest hour")
        check(report.records?.map { $0.kind } == ["text", "voice", "round", "call", "hour"], "Record order")

        // Typical day (days from 4:00): day 1 10:00–10:12 (3), day 2 9:00 to
        // 02:00 next night (3), day 3 13:00 (1).
        check(report.typicalDay == S.TypicalDay(days: 3, messages: 3, startMinute: 600, endMinute: 780, spanMinutes: 12, busyWeekday: 0, quietWeekday: 3), "Typical day medians")

        // Who waits: his long waits 22 h 48 min and 10 h, one turn left
        // unanswered at the end; my long waits 7 h and 11 h.
        check(mine.waitLongCount == 2 && mine.waitTotalSeconds == 64800 && mine.unanswered == 0, "My waits")
        check(mine.waitLongest == 39600 && mine.waitLongestAt == monday + 2 * 86400 + 2 * 3600, "My longest wait")
        check(his.waitLongCount == 2 && his.waitTotalSeconds == 118080 && his.unanswered == 1 && his.waitLongest == 82080, "His waits")

        // Mood: his 😂 and his 👍 reaction; too few emoji for a timeline mood.
        check(his.moods == [S.Count(key: "joy", count: 1), S.Count(key: "laugh", count: 1)] && mine.moods == [], "Moods")
        check(report.moodTimeline?.count == 7 && report.moodTimeline?.allSatisfy({ $0.isEmpty }) == true, "Mood timeline needs 3 emoji")
        check(S.mood(of: "👍🏽") == .joy && S.mood(of: "❤️") == .love && S.mood(of: "❤") == .love && S.mood(of: "a") == nil, "Mood of an emoji")

        // Words only one side uses (at least twice, never by the other).
        let words = S.Builder(accountPeerId: me, peerId: friend, title: "Матвей", isGroup: false, period: .week, from: monday, to: monday + 86400, names: [me: "Я", friend: "Матвей"], clock: utc)
        words.add(S.Item(timestamp: monday + 10, authorId: me, text: "жиза жиза ок"))
        words.add(S.Item(timestamp: monday + 20, authorId: friend, text: "ок ок норм"))
        let wordsReport = words.build(generated: monday + 100)
        check(wordsReport.me?.uniqueWords == [S.Count(key: "жиза", count: 2)] && wordsReport.other?.uniqueWords == [], "Unique words")

        // Groups: who replies to whom; replies to oneself do not count.
        let replies = S.Builder(accountPeerId: me, peerId: -5, title: "Группа", isGroup: true, period: .week, from: monday, to: monday + 86400, names: [me: "Я", 3: "Глеб"], clock: utc)
        replies.add(S.Item(timestamp: monday + 10, authorId: 3, text: "a", isReply: true, replyToAuthorId: me))
        replies.add(S.Item(timestamp: monday + 20, authorId: 3, text: "b", isReply: true, replyToAuthorId: me))
        replies.add(S.Item(timestamp: monday + 30, authorId: me, text: "c", isReply: true, replyToAuthorId: 3))
        replies.add(S.Item(timestamp: monday + 40, authorId: 4, text: "d", isReply: true, replyToAuthorId: 4))
        let repliesReport = replies.build(generated: monday + 100)
        check(repliesReport.replyPairs == [S.ReplyPair(from: 3, to: me, count: 2), S.ReplyPair(from: me, to: 3, count: 1)], "Reply pairs")
        check(report.replyPairs == nil && repliesReport.me?.waitLongCount == nil, "No reply pairs in private chats, no waits in groups")

        // Previous period summary and the two weeks.
        let summary = S.summary(report)
        check(summary.total == 7 && summary.daysWithMessages == 3 && summary.calls == 1 && summary.callSeconds == 300 && summary.people.count == 2, "Summary")
        let now = monday + 20 * 86400 + 12 * 3600
        let two = S.twoWeeks(items: [
            S.Item(timestamp: now, authorId: me),
            S.Item(timestamp: now - 7 * 86400, authorId: me),
            S.Item(timestamp: now - 13 * 86400, authorId: friend),
            S.Item(timestamp: now - 14 * 86400, authorId: friend),
            S.Item(timestamp: now - 3600, authorId: friend, kind: .call, duration: 10)
        ], now: now, clock: utc)
        check(two.firstDay == utc.day(now) - 6 && two.current == [0, 0, 0, 0, 0, 0, 1] && two.previous == [1, 0, 0, 0, 0, 0, 1], "Two weeks, calls and older days left out")
        check(S.Period.week.scanStart(now: now) == now - 14 * 86400 && S.Period.month.scanStart(now: now) == now - 60 * 86400, "Scan covers the previous period")
        check(S.Period.year.previousStart(now: now) == now - 730 * 86400 && S.Period.fiveYears.previousStart(now: now) == nil && S.Period.fiveYears.scanStart(now: now) == S.Period.fiveYears.start(now: now), "No previous period for 5 years")

        // A report saved by 1.10 (no new fields) still opens.
        var old = report
        old.records = nil
        old.typicalDay = nil
        old.replyPairs = nil
        old.moodTimeline = nil
        old.previous = nil
        old.twoWeeks = nil
        old.people = old.people.map { person in
            var person = person
            person.moods = nil
            person.uniqueWords = nil
            person.waitLongCount = nil
            person.waitTotalSeconds = nil
            person.waitLongest = nil
            person.waitLongestAt = nil
            person.unanswered = nil
            return person
        }
        if let data = try? JSONEncoder().encode(old) {
            let text = String(decoding: data, as: UTF8.self)
            check(!text.contains("\"records\"") && !text.contains("\"moods\""), "Old report has no new keys")
            check((try? JSONDecoder().decode(S.Report.self, from: data)) == old, "Old report decodes")
        } else {
            check(false, "Old report encodes")
        }
        let slide = ShadowChatStatsPage.render(report, options: ShadowChatStatsPage.Options(mode: .card, dark: true, slide: 3))
        check(slide.contains("\"slide\":3") && slide.contains("function slides()"), "Slide card config")

        print("Shadow chat stats: \(count) checks passed")
    }
}

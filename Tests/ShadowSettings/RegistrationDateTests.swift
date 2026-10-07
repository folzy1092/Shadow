import Foundation

@main
struct RegistrationDateTests {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            count += 1
        }
        func year(_ timestamp: Int64) -> Int {
            return ShadowRegistrationDate.utcComponents(timestamp).year
        }

        let now: Int64 = 1791331200 // 2026-10-07
        let anchors = ShadowRegistrationDate.monotone(ShadowRegistrationDate.staticAnchors)

        // The static table is already monotone and sorted.
        check(anchors.count == ShadowRegistrationDate.staticAnchors.count, "Static table survives cleanup unchanged")
        for i in 1 ..< anchors.count {
            check(anchors[i].0 > anchors[i - 1].0 && anchors[i].1 >= anchors[i - 1].1, "Monotone at \(i)")
        }

        // Pool-adjacent-violators merges a point that goes back in time.
        let cleaned = ShadowRegistrationDate.monotone([(100, 1000), (200, 3000), (300, 2000), (400, 5000)])
        check(cleaned.count == 3, "Violating pair is pooled")
        check(cleaned[1].1 == 2500, "Pooled date is the average")
        for i in 1 ..< cleaned.count {
            check(cleaned[i].1 >= cleaned[i - 1].1, "Cleaned is monotone")
        }

        // Interpolation hits anchors and stays between neighbours.
        check(ShadowRegistrationDate.estimate(userId: 805158066, anchors: anchors, now: now)?.timestamp == 1563208000, "Exact anchor")
        if let middle = ShadowRegistrationDate.estimate(userId: 600_000_000, anchors: anchors, now: now) {
            check(middle.timestamp > 1501459000 && middle.timestamp < 1563208000, "Between 2017 and 2019")
            check(!middle.extrapolated, "Inside the table is not extrapolated")
        } else {
            check(false, "Estimate exists")
        }
        // The old table said June 2024 for everything above 7.5e9.
        check(year(ShadowRegistrationDate.estimate(userId: 7_583_599_300, anchors: anchors, now: now)!.timestamp) == 2025, "Feb 2025 account")

        // Past the newest anchor: extrapolated forward, never into the future.
        let newer = ShadowRegistrationDate.estimate(userId: 8_700_000_000, anchors: anchors, now: now)!
        check(newer.extrapolated, "Newer than the table is extrapolated")
        check(newer.timestamp > 1758758400 && newer.timestamp <= now, "Projected after Sep 2025, not after now")
        check(ShadowRegistrationDate.estimate(userId: 90_000_000_000, anchors: anchors, now: now)!.timestamp == now, "Clamped to now")
        check(ShadowRegistrationDate.estimate(userId: 0, anchors: anchors, now: now) == nil, "No id, no date")
        check(ShadowRegistrationDate.estimate(userId: 1, anchors: anchors, now: now)?.timestamp == 1383264000, "Oldest ids get the first anchor")

        // Telegram's month.
        check(ShadowRegistrationDate.parseOfficialMonth("10.2025").map { $0.month == 10 && $0.year == 2025 } == true, "MM.YYYY")
        check(ShadowRegistrationDate.parseOfficialMonth("13.2025") == nil, "Bad month")
        check(ShadowRegistrationDate.parseOfficialMonth("2025") == nil, "Bad format")

        // Bot answers.
        let exact = ShadowRegistrationDate.parseBotAnswer("{\"flag\":\"EXACT\",\"date\":\"12.10.2021\"}")
        check(exact?.flag == .exact, "Flag parsed")
        if let exact {
            let components = ShadowRegistrationDate.utcComponents(exact.timestamp)
            check(components.day == 12 && components.month == 10 && components.year == 2021, "Date parsed")
        }
        check(ShadowRegistrationDate.parseBotAnswer("failed") == nil, "Bot failure")
        check(ShadowRegistrationDate.parseBotAnswer("{\"flag\":\"WHAT\",\"date\":\"12.10.2021\"}") == nil, "Unknown flag")

        // Priority: Telegram > bot > local.
        let botAnswer = ShadowRegistrationDate.BotAnswer(flag: .interpolated, timestamp: 1634000000)
        check(ShadowRegistrationDate.resolve(userId: 1974255900, official: "03.2021", bot: botAnswer, anchors: anchors, now: now) == .official(month: 3, year: 2021), "Official wins")
        check(ShadowRegistrationDate.resolve(userId: 1974255900, official: nil, bot: botAnswer, anchors: anchors, now: now) == .approximately(timestamp: 1634000000, precision: .day), "Bot over local")
        // "Later than" for a new account: the local projection is more useful.
        let later = ShadowRegistrationDate.BotAnswer(flag: .later, timestamp: 1758758400)
        if case let .approximately(timestamp, precision)? = ShadowRegistrationDate.resolve(userId: 8_700_000_000, official: nil, bot: later, anchors: anchors, now: now) {
            check(timestamp > 1758758400 && precision == .month, "ET + newer local estimate")
        } else {
            check(false, "ET resolves to an estimate")
        }
        check(ShadowRegistrationDate.resolve(userId: 805158066, official: nil, bot: later, anchors: anchors, now: now) == .after(timestamp: 1758758400), "ET disagreeing with local keeps the bound")

        // Text.
        check(ShadowRegistrationDate.text(.official(month: 10, year: 2025)) == "Октябрь 2025 г.", "Official text")
        check(ShadowRegistrationDate.text(.approximately(timestamp: 1634000000, precision: .day)) == "≈ 12 октября 2021 г.", "Day text")
        check(ShadowRegistrationDate.text(.approximately(timestamp: 1634000000, precision: .month)) == "≈ октябрь 2021 г.", "Month text")
        check(ShadowRegistrationDate.text(.after(timestamp: 1758758400)) == "Позже 25 сентября 2025 г.", "After text")
        check(ShadowRegistrationDate.text(.before(timestamp: 1758758400)) == "Раньше 25 сентября 2025 г.", "Before text")

        // Store: official months become anchors; bot fetch bookkeeping.
        let store = ShadowRegistrationDateStore(fileURL: nil)
        check(store.recordOfficial(userId: 9_000_000_000, month: "06.2026"), "New official month recorded")
        check(!store.recordOfficial(userId: 9_000_000_000, month: "06.2026"), "Same month is not new")
        check(!store.recordOfficial(userId: 9_000_000_001, month: "junk"), "Junk ignored")
        check(store.anchors().last?.0 == 9_000_000_000, "Learned anchor extends the table")
        check(store.value(userId: 9_000_000_000, official: nil, now: now) == .official(month: 6, year: 2026), "Stored official month is shown")
        if case let .approximately(timestamp, _)? = store.value(userId: 8_900_000_000, official: nil, now: now) {
            check(!ShadowRegistrationDate.estimate(userId: 8_900_000_000, anchors: store.anchors(), now: now)!.extrapolated, "Learned anchor turns extrapolation into interpolation")
            check(timestamp > 1758758400 && timestamp < 1781481600, "Between Sep 2025 and mid-June 2026")
        } else {
            check(false, "Value near a learned anchor")
        }

        let t0 = 1_000_000.0
        check(store.beginBotFetch(userId: 42, now: t0), "First fetch starts")
        check(!store.beginBotFetch(userId: 42, now: t0), "No parallel fetch")
        store.finishBotFetch(userId: 42, answer: nil, now: t0)
        check(!store.beginBotFetch(userId: 42, now: t0 + 60), "Failure is not retried at once")
        check(store.beginBotFetch(userId: 42, now: t0 + ShadowRegistrationDateStore.failedRetryInterval + 1), "Failure retried after a day")
        store.finishBotFetch(userId: 42, answer: botAnswer, now: t0 + 100_000)
        check(store.botAnswer(userId: 42) == botAnswer, "Answer stored")
        check(!store.beginBotFetch(userId: 42, now: t0 + 200_000), "Fresh answer is not refetched")
        check(store.beginBotFetch(userId: 42, now: t0 + 100_000 + ShadowRegistrationDateStore.answerRefreshInterval + 1), "Old answer refreshed")
        store.finishBotFetch(userId: 42, answer: nil, now: t0 + 100_000 + ShadowRegistrationDateStore.answerRefreshInterval + 2)
        check(store.botAnswer(userId: 42) == botAnswer, "A failed refresh keeps the old answer")

        // Persistence round-trip.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("shadow-regdate-\(UUID().uuidString).json")
        let saved = ShadowRegistrationDateStore(fileURL: url)
        saved.recordOfficial(userId: 123, month: "01.2020")
        check(saved.beginBotFetch(userId: 77, now: t0), "Fetch for persistence")
        saved.finishBotFetch(userId: 77, answer: botAnswer, now: t0)
        let reloaded = ShadowRegistrationDateStore(fileURL: url)
        check(reloaded.officialMonth(userId: 123) == "01.2020", "Official month persisted")
        check(reloaded.botAnswer(userId: 77) == botAnswer, "Bot answer persisted")
        try? FileManager.default.removeItem(at: url)

        print("RegistrationDateTests: \(count) checks passed")
    }
}

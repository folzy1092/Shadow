import Foundation

@main
struct ChatStreakTests {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            count += 1
        }
        typealias W = ShadowChatStreak.Walker
        // Messages newest first: (day, mine).
        func run(_ messages: [(Int32, Bool)], today: Int32 = 100, end: Bool = true) -> (days: Int, finished: Bool, read: Int) {
            var walker = W(today: today)
            var read = 0
            for (day, mine) in messages {
                read += 1
                if !walker.add(day: day, isMine: mine) {
                    break
                }
            }
            if end {
                walker.finishAtEnd()
            }
            return (walker.days, walker.finished, read)
        }

        check(run([(100, true), (100, false), (99, true), (99, false), (98, false)]).days == 2, "Today and yesterday, day 98 only one side")
        check(run([(99, true), (99, false), (98, false), (98, true)]).days == 2, "Today has no messages yet: the run continues")
        check(run([(100, true), (99, true), (99, false)]).days == 1, "Today only me: not counted, does not break")
        check(run([(100, true), (100, false), (98, true), (98, false)]).days == 1, "A missing day breaks the run")
        check(run([(97, true), (97, false)]).days == 0, "Old run is not current")
        let stopped = run([(100, true), (100, false), (98, true), (98, false), (97, true), (97, false)])
        check(stopped.read == 3 && stopped.finished, "Stops reading at the first older day after a gap")
        let open = run([(100, true), (100, false), (99, true), (99, false)], end: false)
        check(!open.finished && open.days == 1, "Reached the oldest stored message: day 99 still open, more history needed")
        check(run([]).days == 0, "Empty chat")
        check(run([(101, true), (100, true), (100, false)]).days == 1, "A message from the future is ignored")

        check(ShadowChatStreak.text(days: 1) == nil, "One day is not shown")
        check(ShadowChatStreak.text(days: 2) == "Общаемся 2 дня подряд", "2 дня")
        check(ShadowChatStreak.text(days: 5) == "Общаемся 5 дней подряд", "5 дней")
        check(ShadowChatStreak.text(days: 21) == "Общаемся 21 день подряд", "21 день")
        check(ShadowChatStreak.text(days: 112) == "Общаемся 112 дней подряд", "112 дней")

        let suite = "shadow-chat-streak-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = ShadowChatStreakStore(defaults: defaults)
        check(store.needsUpdate(accountPeerId: 1, peerId: 2, now: 1000, today: 10), "Nothing stored: count")
        store.set(accountPeerId: 1, peerId: 2, days: 47, date: 1000, day: 10)
        check(store.value(accountPeerId: 1, peerId: 2)?.days == 47, "Stored")
        check(!store.needsUpdate(accountPeerId: 1, peerId: 2, now: 1000 + 60, today: 10), "Fresh")
        check(store.needsUpdate(accountPeerId: 1, peerId: 2, now: 1000 + 31 * 60, today: 10), "Stale after 30 minutes")
        check(store.needsUpdate(accountPeerId: 1, peerId: 2, now: 1000 + 60, today: 11), "Stale on a new day")
        check(store.value(accountPeerId: 1, peerId: 3) == nil, "Per chat")
        check(store.begin(accountPeerId: 1, peerId: 2) && !store.begin(accountPeerId: 1, peerId: 2), "One count at a time")
        store.end(accountPeerId: 1, peerId: 2)
        check(store.begin(accountPeerId: 1, peerId: 2), "Free again")
        defaults.removePersistentDomain(forName: suite)

        print("Shadow chat streak: \(count) checks passed")
    }
}

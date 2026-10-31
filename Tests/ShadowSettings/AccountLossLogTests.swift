import Foundation

@main
struct AccountLossLogTests {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            count += 1
        }
        let suite = "shadow-account-loss-tests-\(UInt64.random(in: 0 ... UInt64.max))"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let log = ShadowAccountLossLog(defaults: defaults)

        check(log.entries().isEmpty, "Empty at first")
        check(log.reportText().contains("пуст"), "Empty report says so")
        check(log.latestReason(peerId: 1) == nil, "No reason yet")

        let start = Date(timeIntervalSince1970: 1_800_000_000)
        log.noteSeen(peerIds: [1, 2], now: start)
        log.noteSeen(peerIds: [1], now: start.addingTimeInterval(100))
        log.record(site: "network.loggedOut", peerId: 1, accountId: 77, reason: "401 AUTH_KEY_UNREGISTERED", isCurrent: true, now: start.addingTimeInterval(300), stack: ["frame0", "frame1"])
        let first = log.entries().first
        check(first?.secondsSinceAdded == 300, "Age counts from the first sighting")
        check(first?.stack == ["frame0", "frame1"], "Stack kept")
        check(first?.accountId == 77 && first?.isCurrent == true && first?.site == "network.loggedOut", "Fields kept")

        log.record(site: "accountManager.cleanup", peerId: 1, reason: nil, now: start.addingTimeInterval(301), stack: [])
        check(log.latestReason(peerId: 1) == "401 AUTH_KEY_UNREGISTERED (network.loggedOut)", "Latest reason skips entries without one")

        log.record(site: "duress", peerId: 9, reason: "wipe", now: start.addingTimeInterval(302), stack: [])
        check(log.entries().last?.secondsSinceAdded == nil, "Unseen peer has no age")

        let reloaded = ShadowAccountLossLog(defaults: defaults)
        check(reloaded.entries().count == 3, "Survives a reload")
        let report = reloaded.reportText()
        check(report.contains("peer 1"), "Report names the peer")
        check(report.contains("AUTH_KEY_UNREGISTERED"), "Report has the reason")
        check(report.contains("через 300 с"), "Report has the age")
        check(report.contains("без причины"), "Report marks missing reasons")

        log.record(site: "deep", peerId: 3, reason: "x", stack: (0 ..< 50).map { "f\($0)" })
        check(log.entries().last?.stack.count == ShadowAccountLossLog.maxStackFrames, "Stack capped")

        for index in 0 ..< ShadowAccountLossLog.maxEntries + 10 {
            log.record(site: "bulk\(index)", peerId: 4, reason: nil, stack: [])
        }
        let entries = log.entries()
        check(entries.count == ShadowAccountLossLog.maxEntries, "Entries capped")
        check(entries.last?.site == "bulk\(ShadowAccountLossLog.maxEntries + 9)", "Newest kept")

        print("AccountLossLogTests: \(count) checks passed")
    }
}

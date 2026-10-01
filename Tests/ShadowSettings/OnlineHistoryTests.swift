import Foundation

@main
struct OnlineHistoryTests {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            count += 1
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("shadow-online-tests-\(UInt64.random(in: 0 ... UInt64.max))", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = ShadowOnlineHistory(directory: directory)
        let t: Int32 = 1_800_000_000

        check(history.sessions(accountPeerId: 1, peerId: 5, now: t).isEmpty, "Empty at first")
        history.record(accountPeerId: 1, peerId: 5, onlineUntil: t + 300, lastSeen: nil, now: t)
        let open = history.sessions(accountPeerId: 1, peerId: 5, now: t + 60)
        check(open == [ShadowOnlineHistory.Session(start: t, end: t + 60)], "Open session is reported up to now")
        history.record(accountPeerId: 1, peerId: 5, onlineUntil: t + 400, lastSeen: nil, now: t + 100)
        history.record(accountPeerId: 1, peerId: 5, onlineUntil: nil, lastSeen: t + 200, now: t + 210)
        check(history.sessions(accountPeerId: 1, peerId: 5, now: t + 500) == [ShadowOnlineHistory.Session(start: t, end: t + 200)], "Offline closes at last seen")

        // Online again; the status expires without an offline update, then a new session starts.
        history.record(accountPeerId: 1, peerId: 5, onlineUntil: t + 1100, lastSeen: nil, now: t + 1000)
        history.record(accountPeerId: 1, peerId: 5, onlineUntil: t + 3100, lastSeen: nil, now: t + 3000)
        let sessions = history.sessions(accountPeerId: 1, peerId: 5, now: t + 3050)
        check(sessions.count == 3, "Expired session closed, new one open")
        check(sessions[1] == ShadowOnlineHistory.Session(start: t + 1000, end: t + 1100), "Expired session ends at its until")
        check(history.sessions(accountPeerId: 2, peerId: 5, now: t).isEmpty, "Per account")

        // Hidden last seen: closes at now.
        history.record(accountPeerId: 1, peerId: 6, onlineUntil: t + 100, lastSeen: nil, now: t)
        history.record(accountPeerId: 1, peerId: 6, onlineUntil: nil, lastSeen: nil, now: t + 50)
        check(history.sessions(accountPeerId: 1, peerId: 6, now: t + 60) == [ShadowOnlineHistory.Session(start: t, end: t + 50)], "Hidden last seen closes at now")

        // Persistence.
        history.flush()
        let reloaded = ShadowOnlineHistory(directory: directory)
        check(reloaded.sessions(accountPeerId: 1, peerId: 6, now: t + 60).count == 1, "Persisted")

        // Retention.
        let later = t + Int32(ShadowOnlineHistory.retention) + 1000
        history.record(accountPeerId: 1, peerId: 6, onlineUntil: later + 10, lastSeen: nil, now: later)
        check(history.sessions(accountPeerId: 1, peerId: 6, now: later).count == 1, "Old sessions pruned")

        print("Shadow online history: \(count) checks passed")
    }
}

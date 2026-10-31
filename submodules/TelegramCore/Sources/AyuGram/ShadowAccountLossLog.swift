import Foundation

// Shadow 2.2.1: why an account left this device.
//
// Accounts were disappearing locally while their server sessions stayed alive,
// and the restore report could only guess why. Every logout and removal site
// writes an entry here: the peer, the site, the server's reason when there is
// one, whether it was the current account and how long after it first appeared.
// The log lives in UserDefaults so it survives the relaunch that follows a
// logout, and the restore report shows it.
//
// Foundation only, so it is unit-tested by the Foundation suite.
public final class ShadowAccountLossLog {
    public static let shared = ShadowAccountLossLog(defaults: .standard)

    public static let maxEntries = 100
    public static let maxStackFrames = 20
    static let reportStackFrames = 8

    public struct Entry: Codable, Equatable {
        public let date: Date
        public let peerId: Int64?
        public let accountId: Int64?
        public let site: String
        public let reason: String?
        public let isCurrent: Bool?
        public let secondsSinceAdded: Double?
        public let stack: [String]
    }

    private enum Key {
        static let entries = "shadow.accountLoss.entries.v1"
        static let firstSeen = "shadow.accountLoss.firstSeen.v1"
    }

    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    // Remembers when each peer was first seen on this device; later sightings keep the first date.
    public func noteSeen(peerIds: Set<Int64>, now: Date = Date()) {
        self.lock.lock()
        defer { self.lock.unlock() }
        let current = self.loadFirstSeen()
        let missing = peerIds.map { String($0) }.filter { current[$0] == nil }
        if missing.isEmpty {
            return
        }
        var updated = current
        for key in missing {
            updated[key] = now.timeIntervalSince1970
        }
        self.defaults.set(updated, forKey: Key.firstSeen)
    }

    public func record(site: String, peerId: Int64?, accountId: Int64? = nil, reason: String?, isCurrent: Bool? = nil, now: Date = Date(), stack: [String] = Thread.callStackSymbols) {
        self.lock.lock()
        defer { self.lock.unlock() }
        let secondsSinceAdded: Double? = peerId.flatMap { self.loadFirstSeen()[String($0)] }.map { now.timeIntervalSince1970 - $0 }
        let entry = Entry(
            date: now,
            peerId: peerId,
            accountId: accountId,
            site: site,
            reason: reason,
            isCurrent: isCurrent,
            secondsSinceAdded: secondsSinceAdded,
            stack: Array(stack.prefix(ShadowAccountLossLog.maxStackFrames))
        )
        let entries = Array((self.loadEntries() + [entry]).suffix(ShadowAccountLossLog.maxEntries))
        if let data = try? JSONEncoder().encode(entries) {
            self.defaults.set(data, forKey: Key.entries)
        }
    }

    public func entries() -> [Entry] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.loadEntries()
    }

    // The newest recorded reason for a peer, with the site it came from.
    public func latestReason(peerId: Int64) -> String? {
        guard let entry = self.entries().last(where: { $0.peerId == peerId && $0.reason != nil }), let reason = entry.reason else {
            return nil
        }
        return "\(reason) (\(entry.site))"
    }

    public func reportText() -> String {
        let entries = self.entries()
        if entries.isEmpty {
            return "Журнал потерь аккаунтов пуст."
        }
        let formatter = ISO8601DateFormatter()
        var lines = ["Журнал потерь аккаунтов (\(entries.count)):"]
        for entry in entries.reversed() {
            var parts = [formatter.string(from: entry.date), entry.site]
            if let peerId = entry.peerId {
                parts.append("peer \(peerId)")
            }
            if let accountId = entry.accountId {
                parts.append("account \(accountId)")
            }
            if let isCurrent = entry.isCurrent {
                parts.append(isCurrent ? "текущий" : "не текущий")
            }
            if let seconds = entry.secondsSinceAdded {
                parts.append("через \(Int(seconds)) с после добавления")
            }
            parts.append(entry.reason ?? "без причины")
            lines.append("• " + parts.joined(separator: " · "))
            for frame in entry.stack.prefix(ShadowAccountLossLog.reportStackFrames) {
                lines.append("    " + frame)
            }
        }
        return lines.joined(separator: "\n")
    }

    private func loadEntries() -> [Entry] {
        guard let data = self.defaults.data(forKey: Key.entries), let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
            return []
        }
        return entries
    }

    private func loadFirstSeen() -> [String: Double] {
        return (self.defaults.dictionary(forKey: Key.firstSeen) as? [String: Double]) ?? [:]
    }
}

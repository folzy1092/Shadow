import Foundation

// Shadow: «Общаемся N дней подряд» in a private chat's profile. A day counts
// when both sides sent at least one message that day (reactions and calls do
// not count), local calendar days; today, while it lasts, never breaks the
// run. Foundation only (tested in Tests/ShadowSettings/ChatStreakTests.swift);
// ShadowChatStatsCollect.chatStreak walks the stored messages.
public enum ShadowChatStreak {
    // The profile line shows from this many days.
    public static let minimumDays = 2

    public static func text(days: Int) -> String? {
        guard days >= minimumDays else {
            return nil
        }
        let a = days % 100
        let b = a % 10
        let word: String
        if a > 10 && a < 20 {
            word = "дней"
        } else if b == 1 {
            word = "день"
        } else if b > 1 && b < 5 {
            word = "дня"
        } else {
            word = "дней"
        }
        return "Общаемся \(days) \(word) подряд"
    }

    // Fed with messages from the newest to the oldest; stops as soon as a day
    // without both sides is passed.
    public struct Walker {
        public let today: Int32
        public private(set) var day: Int32
        public private(set) var days = 0
        public private(set) var finished = false
        private var mine = false
        private var theirs = false

        public init(today: Int32) {
            self.today = today
            self.day = today
        }

        // false: the run is over, no need to read older messages.
        public mutating func add(day messageDay: Int32, isMine: Bool) -> Bool {
            while !self.finished && messageDay < self.day {
                self.closeDay()
            }
            if self.finished {
                return false
            }
            if messageDay == self.day {
                if isMine {
                    self.mine = true
                } else {
                    self.theirs = true
                }
            }
            return true
        }

        private mutating func closeDay() {
            if self.mine && self.theirs {
                self.days += 1
            } else if self.day != self.today {
                self.finished = true
                return
            }
            self.day -= 1
            self.mine = false
            self.theirs = false
        }

        // No older messages exist: count the day in progress and stop.
        public mutating func finishAtEnd() {
            if !self.finished {
                if self.mine && self.theirs {
                    self.days += 1
                }
                self.finished = true
            }
        }
    }
}

public final class ShadowChatStreakStore {
    public static let shared = ShadowChatStreakStore(defaults: .standard)
    public static let didChangeNotification = Notification.Name("ShadowChatStreakStore.didChange")
    // Recount at most this often for an open profile.
    public static let freshness: TimeInterval = 30 * 60

    private let defaults: UserDefaults
    private let key = "shadow.chatStreak.v1"
    private let lock = NSLock()
    private var running = Set<String>()

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    private static func entryKey(accountPeerId: Int64, peerId: Int64) -> String {
        return "\(accountPeerId)/\(peerId)"
    }

    // (days, when counted, the local day it was counted on).
    public func value(accountPeerId: Int64, peerId: Int64) -> (days: Int, date: TimeInterval, day: Int32)? {
        guard let all = self.defaults.dictionary(forKey: self.key), let entry = all[ShadowChatStreakStore.entryKey(accountPeerId: accountPeerId, peerId: peerId)] as? [String: Any], let days = entry["days"] as? Int, let date = entry["date"] as? Double else {
            return nil
        }
        return (days, date, Int32(entry["day"] as? Int ?? 0))
    }

    public func set(accountPeerId: Int64, peerId: Int64, days: Int, date: TimeInterval, day: Int32) {
        var all = self.defaults.dictionary(forKey: self.key) ?? [:]
        let entryKey = ShadowChatStreakStore.entryKey(accountPeerId: accountPeerId, peerId: peerId)
        let previous = (all[entryKey] as? [String: Any])?["days"] as? Int
        all[entryKey] = ["days": days, "date": date, "day": Int(day)]
        self.defaults.set(all, forKey: self.key)
        if previous != days {
            NotificationCenter.default.post(name: ShadowChatStreakStore.didChangeNotification, object: nil)
        }
    }

    public func needsUpdate(accountPeerId: Int64, peerId: Int64, now: TimeInterval, today: Int32) -> Bool {
        guard let value = self.value(accountPeerId: accountPeerId, peerId: peerId) else {
            return true
        }
        return value.day != today || now - value.date > ShadowChatStreakStore.freshness
    }

    // One count per chat at a time.
    public func begin(accountPeerId: Int64, peerId: Int64) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.running.insert(ShadowChatStreakStore.entryKey(accountPeerId: accountPeerId, peerId: peerId)).inserted
    }

    public func end(accountPeerId: Int64, peerId: Int64) {
        self.lock.lock()
        self.running.remove(ShadowChatStreakStore.entryKey(accountPeerId: accountPeerId, peerId: peerId))
        self.lock.unlock()
    }
}

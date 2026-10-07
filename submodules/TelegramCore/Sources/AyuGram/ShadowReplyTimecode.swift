import Foundation

// Shadow: a timecode in text replies to voice messages and round videos.
// Replying to a 5:12 voice message heard up to 0:53 sends "0:53 text"; Telegram
// itself makes that 0:53 a link that seeks the replied message, also for the
// other side. AyuGramSettings.replyTimecode turns it on, replyTimecodeMode:
//
//   0 Всегда      the timecode is added without asking
//   1 Спрашивать  an alert asks; its checkbox remembers the answer in this chat
//                 for 30 minutes (in memory only)
//
// Only a message that was started (1 s) and not heard to the end (1 s left)
// gets a timecode. Positions come from the shared player: `positions` keeps the
// last one of every voice message, because Telegram moves on to the next voice
// message by itself and the replied one is no longer playing.
//
// Foundation only, so it is unit-tested by the Foundation suite.
public enum ShadowReplyTimecode {
    public static let modeAlways: Int32 = 0
    public static let modeAsk: Int32 = 1
    public static let modes: [Int32] = [modeAlways, modeAsk]
    public static let rememberInterval: Double = 30.0 * 60.0

    public static func modeTitle(_ mode: Int32) -> String {
        return normalizedMode(mode) == modeAsk ? "Спрашивать" : "Всегда"
    }

    public static func normalizedMode(_ mode: Int32) -> Int32 {
        return modes.contains(mode) ? mode : modeAlways
    }

    // The timecode for a position, nil when the message was not started or was
    // heard to the end.
    public static func timecode(position: Double?, duration: Double) -> String? {
        guard let position, duration >= 2.0, position >= 1.0, position <= duration - 1.0 else {
            return nil
        }
        return ShadowVoiceTime.clock(Int32(position))
    }

    public static func applying(_ timecode: String, to text: String) -> String {
        return "\(timecode) \(text)"
    }

    // What sending does with a timecode.
    public enum Resolved: Equatable {
        case add(String)
        case skip
    }

    public enum Action: Equatable {
        case add
        case skip
        case ask
    }

    // `remembered`: the answer remembered in this chat, nil when there is none.
    public static func action(enabled: Bool, mode: Int32, remembered: Bool?) -> Action {
        guard enabled else {
            return .skip
        }
        if normalizedMode(mode) == modeAlways {
            return .add
        }
        if let remembered {
            return remembered ? .add : .skip
        }
        return .ask
    }

    public static func chatKey(accountPeerId: Int64, peerId: Int64, threadId: Int64?) -> String {
        return "\(accountPeerId)/\(peerId)/\(threadId ?? 0)"
    }

    public static func messageKey(accountPeerId: Int64, peerId: Int64, namespace: Int32, id: Int32) -> String {
        return "\(accountPeerId)/\(peerId)/\(namespace)/\(id)"
    }

    // Answers remembered per chat for 30 minutes.
    public final class Memory {
        private let lock = NSLock()
        private var entries: [String: (add: Bool, until: Double)] = [:]

        public init() {
        }

        public func remember(chat: String, add: Bool, now: Double) {
            self.lock.lock()
            defer { self.lock.unlock() }
            self.entries = self.entries.filter { $0.value.until > now }
            self.entries[chat] = (add, now + ShadowReplyTimecode.rememberInterval)
        }

        public func answer(chat: String, now: Double) -> Bool? {
            self.lock.lock()
            defer { self.lock.unlock() }
            guard let entry = self.entries[chat], entry.until > now else {
                return nil
            }
            return entry.add
        }
    }

    // One status of the shared player. `generatedAt` and `now` are the same
    // clock (CACurrentMediaTime in the app).
    public struct PlaybackSample: Equatable {
        public var timestamp: Double
        public var duration: Double
        public var rate: Double
        public var isPlaying: Bool
        public var generatedAt: Double

        public init(timestamp: Double, duration: Double, rate: Double, isPlaying: Bool, generatedAt: Double) {
            self.timestamp = timestamp
            self.duration = duration
            self.rate = rate
            self.isPlaying = isPlaying
            self.generatedAt = generatedAt
        }

        public func position(now: Double) -> Double {
            var value = self.timestamp
            if self.isPlaying {
                value += max(0.0, now - self.generatedAt) * self.rate
            }
            if self.duration > 0.0 {
                value = min(value, self.duration)
            }
            return max(0.0, value)
        }
    }

    // Last positions of voice messages, at most `limit` of them.
    public final class Positions {
        private let lock = NSLock()
        private let limit: Int
        private var samples: [String: PlaybackSample] = [:]
        private var order: [String] = []

        public init(limit: Int = 200) {
            self.limit = limit
        }

        public func record(key: String, sample: PlaybackSample) {
            self.lock.lock()
            defer { self.lock.unlock() }
            if self.samples[key] == nil {
                self.order.append(key)
                if self.order.count > self.limit {
                    let removed = self.order.removeFirst()
                    self.samples.removeValue(forKey: removed)
                }
            }
            self.samples[key] = sample
        }

        // The player left this message: keep where it stopped.
        public func freeze(key: String, now: Double) {
            self.lock.lock()
            defer { self.lock.unlock() }
            guard var sample = self.samples[key], sample.isPlaying else {
                return
            }
            sample.timestamp = sample.position(now: now)
            sample.isPlaying = false
            sample.generatedAt = now
            self.samples[key] = sample
        }

        public func sample(key: String) -> PlaybackSample? {
            self.lock.lock()
            defer { self.lock.unlock() }
            return self.samples[key]
        }
    }

    public static let memory = Memory()
    public static let positions = Positions()
}

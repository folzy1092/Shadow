import Foundation

// Shadow: «Своя скорость для чатов» (AyuGramSettings.chatVoiceSpeed). With it
// on, the speed button of the player bar changes the speed of the chat the
// voice message plays from, not the common one: everywhere 1.2x, a friend's
// chat 1.5x. A voice player started from a chat with its own speed starts at it.
//
// Speeds are AudioPlaybackRate raw values (rate × 1000), stored on this device
// per account and chat. `currentChat` is the chat of the voice message playing
// now, set by MediaManager.
//
// Foundation only, so it is unit-tested by the Foundation suite.
public final class ShadowChatVoiceSpeed {
    public static let shared = ShadowChatVoiceSpeed(defaults: .standard)
    // Posted after a chat speed is set or reset.
    public static let didChangeNotification = Notification.Name("ShadowChatVoiceSpeedDidChange")

    public struct Entry: Equatable {
        public let peerId: Int64
        public let rate: Int32
    }

    private static let storageKey = "shadowChatVoiceSpeeds.v1"
    private let defaults: UserDefaults
    private let lock = NSLock()
    private var currentChatValue: String?

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public static func chatKey(accountPeerId: Int64, peerId: Int64) -> String {
        return "\(accountPeerId)/\(peerId)"
    }

    // 1500 → "1.5x", 1000 → "1x", 1250 → "1.25x".
    public static func title(rate: Int32) -> String {
        var text = String(format: "%.2f", Double(rate) / 1000.0)
        while text.hasSuffix("0") {
            text.removeLast()
        }
        if text.hasSuffix(".") {
            text.removeLast()
        }
        return text + "x"
    }

    public var currentChat: String? {
        get {
            self.lock.lock()
            defer { self.lock.unlock() }
            return self.currentChatValue
        }
        set {
            self.lock.lock()
            defer { self.lock.unlock() }
            self.currentChatValue = newValue
        }
    }

    private func load() -> [String: Int32] {
        guard let raw = self.defaults.dictionary(forKey: ShadowChatVoiceSpeed.storageKey) else {
            return [:]
        }
        var result: [String: Int32] = [:]
        for (key, value) in raw {
            if let number = value as? NSNumber, number.int32Value > 0 {
                result[key] = number.int32Value
            }
        }
        return result
    }

    private func save(_ values: [String: Int32]) {
        self.defaults.set(values.mapValues { NSNumber(value: $0) }, forKey: ShadowChatVoiceSpeed.storageKey)
    }

    public func rate(chat: String) -> Int32? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.load()[chat]
    }

    public func set(chat: String, rate: Int32) {
        guard rate > 0 else {
            return
        }
        self.lock.lock()
        var values = self.load()
        values[chat] = rate
        self.save(values)
        self.lock.unlock()
        self.notifyChanged()
    }

    public func remove(chat: String) {
        self.lock.lock()
        var values = self.load()
        values.removeValue(forKey: chat)
        self.save(values)
        self.lock.unlock()
        self.notifyChanged()
    }

    public func removeAll(accountPeerId: Int64) {
        self.lock.lock()
        let prefix = "\(accountPeerId)/"
        self.save(self.load().filter { !$0.key.hasPrefix(prefix) })
        self.lock.unlock()
        self.notifyChanged()
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: ShadowChatVoiceSpeed.didChangeNotification, object: self)
    }

    // Chats of one account with their own speed, by peer id.
    public func entries(accountPeerId: Int64) -> [Entry] {
        self.lock.lock()
        defer { self.lock.unlock() }
        let prefix = "\(accountPeerId)/"
        var result: [Entry] = []
        for (key, rate) in self.load() where key.hasPrefix(prefix) {
            if let peerId = Int64(key.dropFirst(prefix.count)) {
                result.append(Entry(peerId: peerId, rate: rate))
            }
        }
        return result.sorted(by: { $0.peerId < $1.peerId })
    }
}

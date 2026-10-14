import Foundation

// Shadow: «Закрепить у себя» — a pinned message only this device sees, in any
// chat: a channel, a group without the right to pin, a private chat. The chat
// header shows local pins next to the real ones (ChatController
// shadowMergeLocalPins): a tap goes to the pin and the next tap to the one
// above it, like the stock panel; the close button and the menu unpin them.
//
// Stored per account and chat in UserDefaults of this device ("namespace:id"
// of each message, oldest first); not synced and not exported.
//
// Foundation only, so it is unit-tested by the Foundation suite.
public struct ShadowLocalPin: Hashable, Comparable {
    public let namespace: Int32
    public let id: Int32

    public init(namespace: Int32, id: Int32) {
        self.namespace = namespace
        self.id = id
    }

    public static func <(lhs: ShadowLocalPin, rhs: ShadowLocalPin) -> Bool {
        if lhs.namespace != rhs.namespace {
            return lhs.namespace < rhs.namespace
        }
        return lhs.id < rhs.id
    }

    var stored: String {
        return "\(self.namespace):\(self.id)"
    }

    init?(stored: String) {
        let parts = stored.split(separator: ":")
        guard parts.count == 2, let namespace = Int32(parts[0]), let id = Int32(parts[1]) else {
            return nil
        }
        self.init(namespace: namespace, id: id)
    }
}

public final class ShadowLocalPinStore {
    public static let shared = ShadowLocalPinStore(defaults: .standard)
    public static let didChangeNotification = Notification.Name("ShadowLocalPinStore.didChange")
    public static let limitPerChat = 100

    private let defaults: UserDefaults
    private let key = "shadow.localPins.v1"
    private let lock = NSLock()

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    private func chatKey(accountPeerId: Int64, peerId: Int64) -> String {
        return "\(accountPeerId)/\(peerId)"
    }

    private func load() -> [String: [String]] {
        return (self.defaults.dictionary(forKey: self.key) as? [String: [String]]) ?? [:]
    }

    // Oldest first.
    public func pins(accountPeerId: Int64, peerId: Int64) -> [ShadowLocalPin] {
        self.lock.lock()
        defer { self.lock.unlock() }
        let values = self.load()[self.chatKey(accountPeerId: accountPeerId, peerId: peerId)] ?? []
        return Array(Set(values.compactMap(ShadowLocalPin.init(stored:)))).sorted()
    }

    public func isPinned(accountPeerId: Int64, peerId: Int64, pin: ShadowLocalPin) -> Bool {
        return self.pins(accountPeerId: accountPeerId, peerId: peerId).contains(pin)
    }

    public func setPinned(_ pinned: Bool, accountPeerId: Int64, peerId: Int64, pin: ShadowLocalPin) {
        self.lock.lock()
        var all = self.load()
        let chatKey = self.chatKey(accountPeerId: accountPeerId, peerId: peerId)
        var pins = Set((all[chatKey] ?? []).compactMap(ShadowLocalPin.init(stored:)))
        if pinned {
            pins.insert(pin)
        } else {
            pins.remove(pin)
        }
        let sorted = Array(pins.sorted().suffix(ShadowLocalPinStore.limitPerChat))
        if sorted.isEmpty {
            all.removeValue(forKey: chatKey)
        } else {
            all[chatKey] = sorted.map { $0.stored }
        }
        self.defaults.set(all, forKey: self.key)
        self.lock.unlock()
        NotificationCenter.default.post(name: ShadowLocalPinStore.didChangeNotification, object: nil)
    }
}

public enum ShadowLocalPins {
    // Which pin the header shows, like the stock panel: the newest one at or
    // above the reference message (the top visible one; strictly above after a
    // tap on the panel scrolled to it), else the oldest. No reference: the
    // newest. `ids` are oldest first. Returns an index into `ids`.
    public static func pickIndex(ids: [Int32], referenceId: Int32?, isScrolled: Bool) -> Int? {
        guard !ids.isEmpty else {
            return nil
        }
        guard let referenceId else {
            return ids.count - 1
        }
        var result = 0
        for i in 0 ..< ids.count {
            let matches = isScrolled ? ids[i] < referenceId : ids[i] <= referenceId
            if matches {
                result = i
            }
        }
        return result
    }

    // Of two candidates (a local pin and a real one) the one the header shows:
    // the newer of those that match the reference, else the older.
    public static func prefersFirst(_ first: Int32, over second: Int32, referenceId: Int32?, isScrolled: Bool) -> Bool {
        guard let referenceId else {
            return first > second
        }
        func matches(_ id: Int32) -> Bool {
            return isScrolled ? id < referenceId : id <= referenceId
        }
        switch (matches(first), matches(second)) {
        case (true, true):
            return first > second
        case (true, false):
            return true
        case (false, true):
            return false
        case (false, false):
            return first < second
        }
    }
}

import Foundation

// Shadow: second space (spec docs/specs/2026-10-01-shadow-batch.md, section 6).
//
// Device-local state in UserDefaults:
//   * per-chat visibility, per account (account peer id -> peer id -> visibility);
//     "everywhere" is the default and is not stored;
//   * the second code, stored only as PBKDF2-HMAC-SHA256 (see ShadowChatLockStore.derive);
//   * the mute state a chat had before it moved to the second space.
// The active space lives in memory: every launch starts in the main space.
//
// Foundation + CommonCrypto only (with ShadowChatLock.swift), so it is
// unit-tested by the Foundation suite.
public final class ShadowSpaceStore {
    public static let shared = ShadowSpaceStore(defaults: .standard)

    // Posted (on the calling thread) when the active space, a visibility or the code changes.
    public static let didChangeNotification = Notification.Name("ShadowSpaceDidChange")

    public enum Space: Equatable {
        case main
        case second
    }

    public enum Visibility: Int, CaseIterable {
        case everywhere = 0
        case mainOnly = 1
        case secondOnly = 2

        public var title: String {
            switch self {
            case .everywhere:
                return "Везде"
            case .mainOnly:
                return "Только основное"
            case .secondOnly:
                return "Только второе"
            }
        }

        public func isVisible(in space: Space) -> Bool {
            switch self {
            case .everywhere:
                return true
            case .mainOnly:
                return space == .main
            case .secondOnly:
                return space == .second
            }
        }
    }

    // Format of the Telegram passcode; the second code must match it so the
    // passcode screen accepts it.
    public enum CodeFormat: Equatable {
        case digits(Int)
        case text
    }

    private enum Key {
        static let visibility = "shadow.spaces.visibility.v1"
        static let code = "shadow.spaces.code.v1"
        static let savedMute = "shadow.spaces.savedMute.v1"
        static let exclusive = "shadow.spaces.secondExclusive.v1"
    }

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var activeSpaceValue: Space = .main
    // accountPeerId -> peerId -> raw visibility; mirrors UserDefaults so the
    // chat list can query it per row without decoding.
    private var visibilityCache: [Int64: [Int64: Int]]
    // When on, the second space shows only "only second" chats: every other
    // chat (including "everywhere" and new ones) stays in the main space.
    private var secondSpaceExclusiveValue: Bool

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        self.visibilityCache = ShadowSpaceStore.decodeVisibility(defaults.dictionary(forKey: Key.visibility))
        self.secondSpaceExclusiveValue = defaults.bool(forKey: Key.exclusive)
    }

    public var secondSpaceExclusive: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.secondSpaceExclusiveValue
    }

    public func setSecondSpaceExclusive(_ value: Bool) {
        self.lock.lock()
        self.secondSpaceExclusiveValue = value
        self.defaults.set(value, forKey: Key.exclusive)
        self.lock.unlock()
        self.notifyChanged()
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: ShadowSpaceStore.didChangeNotification, object: self)
    }

    // MARK: Active space

    public var activeSpace: Space {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.activeSpaceValue
    }

    public func setActiveSpace(_ space: Space) {
        self.lock.lock()
        let changed = self.activeSpaceValue != space
        self.activeSpaceValue = space
        self.lock.unlock()
        if changed {
            self.notifyChanged()
        }
    }

    // Starts or ends the duress session (ShadowDisguise.isDuressActive) and
    // lets the chat list re-filter.
    public func setDuressActive(_ value: Bool) {
        let changed = ShadowDisguise.shared.isDuressActive != value
        ShadowDisguise.shared.setDuressActive(value)
        if changed {
            self.notifyChanged()
        }
    }

    // MARK: Visibility

    private static func decodeVisibility(_ dictionary: [String: Any]?) -> [Int64: [Int64: Int]] {
        var result: [Int64: [Int64: Int]] = [:]
        for (accountKey, value) in dictionary ?? [:] {
            guard let accountPeerId = Int64(accountKey), let peers = value as? [String: Int] else {
                continue
            }
            var mapped: [Int64: Int] = [:]
            for (peerKey, raw) in peers {
                if let peerId = Int64(peerKey), let visibility = Visibility(rawValue: raw), visibility != .everywhere {
                    mapped[peerId] = raw
                }
            }
            if !mapped.isEmpty {
                result[accountPeerId] = mapped
            }
        }
        return result
    }

    private func persistVisibility() {
        var dictionary: [String: [String: Int]] = [:]
        for (accountPeerId, peers) in self.visibilityCache where !peers.isEmpty {
            var mapped: [String: Int] = [:]
            for (peerId, raw) in peers {
                mapped["\(peerId)"] = raw
            }
            dictionary["\(accountPeerId)"] = mapped
        }
        self.defaults.set(dictionary, forKey: Key.visibility)
    }

    public func visibility(accountPeerId: Int64, peerId: Int64) -> Visibility {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.visibilityCache[accountPeerId]?[peerId].flatMap(Visibility.init(rawValue:)) ?? .everywhere
    }

    // Chats with a non-default visibility.
    public func customVisibilities(accountPeerId: Int64) -> [Int64: Visibility] {
        self.lock.lock()
        defer { self.lock.unlock() }
        var result: [Int64: Visibility] = [:]
        for (peerId, raw) in self.visibilityCache[accountPeerId] ?? [:] {
            if let visibility = Visibility(rawValue: raw) {
                result[peerId] = visibility
            }
        }
        return result
    }

    public func setVisibility(_ visibility: Visibility, accountPeerId: Int64, peerIds: [Int64]) {
        self.lock.lock()
        var peers = self.visibilityCache[accountPeerId] ?? [:]
        for peerId in peerIds {
            peers[peerId] = visibility == .everywhere ? nil : visibility.rawValue
        }
        self.visibilityCache[accountPeerId] = peers.isEmpty ? nil : peers
        self.persistVisibility()
        self.lock.unlock()
        self.notifyChanged()
    }

    // True when the chat must not be shown in the active space.
    // Shadow: the Full disguise (ShadowDisguise) shows every chat and ignores the
    // second code, like stock Telegram.
    // A duress session (ShadowDisguise.isDuressActive) also hides locked chats
    // and every «only second» chat, so nothing reveals that they exist.
    public func isHidden(accountPeerId: Int64, peerId: Int64) -> Bool {
        if ShadowDisguise.shared.isDuressActive {
            if ShadowChatLockStore.shared.isLocked(accountPeerId: accountPeerId, peerId: peerId) {
                return true
            }
            return self.visibility(accountPeerId: accountPeerId, peerId: peerId) == .secondOnly
        }
        if ShadowDisguise.shared.isFull {
            return false
        }
        self.lock.lock()
        defer { self.lock.unlock() }
        let visibility = self.visibilityCache[accountPeerId]?[peerId].flatMap(Visibility.init(rawValue:)) ?? .everywhere
        if self.activeSpaceValue == .second && self.secondSpaceExclusiveValue {
            return visibility != .secondOnly
        }
        return !visibility.isVisible(in: self.activeSpaceValue)
    }

    // Chats with a stored visibility that are hidden in the active space (used by
    // the folder unread badges). The exclusive second space hides every other
    // chat too, which cannot be listed; those are not covered here.
    public func hiddenPeerIds(accountPeerId: Int64) -> [Int64] {
        if ShadowDisguise.shared.isDuressActive {
            let locked = ShadowChatLockStore.shared.lockedPeerIds(accountPeerId: accountPeerId)
            let second = self.customVisibilities(accountPeerId: accountPeerId).compactMap { $0.value == .secondOnly ? $0.key : nil }
            return Array(Set(locked + second)).sorted()
        }
        if ShadowDisguise.shared.isFull {
            return []
        }
        self.lock.lock()
        defer { self.lock.unlock() }
        let space = self.activeSpaceValue
        return (self.visibilityCache[accountPeerId] ?? [:]).compactMap { peerId, raw in
            guard let visibility = Visibility(rawValue: raw) else {
                return nil
            }
            return visibility.isVisible(in: space) ? nil : peerId
        }
    }

    // MARK: Saved mute state

    // Opaque string from the caller (TelegramCore encodes the PeerMuteState).
    public func saveMuteState(_ value: String, accountPeerId: Int64, peerId: Int64) {
        var map = (self.defaults.dictionary(forKey: Key.savedMute) as? [String: String]) ?? [:]
        let key = "\(accountPeerId):\(peerId)"
        if map[key] == nil {
            map[key] = value
            self.defaults.set(map, forKey: Key.savedMute)
        }
    }

    public func takeSavedMuteState(accountPeerId: Int64, peerId: Int64) -> String? {
        var map = (self.defaults.dictionary(forKey: Key.savedMute) as? [String: String]) ?? [:]
        let key = "\(accountPeerId):\(peerId)"
        guard let value = map.removeValue(forKey: key) else {
            return nil
        }
        self.defaults.set(map, forKey: Key.savedMute)
        return value
    }

    // MARK: Second code

    public var hasCode: Bool {
        return self.defaults.dictionary(forKey: Key.code) != nil
    }

    // Normalizes Arabic-Indic and other Unicode digits to ASCII, as the passcode screen does.
    public static func normalize(_ code: String) -> String {
        var result = ""
        for character in code {
            if character.isNumber, let value = character.wholeNumberValue, (0 ... 9).contains(value) {
                result += String(value)
            } else {
                result.append(character)
            }
        }
        return result
    }

    // nil when the code is acceptable; otherwise the reason it is not.
    public static func validationError(code: String, format: CodeFormat, mainCode: String) -> String? {
        let code = ShadowSpaceStore.normalize(code)
        switch format {
        case let .digits(length):
            if code.count != length || !code.allSatisfy({ $0.isASCII && $0.isNumber }) {
                return "Код должен состоять из \(length) цифр, как код-пароль Telegram"
            }
        case .text:
            if code.count < ShadowChatLockStore.minimumPasswordLength {
                return "Минимум \(ShadowChatLockStore.minimumPasswordLength) символа"
            }
        }
        if code == ShadowSpaceStore.normalize(mainCode) {
            return "Код совпадает с код-паролем Telegram"
        }
        return nil
    }

    @discardableResult
    public func setCode(_ code: String) -> Bool {
        let code = ShadowSpaceStore.normalize(code)
        var generator = SystemRandomNumberGenerator()
        let salt = Data((0 ..< 16).map { _ in UInt8.random(in: 0 ... 255, using: &generator) })
        guard !code.isEmpty, let hash = ShadowChatLockStore.derive(password: code, salt: salt, iterations: ShadowChatLockStore.iterations) else {
            return false
        }
        self.defaults.set([
            "salt": salt,
            "hash": hash,
            "iterations": Int(ShadowChatLockStore.iterations)
        ], forKey: Key.code)
        self.notifyChanged()
        return true
    }

    public func verifyCode(_ code: String) -> Bool {
        if ShadowDisguise.shared.isFull {
            return false
        }
        let code = ShadowSpaceStore.normalize(code)
        guard !code.isEmpty, let stored = self.defaults.dictionary(forKey: Key.code),
              let salt = stored["salt"] as? Data,
              let hash = stored["hash"] as? Data,
              let iterations = stored["iterations"] as? Int, iterations > 0,
              let candidate = ShadowChatLockStore.derive(password: code, salt: salt, iterations: UInt32(iterations)),
              candidate.count == hash.count else {
            return false
        }
        var difference: UInt8 = 0
        for (a, b) in zip(candidate, hash) {
            difference |= a ^ b
        }
        return difference == 0
    }

    // Removes the code and every visibility (all accounts). The caller restores
    // the current account's mute states first.
    public func removeCode() {
        self.lock.lock()
        self.defaults.removeObject(forKey: Key.code)
        self.defaults.removeObject(forKey: Key.visibility)
        self.defaults.removeObject(forKey: Key.exclusive)
        self.visibilityCache = [:]
        self.secondSpaceExclusiveValue = false
        self.activeSpaceValue = .main
        self.lock.unlock()
        self.notifyChanged()
    }
}

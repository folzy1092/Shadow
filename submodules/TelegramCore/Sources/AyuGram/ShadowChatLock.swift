import Foundation
import CommonCrypto

// Shadow: per-chat lock (spec docs/specs/2026-10-01-shadow-batch.md, section 5).
//
// Device-local state in UserDefaults:
//   * locked chats, per account (account peer id -> peer ids);
//   * one device password, stored only as PBKDF2-HMAC-SHA256(salt, 100k);
//   * the time a "forgot password" reset was requested (it completes after an hour).
// Session state (chats unlocked until the app goes to background) lives in memory.
//
// Foundation + CommonCrypto only, so it is unit-tested by the Foundation suite.
public final class ShadowChatLockStore {
    public static let shared = ShadowChatLockStore(defaults: .standard)

    // Posted (on the calling thread) whenever locks, the password or a pending reset change.
    public static let didChangeNotification = Notification.Name("ShadowChatLockDidChange")

    public static let resetDelay: TimeInterval = 60.0 * 60.0
    public static let minimumPasswordLength = 4
    static let iterations: UInt32 = 100_000

    private enum Key {
        static let locked = "shadow.chatLock.locked.v1"
        static let password = "shadow.chatLock.password.v1"
        static let resetRequestedAt = "shadow.chatLock.resetRequestedAt.v1"
    }

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var unlocked = Set<String>()

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    private static func sessionKey(accountPeerId: Int64, peerId: Int64) -> String {
        return "\(accountPeerId):\(peerId)"
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: ShadowChatLockStore.didChangeNotification, object: self)
    }

    // MARK: Locked chats

    private func lockedMap() -> [String: [String]] {
        return (self.defaults.dictionary(forKey: Key.locked) as? [String: [String]]) ?? [:]
    }

    public func lockedPeerIds(accountPeerId: Int64) -> [Int64] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return (self.lockedMap()["\(accountPeerId)"] ?? []).compactMap(Int64.init)
    }

    public func isLocked(accountPeerId: Int64, peerId: Int64) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.lockedMap()["\(accountPeerId)"]?.contains("\(peerId)") ?? false
    }

    public var hasLockedChats: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.lockedMap().values.contains(where: { !$0.isEmpty })
    }

    public func setLocked(_ locked: Bool, accountPeerId: Int64, peerId: Int64) {
        self.lock.lock()
        var map = self.lockedMap()
        var peers = map["\(accountPeerId)"] ?? []
        peers.removeAll(where: { $0 == "\(peerId)" })
        if locked {
            peers.append("\(peerId)")
            // A chat locked during this session starts locked.
            self.unlocked.remove(ShadowChatLockStore.sessionKey(accountPeerId: accountPeerId, peerId: peerId))
        }
        map["\(accountPeerId)"] = peers.isEmpty ? nil : peers
        self.defaults.set(map, forKey: Key.locked)
        self.lock.unlock()
        self.notifyChanged()
    }

    // MARK: Session

    // True while the chat must be covered: locked and not unlocked in this session.
    public func requiresUnlock(accountPeerId: Int64, peerId: Int64) -> Bool {
        guard self.isLocked(accountPeerId: accountPeerId, peerId: peerId) else {
            return false
        }
        self.lock.lock()
        defer { self.lock.unlock() }
        return !self.unlocked.contains(ShadowChatLockStore.sessionKey(accountPeerId: accountPeerId, peerId: peerId))
    }

    // A successful unlock also proves the owner is present, so it cancels a
    // pending "forgot password" reset.
    public func markUnlocked(accountPeerId: Int64, peerId: Int64) {
        self.lock.lock()
        self.unlocked.insert(ShadowChatLockStore.sessionKey(accountPeerId: accountPeerId, peerId: peerId))
        self.lock.unlock()
        self.cancelReset()
    }

    // Called when a chat screen closes: every entry asks for Face ID / the password again.
    public func relock(accountPeerId: Int64, peerId: Int64) {
        self.lock.lock()
        let removed = self.unlocked.remove(ShadowChatLockStore.sessionKey(accountPeerId: accountPeerId, peerId: peerId)) != nil
        self.lock.unlock()
        if removed {
            self.notifyChanged()
        }
    }

    // Called when the app goes to background.
    public func relockAll() {
        self.lock.lock()
        self.unlocked.removeAll()
        self.lock.unlock()
        self.notifyChanged()
    }

    // MARK: Password

    public var hasPassword: Bool {
        return self.defaults.dictionary(forKey: Key.password) != nil
    }

    static func derive(password: String, salt: Data, iterations: UInt32) -> Data? {
        let passwordData = Array(password.utf8)
        guard !passwordData.isEmpty else {
            return nil
        }
        let derivedLength = Int(CC_SHA256_DIGEST_LENGTH)
        var derived = [UInt8](repeating: 0, count: derivedLength)
        let saltBytes = [UInt8](salt)
        let status = passwordData.withUnsafeBufferPointer { passwordBuffer -> Int32 in
            return passwordBuffer.baseAddress!.withMemoryRebound(to: Int8.self, capacity: passwordData.count) { passwordPointer -> Int32 in
                return CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordPointer,
                    passwordData.count,
                    saltBytes,
                    saltBytes.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    iterations,
                    &derived,
                    derivedLength
                )
            }
        }
        guard status == Int32(kCCSuccess) else {
            return nil
        }
        return Data(derived)
    }

    @discardableResult
    public func setPassword(_ password: String) -> Bool {
        guard password.count >= ShadowChatLockStore.minimumPasswordLength else {
            return false
        }
        var generator = SystemRandomNumberGenerator()
        let salt = Data((0 ..< 16).map { _ in UInt8.random(in: 0 ... 255, using: &generator) })
        guard let hash = ShadowChatLockStore.derive(password: password, salt: salt, iterations: ShadowChatLockStore.iterations) else {
            return false
        }
        self.defaults.set([
            "salt": salt,
            "hash": hash,
            "iterations": Int(ShadowChatLockStore.iterations)
        ], forKey: Key.password)
        self.notifyChanged()
        return true
    }

    public func verifyPassword(_ password: String) -> Bool {
        guard !password.isEmpty, let stored = self.defaults.dictionary(forKey: Key.password),
              let salt = stored["salt"] as? Data,
              let hash = stored["hash"] as? Data,
              let iterations = stored["iterations"] as? Int, iterations > 0,
              let candidate = ShadowChatLockStore.derive(password: password, salt: salt, iterations: UInt32(iterations)),
              candidate.count == hash.count else {
            return false
        }
        // Constant-time comparison.
        var difference: UInt8 = 0
        for (a, b) in zip(candidate, hash) {
            difference |= a ^ b
        }
        return difference == 0
    }

    // MARK: Reset

    public var resetRequestedAt: Date? {
        let value = self.defaults.double(forKey: Key.resetRequestedAt)
        return value > 0 ? Date(timeIntervalSince1970: value) : nil
    }

    public func requestReset(now: Date = Date()) {
        if self.resetRequestedAt == nil {
            self.defaults.set(now.timeIntervalSince1970, forKey: Key.resetRequestedAt)
            self.notifyChanged()
        }
    }

    public func cancelReset() {
        if self.resetRequestedAt != nil {
            self.defaults.removeObject(forKey: Key.resetRequestedAt)
            self.notifyChanged()
        }
    }

    // Seconds left before a password-less reset is allowed; nil when none is pending.
    public func resetRemaining(now: Date = Date()) -> TimeInterval? {
        guard let requestedAt = self.resetRequestedAt else {
            return nil
        }
        return max(0.0, ShadowChatLockStore.resetDelay - now.timeIntervalSince(requestedAt))
    }

    public func canResetWithoutPassword(now: Date = Date()) -> Bool {
        return self.resetRemaining(now: now) == 0.0
    }

    // Removes every lock (all accounts), the password and any pending reset.
    public func performReset() {
        self.lock.lock()
        self.defaults.removeObject(forKey: Key.locked)
        self.defaults.removeObject(forKey: Key.password)
        self.defaults.removeObject(forKey: Key.resetRequestedAt)
        self.unlocked.removeAll()
        self.lock.unlock()
        self.notifyChanged()
    }
}

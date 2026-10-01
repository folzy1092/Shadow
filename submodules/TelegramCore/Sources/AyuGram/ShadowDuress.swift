import Foundation

// Shadow: emergency protection.
//
//   * Duress code — a third code for the app lock screen. It unlocks the app
//     into a «clean» session (ShadowDisguise.isDuressActive): the main space
//     without locked chats, without «only second» chats and with every Shadow
//     settings entry point hidden. Optionally it also logs out of the chosen
//     accounts. The session ends when the main code, the second code or
//     Face ID / Touch ID unlocks the app.
//   * Panic gesture — face the phone down, shake it, or triple-tap with two
//     fingers; it runs one of PanicAction right away, without any code.
//
// Device-local state in UserDefaults; the code is stored only as
// PBKDF2-HMAC-SHA256 (ShadowChatLockStore.derive). Foundation only (with
// ShadowSpaces.swift, ShadowChatLock.swift and ShadowDisguise.swift), so it is
// unit-tested by the Foundation suite.
public final class ShadowDuress {
    public static let shared = ShadowDuress(defaults: .standard)

    // Posted on the main thread when a setting or the code changes.
    public static let didChangeNotification = Notification.Name("ShadowDuressDidChange")
    // Posted on the main thread when the duress code was entered; userInfo
    // carries `logoutAccountPeerIdsKey` ([Int64]) for the app to log out of.
    public static let didTriggerNotification = Notification.Name("ShadowDuressDidTrigger")
    public static let logoutAccountPeerIdsKey = "accountPeerIds"
    // Posted on the main thread after the panic gesture ran its action.
    public static let didPanicNotification = Notification.Name("ShadowDuressDidPanic")

    public enum PanicGesture: Int, CaseIterable {
        case off = 0
        case faceDown = 1
        case shake = 2
        case twoFingerTripleTap = 3

        public var title: String {
            switch self {
            case .off:
                return "Выключен"
            case .faceDown:
                return "Перевернуть экраном вниз"
            case .shake:
                return "Встряхнуть"
            case .twoFingerTripleTap:
                return "Тройной тап двумя пальцами"
            }
        }
    }

    public enum PanicAction: Int, CaseIterable {
        // Leaves the second space for the main one.
        case hideSecondSpace = 0
        // The same clean session as the duress code.
        case clean = 1
        // ShadowDisguise Full: stock Telegram. Full turns chat locks and the
        // second space off, so locked and second-space chats become visible.
        case fullDisguise = 2

        public var title: String {
            switch self {
            case .hideSecondSpace:
                return "Скрыть второе пространство"
            case .clean:
                return "Чистый режим"
            case .fullDisguise:
                return "Full-маскировка"
            }
        }
    }

    private enum Key {
        static let code = "shadow.duress.code.v1"
        static let logoutAccounts = "shadow.duress.logoutAccounts.v1"
        static let panicGesture = "shadow.duress.panicGesture.v1"
        static let panicAction = "shadow.duress.panicAction.v1"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    private func notify(_ name: Notification.Name, userInfo: [AnyHashable: Any]? = nil) {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: name, object: self, userInfo: userInfo)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: name, object: self, userInfo: userInfo)
            }
        }
    }

    // MARK: Code

    public var hasCode: Bool {
        return self.defaults.dictionary(forKey: Key.code) != nil
    }

    // nil when the code is acceptable; otherwise the reason it is not. It must
    // differ from the Telegram passcode and from the second-space code.
    public static func validationError(code: String, format: ShadowSpaceStore.CodeFormat, mainCode: String, matchesSecondCode: (String) -> Bool) -> String? {
        if let error = ShadowSpaceStore.validationError(code: code, format: format, mainCode: mainCode) {
            return error
        }
        if matchesSecondCode(ShadowSpaceStore.normalize(code)) {
            return "Код совпадает с кодом второго пространства"
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
        self.notify(ShadowDuress.didChangeNotification)
        return true
    }

    // The Full disguise turns the duress code off, like the second code.
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

    public func removeCode() {
        self.defaults.removeObject(forKey: Key.code)
        self.defaults.removeObject(forKey: Key.logoutAccounts)
        self.notify(ShadowDuress.didChangeNotification)
    }

    // MARK: Accounts to log out of

    public var logoutAccountPeerIds: [Int64] {
        return ((self.defaults.array(forKey: Key.logoutAccounts) as? [String]) ?? []).compactMap(Int64.init).sorted()
    }

    public func setLogout(_ value: Bool, accountPeerId: Int64) {
        var ids = Set(self.logoutAccountPeerIds)
        if value {
            ids.insert(accountPeerId)
        } else {
            ids.remove(accountPeerId)
        }
        self.defaults.set(ids.sorted().map { "\($0)" }, forKey: Key.logoutAccounts)
        self.notify(ShadowDuress.didChangeNotification)
    }

    // Called by the lock screen after the duress code matched: starts the clean
    // session and asks the app to log out of the chosen accounts.
    public func trigger() {
        ShadowSpaceStore.shared.setActiveSpace(.main)
        ShadowSpaceStore.shared.setDuressActive(true)
        self.notify(ShadowDuress.didTriggerNotification, userInfo: [ShadowDuress.logoutAccountPeerIdsKey: self.logoutAccountPeerIds])
    }

    // MARK: Panic gesture

    public var panicGesture: PanicGesture {
        return PanicGesture(rawValue: self.defaults.integer(forKey: Key.panicGesture)) ?? .off
    }

    public func setPanicGesture(_ value: PanicGesture) {
        self.defaults.set(value.rawValue, forKey: Key.panicGesture)
        self.notify(ShadowDuress.didChangeNotification)
    }

    public var panicAction: PanicAction {
        return PanicAction(rawValue: self.defaults.integer(forKey: Key.panicAction)) ?? .hideSecondSpace
    }

    public func setPanicAction(_ value: PanicAction) {
        self.defaults.set(value.rawValue, forKey: Key.panicAction)
        self.notify(ShadowDuress.didChangeNotification)
    }

    // The gesture does nothing in the Full disguise (there is nothing left to
    // hide) and when no gesture is chosen.
    public var isPanicGestureActive: Bool {
        return self.panicGesture != .off && !ShadowDisguise.shared.isFull
    }

    // Runs the chosen action. Returns false when there was nothing to do.
    @discardableResult
    public func panic() -> Bool {
        guard self.isPanicGestureActive else {
            return false
        }
        switch self.panicAction {
        case .hideSecondSpace:
            guard ShadowSpaceStore.shared.activeSpace == .second else {
                return false
            }
            ShadowSpaceStore.shared.setActiveSpace(.main)
        case .clean:
            guard !ShadowDisguise.shared.isDuressActive || ShadowSpaceStore.shared.activeSpace != .main else {
                return false
            }
            ShadowSpaceStore.shared.setActiveSpace(.main)
            ShadowSpaceStore.shared.setDuressActive(true)
        case .fullDisguise:
            ShadowSpaceStore.shared.setActiveSpace(.main)
            ShadowDisguise.shared.setMode(.full)
        }
        self.notify(ShadowDuress.didPanicNotification)
        return true
    }
}

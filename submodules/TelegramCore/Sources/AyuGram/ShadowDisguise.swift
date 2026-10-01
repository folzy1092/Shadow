import Foundation

// Shadow: disguise mode, switched from the hidden Telegram debug menu (tap the
// Settings tab several times). Device-wide, kept in UserDefaults.
//
//   * off      — Shadow as usual;
//   * settings — Shadow's settings entry points are hidden (settings rows, search,
//                long press in the chat list), every feature keeps working;
//   * full     — the app behaves and looks like stock Telegram: fork settings read
//                as their stock values (AyuGramSettings.vanillaSettings), chat
//                locks, the second space, hidden accounts and the wrong-password
//                camera are off, kept deleted messages are not shown. Nothing is
//                erased: switching back restores everything.
//
// Foundation only, so it is unit-tested by the Foundation suite.
public final class ShadowDisguise {
    public static let shared = ShadowDisguise(defaults: .standard)

    // Posted on the main thread whenever the mode changes.
    public static let didChangeNotification = Notification.Name("ShadowDisguiseDidChange")

    public enum Mode: Int32, CaseIterable {
        case off = 0
        case settings = 1
        case full = 2

        public var title: String {
            switch self {
            case .off:
                return "Shadow: показывать"
            case .settings:
                return "Shadow: скрыть настройки"
            case .full:
                return "Shadow: Full (обычный Telegram)"
            }
        }
    }

    private enum Key {
        static let mode = "shadow.disguise.mode.v1"
    }

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var cachedMode: Mode?
    // Clean session opened by the duress code or the panic gesture
    // (ShadowDuress). Memory only: a relaunch starts without it, and the main
    // code, the second code or biometrics end it.
    private var duressActiveValue = false

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public var mode: Mode {
        self.lock.lock()
        defer { self.lock.unlock() }
        if let cachedMode = self.cachedMode {
            return cachedMode
        }
        let value = Mode(rawValue: Int32(self.defaults.integer(forKey: Key.mode))) ?? .off
        self.cachedMode = value
        return value
    }

    // Fork settings entry points are hidden (both "settings" and "full", and
    // during a duress session).
    public var hidesSettings: Bool {
        return self.mode != .off || self.isDuressActive
    }

    public var isDuressActive: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.duressActiveValue
    }

    public func setDuressActive(_ value: Bool) {
        self.lock.lock()
        let changed = self.duressActiveValue != value
        self.duressActiveValue = value
        self.lock.unlock()
        if changed {
            self.postChange()
        }
    }

    // Every fork feature is off and the UI is stock Telegram.
    public var isFull: Bool {
        return self.mode == .full
    }

    // Switching into Full, or out of any hiding mode, must be confirmed by the
    // owner (Face ID / password); only hiding the settings needs no confirmation.
    public static func requiresAuthentication(from current: Mode, to target: Mode) -> Bool {
        if current == target {
            return false
        }
        return target == .full || current != .off
    }

    public func setMode(_ mode: Mode) {
        self.lock.lock()
        let changed = self.cachedMode != mode
        self.cachedMode = mode
        self.defaults.set(Int(mode.rawValue), forKey: Key.mode)
        self.lock.unlock()
        if changed {
            self.postChange()
        }
    }

    private func postChange() {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: ShadowDisguise.didChangeNotification, object: self)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: ShadowDisguise.didChangeNotification, object: self)
            }
        }
    }
}

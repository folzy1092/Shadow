import Foundation

// Shadow: photos taken after a wrong password (spec docs/specs/2026-10-01-shadow-batch.md, 7.2).
// The capture itself lives in PasscodeUI (camera); this store keeps the photos
// on the device until they are delivered to Saved Messages after the next unlock.
//
// Foundation only, so it is unit-tested by the Foundation suite.
public final class ShadowIntruderLog {
    public static let shared = ShadowIntruderLog(
        defaults: .standard,
        directory: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("shadow-intruders", isDirectory: true)
    )

    public enum Reason: String, CaseIterable {
        case passcode
        case chatLock

        public var title: String {
            switch self {
            case .passcode:
                return "неверный код-пароль"
            case .chatLock:
                return "неверный пароль замка чата"
            }
        }
    }

    public struct Entry: Equatable {
        public let url: URL
        public let date: Date
        public let reason: Reason
    }

    // Minimum time between two photos, so a burst of wrong codes makes one photo.
    public static let minimumInterval: TimeInterval = 15.0

    private enum Key {
        static let enabled = "shadow.intruder.enabled.v1"
    }

    private let defaults: UserDefaults
    private let directory: URL
    private let lock = NSLock()
    private var lastCaptureAt: Date?

    public init(defaults: UserDefaults, directory: URL) {
        self.defaults = defaults
        self.directory = directory
    }

    public var isEnabled: Bool {
        get {
            return self.defaults.bool(forKey: Key.enabled)
        }
        set {
            self.defaults.set(newValue, forKey: Key.enabled)
        }
    }

    // True when a new photo should be taken now (enabled and not rate-limited).
    public func beginCapture(now: Date = Date()) -> Bool {
        guard self.isEnabled else {
            return false
        }
        self.lock.lock()
        defer { self.lock.unlock() }
        if let last = self.lastCaptureAt, now.timeIntervalSince(last) < ShadowIntruderLog.minimumInterval {
            return false
        }
        self.lastCaptureAt = now
        return true
    }

    @discardableResult
    public func save(jpeg: Data, reason: Reason, date: Date = Date()) -> URL? {
        guard !jpeg.isEmpty else {
            return nil
        }
        do {
            try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            let url = self.directory.appendingPathComponent("\(Int64(date.timeIntervalSince1970 * 1000))-\(reason.rawValue).jpg")
            try jpeg.write(to: url, options: [.atomic])
            return url
        } catch {
            return nil
        }
    }

    // Undelivered photos, oldest first.
    public func pending() -> [Entry] {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: self.directory, includingPropertiesForKeys: nil) else {
            return []
        }
        var result: [Entry] = []
        for url in urls where url.pathExtension == "jpg" {
            let parts = url.deletingPathExtension().lastPathComponent.split(separator: "-", maxSplits: 1)
            guard parts.count == 2, let millis = Int64(parts[0]), let reason = Reason(rawValue: String(parts[1])) else {
                continue
            }
            result.append(Entry(url: url, date: Date(timeIntervalSince1970: TimeInterval(millis) / 1000.0), reason: reason))
        }
        return result.sorted(by: { $0.date < $1.date })
    }

    public func remove(_ entry: Entry) {
        try? FileManager.default.removeItem(at: entry.url)
    }
}

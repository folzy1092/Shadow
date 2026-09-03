import Foundation

public struct ShadowMessageScreenshotSettings: Codable, Equatable {
    public enum Background: Int32, Codable, CaseIterable {
        case chat = 0
        case customImage = 1
        case white = 2
        case black = 3
    }

    public var enabled: Bool = true
    public var background: Background = .chat
    public var showAvatars: Bool = true
    public var showNames: Bool = true
    public var showBadges: Bool = true
    public var showTime: Bool = true

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case enabled, background, showAvatars, showNames, showBadges, showTime
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        self.background = Background(rawValue: try c.decodeIfPresent(Int32.self, forKey: .background) ?? 0) ?? .chat
        self.showAvatars = try c.decodeIfPresent(Bool.self, forKey: .showAvatars) ?? true
        self.showNames = try c.decodeIfPresent(Bool.self, forKey: .showNames) ?? true
        self.showBadges = try c.decodeIfPresent(Bool.self, forKey: .showBadges) ?? true
        self.showTime = try c.decodeIfPresent(Bool.self, forKey: .showTime) ?? true
    }

    // Fixed, account-local path. Never accept a path from an imported settings file.
    public static func backgroundURL(mediaBoxPath: String) -> URL {
        return URL(fileURLWithPath: mediaBoxPath, isDirectory: true).appendingPathComponent("shadow-message-screenshot.jpg")
    }

    // Bound allocations while keeping ordinary selections in a single image.
    public static func renderScale(width: Double, height: Double) -> Double? {
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
        let scale = min(2.0, sqrt(16_000_000.0 / (width * height)), 16_384.0 / height)
        return scale >= 0.5 ? scale : nil
    }
}

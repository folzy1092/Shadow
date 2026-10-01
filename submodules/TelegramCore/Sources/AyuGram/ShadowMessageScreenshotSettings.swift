import Foundation

public struct ShadowMessageScreenshotSettings: Codable, Equatable {
    public enum Background: Int32, Codable, CaseIterable {
        case chat = 0
        case customImage = 1
        case customColor = 2
    }

    // Legacy raw values:
    // 2 = white
    // 3 = black
    //
    // New raw value 2 means customColor. Presence of customColorARGB
    // distinguishes the new format from the legacy white background.
    public static let legacyWhiteARGB: Int32 = Int32(bitPattern: 0xFFFFFFFF)
    public static let legacyBlackARGB: Int32 = Int32(bitPattern: 0xFF000000)

    public var enabled: Bool = true
    public var anonymize: Bool = false
    public var anonymizeOwn: Bool = true
    public var anonymizeOthers: Bool = true
    public var anonymizedPeerIds: [Int64] = []
    public var background: Background = .chat
    public var customColorARGB: Int32 = ShadowMessageScreenshotSettings.legacyBlackARGB
    public var showAvatars: Bool = true
    public var showNames: Bool = true
    public var showBadges: Bool = true
    public var showTime: Bool = true
    public var showReactions: Bool = true
    public var showOwnName: Bool = true
    public var showPeerNames: Bool = true
    public var showOwnAvatar: Bool = true
    public var showPeerAvatars: Bool = true

    public init() {
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case anonymize, anonymizeOwn, anonymizeOthers, anonymizedPeerIds
        case background
        case customColorARGB
        case showAvatars
        case showNames
        case showBadges
        case showTime
        case showReactions
        case showOwnName
        case showPeerNames
        case showOwnAvatar
        case showPeerAvatars
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        self.enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        self.anonymize = try c.decodeIfPresent(Bool.self, forKey: .anonymize) ?? false
        self.anonymizeOwn = try c.decodeIfPresent(Bool.self, forKey: .anonymizeOwn) ?? true
        self.anonymizeOthers = try c.decodeIfPresent(Bool.self, forKey: .anonymizeOthers) ?? true
        self.anonymizedPeerIds = try c.decodeIfPresent([Int64].self, forKey: .anonymizedPeerIds) ?? []

        let rawBackground = try c.decodeIfPresent(Int32.self, forKey: .background) ?? Background.chat.rawValue
        let storedCustomColorARGB = try c.decodeIfPresent(Int32.self, forKey: .customColorARGB)

        // Do not collapse this into decodeIfPresent defaults.
        // Field presence is what distinguishes legacy white (raw 2)
        // from the new customColor representation (also raw 2).
        switch rawBackground {
        case 2:
            self.background = .customColor
            if let storedCustomColorARGB {
                // New representation.
                self.customColorARGB = storedCustomColorARGB
            } else {
                // Legacy raw value 2 = white.
                self.customColorARGB = Self.legacyWhiteARGB
            }
        case 3:
            // Legacy raw value 3 = black.
            self.background = .customColor
            self.customColorARGB = Self.legacyBlackARGB
        default:
            self.background = Background(rawValue: rawBackground) ?? .chat
            self.customColorARGB = storedCustomColorARGB ?? Self.legacyBlackARGB
        }

        self.showAvatars = try c.decodeIfPresent(Bool.self, forKey: .showAvatars) ?? true
        self.showNames = try c.decodeIfPresent(Bool.self, forKey: .showNames) ?? true
        self.showBadges = try c.decodeIfPresent(Bool.self, forKey: .showBadges) ?? true
        self.showTime = try c.decodeIfPresent(Bool.self, forKey: .showTime) ?? true
        self.showReactions = try c.decodeIfPresent(Bool.self, forKey: .showReactions) ?? true
        self.showOwnName = try c.decodeIfPresent(Bool.self, forKey: .showOwnName) ?? true
        self.showPeerNames = try c.decodeIfPresent(Bool.self, forKey: .showPeerNames) ?? true
        self.showOwnAvatar = try c.decodeIfPresent(Bool.self, forKey: .showOwnAvatar) ?? true
        self.showPeerAvatars = try c.decodeIfPresent(Bool.self, forKey: .showPeerAvatars) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)

        try c.encode(self.enabled, forKey: .enabled)
        try c.encode(self.anonymize, forKey: .anonymize)
        try c.encode(self.anonymizeOwn, forKey: .anonymizeOwn)
        try c.encode(self.anonymizeOthers, forKey: .anonymizeOthers)
        try c.encode(self.anonymizedPeerIds, forKey: .anonymizedPeerIds)

        // Postbox does not support the single-value container used by the
        // raw-value enum's synthesized encoder. Keep explicit Int32 encoding.
        try c.encode(self.background.rawValue, forKey: .background)
        try c.encode(self.customColorARGB, forKey: .customColorARGB)

        try c.encode(self.showAvatars, forKey: .showAvatars)
        try c.encode(self.showNames, forKey: .showNames)
        try c.encode(self.showBadges, forKey: .showBadges)
        try c.encode(self.showTime, forKey: .showTime)
        try c.encode(self.showReactions, forKey: .showReactions)
        try c.encode(self.showOwnName, forKey: .showOwnName)
        try c.encode(self.showPeerNames, forKey: .showPeerNames)
        try c.encode(self.showOwnAvatar, forKey: .showOwnAvatar)
        try c.encode(self.showPeerAvatars, forKey: .showPeerAvatars)
    }

    public func anonymizes(peerId: Int64, accountPeerId: Int64) -> Bool {
        guard self.anonymize else { return false }
        if peerId == accountPeerId { return self.anonymizeOwn }
        return self.anonymizeOthers || self.anonymizedPeerIds.contains(peerId)
    }

    // Fixed, account-local path. Never accept a path from an imported settings file.
    public static func backgroundURL(mediaBoxPath: String) -> URL {
        return URL(fileURLWithPath: mediaBoxPath, isDirectory: true)
            .appendingPathComponent("shadow-message-screenshot.jpg")
    }

    // Bound allocations while keeping ordinary selections in a single image.
    public static func renderScale(width: Double, height: Double) -> Double? {
        guard width.isFinite, height.isFinite, width > 0, height > 0 else {
            return nil
        }

        let scale = min(
            2.0,
            sqrt(16_000_000.0 / (width * height)),
            16_384.0 / height
        )

        return scale >= 0.5 ? scale : nil
    }
}

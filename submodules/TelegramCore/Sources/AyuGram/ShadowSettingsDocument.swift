import Foundation

public enum ShadowSettingsTransferError: Error, LocalizedError {
    case invalidFormat
    case unsupportedVersion(Int)
    case invalidValue(String)
    case tooLarge

    public var errorDescription: String? {
        switch self {
        case .invalidFormat: return "Это не файл настроек Shadow или файл повреждён."
        case let .unsupportedVersion(version): return "Версия формата \(version) не поддерживается. Обновите Shadow. Настройки не изменены."
        case let .invalidValue(key): return "Недопустимое значение настройки: \(key). Ничего не импортировано."
        case .tooLarge: return "Файл настроек превышает лимит 1 МБ."
        }
    }
}

public enum ShadowSettingValue: Equatable {
    case bool(Bool)
    case integer(Int64)
    case text(String)
}

// A deliberately closed allowlist. New account fields are NOT exported until
// explicitly reviewed here and in ShadowSettingsTransfer's key-path mapping.
public struct ShadowSettingsDocument: Codable, Equatable {
    public static let maximumBytes = 1024 * 1024
    public static let booleanKeys: Set<String> = [
        "keepDeletedMessages", "saveEditHistory", "keepSelfDestructMedia",
        "ghostMode", "hideOnlineStatus", "hideTyping", "hideReadReceipts",
        "hideStoryViews", "askBeforeStoryView", "sendViaScheduled", "sendWithoutOnline",
        "showMessageSeconds", "editedIndicatorAsPencil", "regularEmojiFirst",
        "doubleTapToEdit", "showExactLastSeen", "showExactLastSeenSeconds",
        "wideChannelPosts", "showExactViewCounts", "showForwardCount", "preferUsernameForNonContacts", "preferUsernameForBots",
        "hideAllChatsFolder", "foldersAtBottom", "hideBottomSearch", "compactBottomBar",
        "allowSaveRestrictedContent", "roundVideoUseBackCamera", "showCameraTile",
        "cameraTileLivePreview", "confirmCalls", "saveDestructingMedia",
        "saveAllIncomingMedia", "mediaAutoCleanKeepPinned", "mediaAutoCleanKeepChannels",
        "mediaAutoCleanKeepBots", "showProfileId", "showProfileDC",
        "showRegistrationDate", "hideOwnPhoneNumber",
        "screenshotEnabled", "screenshotAvatars", "screenshotNames", "screenshotBadges", "screenshotTime"
    ]
    public static let textKeys: Set<String> = ["editedIndicatorText", "deletedIndicatorText"]
    public static let integerKeys: Set<String> = ["mediaAutoCleanInterval", "attachmentSizeLimit", "bottomBarScrollMode", "screenshotBackground"]
    private static let ageIntervals: Set<Int64> = [0, 86400, 259200, 604800, 1209600, 2592000, 7776000, 15552000, 31536000]
    private static let sizeLimits: Set<Int64> = [0, 314572800, 1073741824, 2147483648, 5368709120, 6442450944, 12884901888]

    public let version: Int
    public let exportedAt: String
    public let settings: [String: ShadowSettingValue]

    private enum CodingKeys: String, CodingKey { case format, version, exportedAt, settings }
    private struct SettingKey: CodingKey {
        let stringValue: String
        var intValue: Int? { return nil }
        init(_ value: String) { self.stringValue = value }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    public init(settings: [String: ShadowSettingValue], date: Date = Date()) throws {
        try Self.validate(settings)
        self.version = 1
        self.exportedAt = ISO8601DateFormatter().string(from: date)
        self.settings = settings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .format) == "shadow-settings" else {
            throw ShadowSettingsTransferError.invalidFormat
        }
        let version = try container.decode(Int.self, forKey: .version)
        guard version == 1 else { throw ShadowSettingsTransferError.unsupportedVersion(version) }
        self.version = version
        self.exportedAt = try container.decode(String.self, forKey: .exportedAt)
        guard ISO8601DateFormatter().date(from: self.exportedAt) != nil else {
            throw ShadowSettingsTransferError.invalidFormat
        }
        let values = try container.nestedContainer(keyedBy: SettingKey.self, forKey: .settings)
        var settings: [String: ShadowSettingValue] = [:]
        // Decode only known fields. Unknown nested values are ignored too.
        for key in values.allKeys {
            do {
                if Self.booleanKeys.contains(key.stringValue) {
                    settings[key.stringValue] = .bool(try values.decode(Bool.self, forKey: key))
                } else if Self.textKeys.contains(key.stringValue) {
                    settings[key.stringValue] = .text(try values.decode(String.self, forKey: key))
                } else if Self.integerKeys.contains(key.stringValue) {
                    settings[key.stringValue] = .integer(try values.decode(Int64.self, forKey: key))
                }
            } catch {
                throw ShadowSettingsTransferError.invalidValue(key.stringValue)
            }
        }
        try Self.validate(settings)
        self.settings = settings
    }

    private static func validate(_ settings: [String: ShadowSettingValue]) throws {
        guard !settings.isEmpty else { throw ShadowSettingsTransferError.invalidFormat }
        for (key, value) in settings {
            switch value {
            case .bool where booleanKeys.contains(key): break
            case let .text(text) where textKeys.contains(key) && text.count <= 64: break
            case let .integer(number) where key == "mediaAutoCleanInterval" && ageIntervals.contains(number): break
            case let .integer(number) where key == "attachmentSizeLimit" && sizeLimits.contains(number): break
            case let .integer(number) where key == "bottomBarScrollMode" && (0...2).contains(number): break
            case let .integer(number) where key == "screenshotBackground" && (0...3).contains(number): break
            default: throw ShadowSettingsTransferError.invalidValue(key)
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("shadow-settings", forKey: .format)
        try container.encode(self.version, forKey: .version)
        try container.encode(self.exportedAt, forKey: .exportedAt)
        var values = container.nestedContainer(keyedBy: SettingKey.self, forKey: .settings)
        for (key, value) in self.settings {
            switch value {
            case let .bool(value): try values.encode(value, forKey: SettingKey(key))
            case let .integer(value): try values.encode(value, forKey: SettingKey(key))
            case let .text(value): try values.encode(value, forKey: SettingKey(key))
            }
        }
    }

    public static func decode(_ data: Data) throws -> ShadowSettingsDocument {
        guard data.count <= Self.maximumBytes else { throw ShadowSettingsTransferError.tooLarge }
        do {
            return try JSONDecoder().decode(Self.self, from: data)
        } catch let error as ShadowSettingsTransferError {
            throw error
        } catch {
            throw ShadowSettingsTransferError.invalidFormat
        }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumBytes else { throw ShadowSettingsTransferError.tooLarge }
        return data
    }
}

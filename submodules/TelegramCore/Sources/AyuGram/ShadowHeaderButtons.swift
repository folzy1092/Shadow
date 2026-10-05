import Foundation

// Shadow: customizable buttons in the root chat list header.
//
// Left side: up to 2 buttons, right side: up to 3 (more would squeeze the
// "Чаты" title on a phone). Each button has a tap action and an optional
// long-press action. The default layout repeats stock Shadow: "Изм." on the
// left; new story, Ghost (long press: Ghost settings) and compose on the right.
//
// Stored inside AyuGramSettings (per account). Actions are stored as their
// String raw values, not as a Codable enum: Postbox's Codable adapter traps on
// raw enums (see test_shadow_postbox.py), and an unknown value from a newer
// build must not break decoding — it simply reads as `.none`.
//
// Foundation only, so it is unit-tested by the Foundation suite.
public enum ShadowHeaderAction: String, CaseIterable {
    case none
    case edit
    case newStory
    case ghostMode
    case ghostSettings
    case compose
    case search
    case readAllServer
    case readAllLocal
    case readFolder
    case toggleHideOnline
    case toggleHideReadReceipts
    case toggleHideTyping
    case savedMessages
    case archive
    case deletedArchive
    case editedArchive
    case shadowSettings
    case quickReplies
    case lockApp
    case switchAccount
    case proxy
    case nightMode
    case storage
    case customLink

    public init(storedValue: String) {
        self = ShadowHeaderAction(rawValue: storedValue) ?? .none
    }

    public var title: String {
        switch self {
        case .none: return "Ничего"
        case .edit: return "Изменить (выбор чатов)"
        case .newStory: return "Новая история"
        case .ghostMode: return "Призрак вкл/выкл"
        case .ghostSettings: return "Настройки Призрака"
        case .compose: return "Написать сообщение"
        case .search: return "Поиск"
        case .readAllServer: return "Прочитать все (на сервере)"
        case .readAllLocal: return "Прочитать все (локально)"
        case .readFolder: return "Прочитать текущую папку"
        case .toggleHideOnline: return "Скрывать онлайн вкл/выкл"
        case .toggleHideReadReceipts: return "Не отправлять прочтения вкл/выкл"
        case .toggleHideTyping: return "Скрывать набор текста вкл/выкл"
        case .savedMessages: return "Избранное"
        case .archive: return "Архив чатов"
        case .deletedArchive: return "Удалённые сообщения"
        case .editedArchive: return "Отредактированные сообщения"
        case .shadowSettings: return "Настройки Shadow"
        case .quickReplies: return "Шаблоны ответов"
        case .lockApp: return "Заблокировать приложение"
        case .switchAccount: return "Следующий аккаунт"
        case .proxy: return "Прокси вкл/выкл"
        case .nightMode: return "Ночная тема вкл/выкл"
        case .storage: return "Хранилище и кэш"
        case .customLink: return "Своя ссылка…"
        }
    }

    // Actions offered in the picker, in display order. `.none` is offered
    // separately (it means "no long-press action").
    public static let selectable: [ShadowHeaderAction] = [
        .edit, .compose, .newStory, .search,
        .ghostMode, .ghostSettings, .toggleHideOnline, .toggleHideReadReceipts, .toggleHideTyping,
        .readAllServer, .readAllLocal, .readFolder,
        .savedMessages, .archive, .deletedArchive, .editedArchive,
        .shadowSettings, .quickReplies, .lockApp, .switchAccount,
        .proxy, .nightMode, .storage, .customLink
    ]
}

public struct ShadowHeaderButton: Codable, Equatable {
    public var tapValue: String
    public var tapLink: String
    public var longPressValue: String
    public var longPressLink: String
    // SF Symbol name for a custom link button; empty = default icon.
    public var icon: String

    public var tap: ShadowHeaderAction {
        get { return ShadowHeaderAction(storedValue: self.tapValue) }
        set { self.tapValue = newValue.rawValue }
    }

    public var longPress: ShadowHeaderAction {
        get { return ShadowHeaderAction(storedValue: self.longPressValue) }
        set { self.longPressValue = newValue.rawValue }
    }

    public init(tap: ShadowHeaderAction, longPress: ShadowHeaderAction = .none, tapLink: String = "", longPressLink: String = "", icon: String = "") {
        self.tapValue = tap.rawValue
        self.tapLink = tapLink
        self.longPressValue = longPress.rawValue
        self.longPressLink = longPressLink
        self.icon = icon
    }

    private enum CodingKeys: String, CodingKey {
        case tap
        case tapLink
        case longPress
        case longPressLink
        case icon
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.tapValue = (try container.decodeIfPresent(String.self, forKey: .tap)) ?? ShadowHeaderAction.none.rawValue
        self.tapLink = (try container.decodeIfPresent(String.self, forKey: .tapLink)) ?? ""
        self.longPressValue = (try container.decodeIfPresent(String.self, forKey: .longPress)) ?? ShadowHeaderAction.none.rawValue
        self.longPressLink = (try container.decodeIfPresent(String.self, forKey: .longPressLink)) ?? ""
        self.icon = (try container.decodeIfPresent(String.self, forKey: .icon)) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.tapValue, forKey: .tap)
        try container.encode(self.tapLink, forKey: .tapLink)
        try container.encode(self.longPressValue, forKey: .longPress)
        try container.encode(self.longPressLink, forKey: .longPressLink)
        try container.encode(self.icon, forKey: .icon)
    }

    // A stable string for the header button identity: when the button's
    // configuration changes, the header must rebuild it (NavigationButtonComponent
    // keeps the first closure for an unchanged identity).
    public var identityKey: String {
        return [self.tapValue, self.tapLink, self.longPressValue, self.longPressLink, self.icon].joined(separator: "|")
    }
}

public struct ShadowHeaderButtons: Codable, Equatable {
    public static let maxLeft = 2
    public static let maxRight = 3

    public var left: [ShadowHeaderButton]
    // Right side, in display order (left to right).
    public var right: [ShadowHeaderButton]

    public init(left: [ShadowHeaderButton], right: [ShadowHeaderButton]) {
        self.left = left
        self.right = right
    }

    public static let stock = ShadowHeaderButtons(
        left: [ShadowHeaderButton(tap: .edit)],
        right: [
            ShadowHeaderButton(tap: .newStory),
            ShadowHeaderButton(tap: .ghostMode, longPress: .ghostSettings),
            ShadowHeaderButton(tap: .compose)
        ]
    )

    public var isStock: Bool {
        return self == ShadowHeaderButtons.stock
    }

    // Drops buttons without a tap action and enforces the per-side limits.
    public func normalized() -> ShadowHeaderButtons {
        let left = self.left.filter { $0.tap != .none }
        let right = self.right.filter { $0.tap != .none }
        return ShadowHeaderButtons(left: Array(left.prefix(ShadowHeaderButtons.maxLeft)), right: Array(right.prefix(ShadowHeaderButtons.maxRight)))
    }

    private enum CodingKeys: String, CodingKey {
        case left
        case right
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.left = (try container.decodeIfPresent([ShadowHeaderButton].self, forKey: .left)) ?? ShadowHeaderButtons.stock.left
        self.right = (try container.decodeIfPresent([ShadowHeaderButton].self, forKey: .right)) ?? ShadowHeaderButtons.stock.right
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.left, forKey: .left)
        try container.encode(self.right, forKey: .right)
    }

    // Icons offered for a custom link button (SF Symbols available on iOS 13).
    public static let customLinkIcons: [String] = [
        "link", "star", "heart", "bolt", "flame", "paperplane",
        "person", "bell", "music.note", "gamecontroller", "cart", "globe"
    ]

    // What a custom link opens. Accepts http(s)://, tg://, shadow://,
    // t.me/<name>, @<name> and a bare username; nil when the text is not a link.
    public static func normalizedLink(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.contains(" ") {
            return nil
        }
        let lowered = trimmed.lowercased()
        if lowered.hasPrefix("https://") || lowered.hasPrefix("http://") || lowered.hasPrefix("tg://") || lowered.hasPrefix("shadow://") {
            return trimmed
        }
        if lowered.hasPrefix("t.me/") || lowered.hasPrefix("telegram.me/") {
            return "https://" + trimmed
        }
        var name = trimmed
        if name.hasPrefix("@") {
            name.removeFirst()
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
        if name.count >= 4, name.count <= 32, name.unicodeScalars.allSatisfy({ allowed.contains($0) }) {
            return "https://t.me/" + name
        }
        return nil
    }
}

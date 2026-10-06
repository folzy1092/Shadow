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
    // A Shadow settings toggle: the step link is shadow://<screen>/<slug>?on|off|switch.
    case setting

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
        case .setting: return "Тумблер настройки…"
        }
    }

    // Actions offered in the picker, in display order. `.none` is offered
    // separately (it means "no long-press action").
    // The three toggleHide* actions are kept for buttons saved by 1.1.0;
    // new buttons use `.setting` (any toggle, several per button).
    public static let selectable: [ShadowHeaderAction] = [
        .setting, .edit, .compose, .newStory, .search,
        .ghostMode, .ghostSettings,
        .readAllServer, .readAllLocal, .readFolder,
        .savedMessages, .archive, .deletedArchive, .editedArchive,
        .shadowSettings, .quickReplies, .lockApp, .switchAccount,
        .proxy, .nightMode, .storage, .customLink
    ]
}

// One action of a button. A button runs all its steps in order; settings
// toggles among them flip together (ShadowSettingLinks.groupTarget).
public struct ShadowHeaderStep: Codable, Equatable {
    public var actionValue: String
    public var link: String

    public var action: ShadowHeaderAction {
        get { return ShadowHeaderAction(storedValue: self.actionValue) }
        set { self.actionValue = newValue.rawValue }
    }

    public init(_ action: ShadowHeaderAction, link: String = "") {
        self.actionValue = action.rawValue
        self.link = link
    }

    private enum CodingKeys: String, CodingKey {
        case action
        case link
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.actionValue = (try container.decodeIfPresent(String.self, forKey: .action)) ?? ShadowHeaderAction.none.rawValue
        self.link = (try container.decodeIfPresent(String.self, forKey: .link)) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.actionValue, forKey: .action)
        try container.encode(self.link, forKey: .link)
    }
}

public struct ShadowHeaderButton: Codable, Equatable {
    public static let maxSteps = 5

    public var tapSteps: [ShadowHeaderStep]
    public var longPressSteps: [ShadowHeaderStep]
    // SF Symbol chosen by the user (ShadowHeaderButtons.iconPresets); empty = automatic.
    public var icon: String

    // The first step (what 1.1.0 stored as the only action).
    public var tap: ShadowHeaderAction {
        get { return self.tapSteps.first?.action ?? .none }
        set { let step = ShadowHeaderStep(newValue, link: self.tapLink); ShadowHeaderButton.setFirst(&self.tapSteps, step) }
    }

    public var tapLink: String {
        get { return self.tapSteps.first?.link ?? "" }
        set { let step = ShadowHeaderStep(self.tap, link: newValue); ShadowHeaderButton.setFirst(&self.tapSteps, step) }
    }

    public var longPress: ShadowHeaderAction {
        get { return self.longPressSteps.first?.action ?? .none }
        set { let step = ShadowHeaderStep(newValue, link: self.longPressLink); ShadowHeaderButton.setFirst(&self.longPressSteps, step) }
    }

    public var longPressLink: String {
        get { return self.longPressSteps.first?.link ?? "" }
        set { let step = ShadowHeaderStep(self.longPress, link: newValue); ShadowHeaderButton.setFirst(&self.longPressSteps, step) }
    }

    private static func setFirst(_ steps: inout [ShadowHeaderStep], _ step: ShadowHeaderStep) {
        if steps.isEmpty {
            steps = [step]
        } else {
            steps[0] = step
        }
        steps = steps.filter { $0.action != .none }
    }

    public init(tap: ShadowHeaderAction, longPress: ShadowHeaderAction = .none, tapLink: String = "", longPressLink: String = "", icon: String = "") {
        self.tapSteps = tap == .none ? [] : [ShadowHeaderStep(tap, link: tapLink)]
        self.longPressSteps = longPress == .none ? [] : [ShadowHeaderStep(longPress, link: longPressLink)]
        self.icon = icon
    }

    public init(tapSteps: [ShadowHeaderStep], longPressSteps: [ShadowHeaderStep] = [], icon: String = "") {
        self.tapSteps = tapSteps
        self.longPressSteps = longPressSteps
        self.icon = icon
    }

    private enum CodingKeys: String, CodingKey {
        case tap
        case tapLink
        case longPress
        case longPressLink
        case tapSteps
        case longPressSteps
        case icon
    }

    // 1.1.0 stored one action per gesture (tap/tapLink); newer builds store the
    // step lists and keep writing the first step the old way for downgrades.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let steps = try container.decodeIfPresent([ShadowHeaderStep].self, forKey: .tapSteps) {
            self.tapSteps = steps
        } else {
            let tap = ShadowHeaderAction(storedValue: (try container.decodeIfPresent(String.self, forKey: .tap)) ?? "")
            let link = (try container.decodeIfPresent(String.self, forKey: .tapLink)) ?? ""
            self.tapSteps = tap == .none ? [] : [ShadowHeaderStep(tap, link: link)]
        }
        if let steps = try container.decodeIfPresent([ShadowHeaderStep].self, forKey: .longPressSteps) {
            self.longPressSteps = steps
        } else {
            let longPress = ShadowHeaderAction(storedValue: (try container.decodeIfPresent(String.self, forKey: .longPress)) ?? "")
            let link = (try container.decodeIfPresent(String.self, forKey: .longPressLink)) ?? ""
            self.longPressSteps = longPress == .none ? [] : [ShadowHeaderStep(longPress, link: link)]
        }
        self.icon = (try container.decodeIfPresent(String.self, forKey: .icon)) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.tapSteps, forKey: .tapSteps)
        try container.encode(self.longPressSteps, forKey: .longPressSteps)
        try container.encode(self.tap.rawValue, forKey: .tap)
        try container.encode(self.tapLink, forKey: .tapLink)
        try container.encode(self.longPress.rawValue, forKey: .longPress)
        try container.encode(self.longPressLink, forKey: .longPressLink)
        try container.encode(self.icon, forKey: .icon)
    }

    // Unknown actions dropped, at most maxSteps per gesture.
    public func normalized() -> ShadowHeaderButton {
        var result = self
        result.tapSteps = Array(self.tapSteps.filter { $0.action != .none }.prefix(ShadowHeaderButton.maxSteps))
        result.longPressSteps = Array(self.longPressSteps.filter { $0.action != .none }.prefix(ShadowHeaderButton.maxSteps))
        return result
    }

    // A stable string for the header button identity: when the button's
    // configuration changes, the header must rebuild it (NavigationButtonComponent
    // keeps the first closure for an unchanged identity).
    public var identityKey: String {
        let tap = self.tapSteps.map { $0.actionValue + ">" + $0.link }.joined(separator: ",")
        let longPress = self.longPressSteps.map { $0.actionValue + ">" + $0.link }.joined(separator: ",")
        return [tap, longPress, self.icon].joined(separator: "|")
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
        let left = self.left.map { $0.normalized() }.filter { $0.tap != .none }
        let right = self.right.map { $0.normalized() }.filter { $0.tap != .none }
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

    // Icons a button can use instead of its automatic one: the Shadow logo,
    // the Ghost, and SF Symbols with a ".fill" variant (iOS 13), drawn while
    // the button's toggles are on.
    public static let iconPresets: [String] = [
        "shadow", "ghost", "pencil.circle", "clock", "eye.slash", "moon", "bolt", "flame",
        "star", "heart", "bell", "shield", "paperplane", "person"
    ]

    public static func iconTitle(_ icon: String) -> String {
        switch icon {
        case "": return "Автоматически"
        case "shadow": return "Логотип Shadow"
        case "ghost": return "Призрак"
        case "pencil.circle": return "Карандаш"
        case "clock": return "Часы"
        case "eye.slash": return "Перечёркнутый глаз"
        case "moon": return "Луна"
        case "bolt": return "Молния"
        case "flame": return "Огонь"
        case "star": return "Звезда"
        case "heart": return "Сердце"
        case "bell": return "Колокольчик"
        case "shield": return "Щит"
        case "paperplane": return "Самолётик"
        case "person": return "Человек"
        case "link": return "Ссылка"
        default: return icon
        }
    }

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

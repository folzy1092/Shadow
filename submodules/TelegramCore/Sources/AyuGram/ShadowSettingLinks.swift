import Foundation

// Shadow: a link for every Shadow settings toggle.
//
//   shadow://<screen>/<slug>          open the screen, scroll to the toggle, pulse it
//   shadow://<screen>/<slug>?on       turn it on   (asks first from a message / browser)
//   shadow://<screen>/<slug>?off      turn it off
//   shadow://<screen>/<slug>?switch   flip it
//   shadow://<screen>/<slug>?value=N  a setting with a choice of values: pick N
//   …&v=1.4.4                         the Shadow version the setting appeared in
//                                     (`since`): an older Shadow that does not
//                                     know the setting says which version it needs
//
// `screen` is the ShadowLinks command of the screen (ShadowLinkRouter);
// `entryId` is the toggle's stableId on that screen (focus, long-press menu);
// `key` is the AyuGramSettings field (ShadowSettingsTransfer.boolValue/setBool,
// or intValue/setInt for a choice: `choices` holds its titles by value).
// Protected toggles (chat locks, second space…) only open; a link never changes
// them. Toggles without a key live outside AyuGramSettings and only open too.
//
// Foundation only, so it is unit-tested by the Foundation suite.
public struct ShadowSettingLink: Equatable {
    public let screen: String
    public let slug: String
    public let entryId: Int32
    public let key: String?
    public let title: String
    public let isProtected: Bool
    // SF Symbol for a header button; empty = the generic on/off icon.
    public let icon: String
    // Shown only while this entry is on (dependent toggles): focus falls back to it.
    public let parentEntryId: Int32?
    // A setting with a choice of values (not on/off): the title of each value,
    // the value being the index. Empty for toggles.
    public let choices: [String]
    // The Shadow version the setting appeared in (1.4.4 and later); links carry
    // it as ?v=. Older settings have none.
    public let since: String?

    public init(screen: String, slug: String, entryId: Int32, key: String?, title: String, isProtected: Bool = false, icon: String = "", parentEntryId: Int32? = nil, choices: [String] = [], since: String? = nil) {
        self.screen = screen
        self.slug = slug
        self.entryId = entryId
        self.key = key
        self.title = title
        self.isProtected = isProtected
        self.icon = icon
        self.parentEntryId = parentEntryId
        self.choices = choices
        self.since = since
    }

    // An on/off toggle a link can change.
    public var isSwitchable: Bool {
        return self.key != nil && !self.isProtected && self.choices.isEmpty
    }

    // A choice a link can set with ?value=N.
    public var isChoice: Bool {
        return self.key != nil && !self.isProtected && !self.choices.isEmpty
    }

    public func choiceTitle(_ value: Int32) -> String? {
        guard value >= 0, Int(value) < self.choices.count else {
            return nil
        }
        return self.choices[Int(value)]
    }

    public var path: String {
        return "shadow://\(self.screen)/\(self.slug)"
    }

    public func link(_ mode: ShadowSettingLinks.Mode) -> String {
        let result: String
        switch mode {
        case .open: result = self.path
        case .on: result = self.path + "?on"
        case .off: result = self.path + "?off"
        case .toggle: result = self.path + "?switch"
        case let .value(value): result = self.path + "?value=\(value)"
        }
        guard let since = self.since else {
            return result
        }
        return result + (result.contains("?") ? "&" : "?") + "v=\(since)"
    }
}

public enum ShadowSettingLinks {
    public enum Mode: Equatable {
        case open
        case on
        case off
        case toggle
        case value(Int32)
    }

    // `query` is ShadowLinks.Link.query: "?switch" parses as ["switch": ""].
    public static func mode(query: [String: String]) -> Mode {
        if let raw = query["value"] ?? query["set"], let value = Int32(raw.trimmingCharacters(in: .whitespaces)) {
            return .value(value)
        }
        if query["switch"] != nil || query["toggle"] != nil {
            return .toggle
        }
        if query["on"] != nil {
            return .on
        }
        if query["off"] != nil {
            return .off
        }
        if let value = query["state"]?.lowercased() {
            switch value {
            case "on", "1", "true": return .on
            case "off", "0", "false": return .off
            case "switch", "toggle": return .toggle
            default: break
            }
        }
        return .open
    }

    // A link this Shadow cannot open: a setting or screen it does not know.
    // `linkVersion` is the link's ?v=, `current` is ShadowVersion.fork.
    public static func isScreen(_ command: String) -> Bool {
        let command = command.lowercased()
        return self.all.contains(where: { $0.screen == command })
    }

    public static func needsUpdate(linkVersion: String?, current: String) -> Bool {
        guard let linkVersion else {
            return false
        }
        return self.compareVersions(linkVersion, current) == .orderedDescending
    }

    public static func unsupportedText(isSetting: Bool, linkVersion: String?, current: String) -> String {
        let what = isSetting ? "Эта настройка" : "Эта ссылка"
        if let linkVersion, self.needsUpdate(linkVersion: linkVersion, current: current) {
            return "\(what) работает с Shadow \(linkVersion). У вас \(current) — обновите Shadow."
        }
        if isSetting {
            return "Такой настройки нет в Shadow \(current). Если ссылку прислали из новой версии — обновите Shadow."
        }
        return "Такой ссылки нет в Shadow \(current). Если её прислали из новой версии — обновите Shadow."
    }

    // "1.4.10" > "1.4.9"; missing parts count as 0, non-digits are ignored.
    public static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        func parts(_ value: String) -> [Int] {
            return value.split(separator: ".").map { part in Int(part.filter { character in character.isNumber }) ?? 0 }
        }
        let left = parts(lhs)
        let right = parts(rhs)
        for index in 0 ..< max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r {
                return l < r ? .orderedAscending : .orderedDescending
            }
        }
        return .orderedSame
    }

    public static func find(screen: String, slug: String) -> ShadowSettingLink? {
        let screen = screen.lowercased()
        let slug = slug.lowercased()
        return self.all.first(where: { $0.screen == screen && $0.slug == slug })
    }

    public static func find(screen: String, entryId: Int32) -> ShadowSettingLink? {
        return self.all.first(where: { $0.screen == screen && $0.entryId == entryId })
    }

    // A settings link with its mode, or nil when `string` is not one.
    public static func resolve(_ string: String) -> (ShadowSettingLink, Mode)? {
        guard let link = ShadowLinks.parse(string), let slug = link.arguments.first, let setting = self.find(screen: link.command, slug: slug) else {
            return nil
        }
        return (setting, self.mode(self.mode(query: link.query), for: setting))
    }

    // ?value=N means nothing for a toggle (nor an unknown N), ?on/?off/?switch
    // nothing for a choice: those just open the setting.
    public static func mode(_ mode: Mode, for setting: ShadowSettingLink) -> Mode {
        switch mode {
        case let .value(value):
            if !setting.isChoice || setting.choiceTitle(value) == nil {
                return .open
            }
        case .on, .off, .toggle:
            if setting.isChoice {
                return .open
            }
        case .open:
            break
        }
        return mode
    }

    // Shared on/off for a group: flipping turns everything on unless all of it
    // is already on, then everything off (a header button with several toggles).
    public static func groupTarget(currentValues: [Bool]) -> Bool {
        return !currentValues.allSatisfy { $0 }
    }

    public static let screenTitles: [String: String] = [
        "ghost": "Призрак",
        "spy": "Сохранение",
        "customization": "Кастомизация",
        "profile": "Подмена профиля",
        "misc": "Разное",
        "filters": "Фильтры",
        "screenshot": "Скриншоты сообщений",
        "locks": "Замки чатов",
        "space": "Второе пространство",
        "feed": "Лента"
    ]

    public static let screenOrder: [String] = ["ghost", "spy", "customization", "screenshot", "filters", "profile", "misc", "locks", "space", "feed"]

    public static let all: [ShadowSettingLink] = [
        // Призрак (AyuGhostEntry)
        ShadowSettingLink(screen: "ghost", slug: "mode", entryId: 1, key: "ghostMode", title: "Режим призрака", icon: "ghost"),
        ShadowSettingLink(screen: "ghost", slug: "online", entryId: 2, key: "hideOnlineStatus", title: "Не показывать онлайн", icon: "person.crop.circle"),
        ShadowSettingLink(screen: "ghost", slug: "typing", entryId: 3, key: "hideTyping", title: "Не показывать набор текста", icon: "pencil.circle"),
        ShadowSettingLink(screen: "ghost", slug: "read", entryId: 4, key: "hideReadReceipts", title: "Не отправлять прочтения", icon: "eye.slash"),
        ShadowSettingLink(screen: "ghost", slug: "stories", entryId: 5, key: "hideStoryViews", title: "Скрывать просмотры историй", icon: "circle.dashed"),
        ShadowSettingLink(screen: "ghost", slug: "offer-stories", entryId: 12, key: "offerGhostBeforeStories", title: "Предлагать призрак перед историями", icon: "questionmark.circle"),
        ShadowSettingLink(screen: "ghost", slug: "scheduled", entryId: 8, key: "sendViaScheduled", title: "Отправлять через отложенные", icon: "clock"),
        ShadowSettingLink(screen: "ghost", slug: "send-offline", entryId: 9, key: "sendWithoutOnline", title: "Отправлять без появления онлайн", icon: "paperplane"),

        // Шпион (AyuSpyEntry)
        ShadowSettingLink(screen: "spy", slug: "deleted", entryId: 1, key: "keepDeletedMessages", title: "Сохранять удалённые", icon: "trash"),
        ShadowSettingLink(screen: "spy", slug: "deleted-secret", entryId: 2, key: "keepDeletedSecretChatMessages", title: "Сохранять удалённые в секретных чатах", icon: "lock"),
        ShadowSettingLink(screen: "spy", slug: "view-once", entryId: 3, key: "keepSelfDestructMedia", title: "Сохранять «одноразовые»", icon: "flame"),
        ShadowSettingLink(screen: "spy", slug: "edit-history", entryId: 6, key: "saveEditHistory", title: "Сохранять историю правок", icon: "pencil"),
        ShadowSettingLink(screen: "spy", slug: "edit-compare", entryId: 7, key: "showEditComparisonAction", title: "Показывать «Сравнить правки»"),
        ShadowSettingLink(screen: "spy", slug: "save-restricted", entryId: 10, key: "allowSaveRestrictedContent", title: "Разрешить сохранение", icon: "square.and.arrow.down"),
        ShadowSettingLink(screen: "spy", slug: "ask-story-view", entryId: 13, key: "askBeforeStoryView", title: "Спросить перед просмотром истории"),
        ShadowSettingLink(screen: "spy", slug: "save-destructing", entryId: 16, key: "saveDestructingMedia", title: "Сохранять самоуничтожающиеся", icon: "timer"),
        ShadowSettingLink(screen: "spy", slug: "save-all-media", entryId: 17, key: "saveAllIncomingMedia", title: "Сохранять все входящие медиа", icon: "photo"),
        ShadowSettingLink(screen: "spy", slug: "clean-keep-pinned", entryId: 20, key: "mediaAutoCleanKeepPinned", title: "Не очищать закреплённые"),
        ShadowSettingLink(screen: "spy", slug: "clean-skip-channels", entryId: 21, key: "mediaAutoCleanKeepChannels", title: "Исключить каналы"),
        ShadowSettingLink(screen: "spy", slug: "clean-skip-bots", entryId: 22, key: "mediaAutoCleanKeepBots", title: "Исключить ботов"),
        ShadowSettingLink(screen: "spy", slug: "online-history", entryId: 26, key: "onlineHistory", title: "Записывать, когда контакты в сети", icon: "chart.bar"),
        ShadowSettingLink(screen: "spy", slug: "save-stories", entryId: 29, key: "saveViewedStories", title: "Сохранять просмотренные истории"),

        // Кастомизация (AyuCustomizationEntry)
        ShadowSettingLink(screen: "customization", slug: "seconds", entryId: 1, key: "showMessageSeconds", title: "Секунды в метках времени", icon: "clock"),
        ShadowSettingLink(screen: "customization", slug: "edited-pencil", entryId: 2, key: "editedIndicatorAsPencil", title: "Значок ✎ вместо «Изменено»", icon: "pencil"),
        ShadowSettingLink(screen: "customization", slug: "emoji-first", entryId: 3, key: "regularEmojiFirst", title: "Обычные эмодзи в начале клавиатуры"),
        ShadowSettingLink(screen: "customization", slug: "double-tap-edit", entryId: 4, key: "doubleTapToEdit", title: "Двойной тап — редактирование"),
        ShadowSettingLink(screen: "customization", slug: "exact-last-seen", entryId: 5, key: "showExactLastSeen", title: "Точное время последнего захода"),
        ShadowSettingLink(screen: "customization", slug: "last-seen-seconds", entryId: 6, key: "showExactLastSeenSeconds", title: "Секунды у последнего захода", parentEntryId: 5),
        ShadowSettingLink(screen: "customization", slug: "wide-posts", entryId: 7, key: "wideChannelPosts", title: "Широкие посты в каналах"),
        ShadowSettingLink(screen: "customization", slug: "exact-views", entryId: 8, key: "showExactViewCounts", title: "Точные просмотры на постах"),
        ShadowSettingLink(screen: "customization", slug: "forward-count", entryId: 9, key: "showForwardCount", title: "Счётчик пересылок"),
        ShadowSettingLink(screen: "customization", slug: "username", entryId: 94, key: "preferUsernameForNonContacts", title: "@username вместо имени незнакомых", icon: "at"),
        ShadowSettingLink(screen: "customization", slug: "username-bots", entryId: 95, key: "preferUsernameForBots", title: "@username также для ботов", parentEntryId: 94),
        ShadowSettingLink(screen: "customization", slug: "mono-icons", entryId: 106, key: "monochromeSettingsIcons", title: "Одноцветные иконки"),
        // Settings that are not on/off or not in AyuGramSettings: links only open them.
        ShadowSettingLink(screen: "customization", slug: "icon-background", entryId: 107, key: nil, title: "Цвет фона иконок", parentEntryId: 106),
        ShadowSettingLink(screen: "customization", slug: "icon-glyph", entryId: 108, key: nil, title: "Цвет значков", parentEntryId: 106),
        ShadowSettingLink(screen: "customization", slug: "edited-text", entryId: 90, key: nil, title: "Свой значок правки"),
        ShadowSettingLink(screen: "customization", slug: "deleted-text", entryId: 91, key: nil, title: "Свой значок удалёнки"),
        ShadowSettingLink(screen: "customization", slug: "message-screenshots", entryId: 93, key: nil, title: "Скриншоты сообщений", icon: "camera.viewfinder"),
        ShadowSettingLink(screen: "customization", slug: "header-buttons", entryId: 111, key: nil, title: "Кнопки шапки"),
        ShadowSettingLink(screen: "customization", slug: "banner-image", entryId: 38, key: nil, title: "Изображение баннера", parentEntryId: 37),
        ShadowSettingLink(screen: "customization", slug: "profile-background-image", entryId: 44, key: nil, title: "Изображение фона профиля", parentEntryId: 41),
        ShadowSettingLink(screen: "customization", slug: "hide-all-chats", entryId: 12, key: "hideAllChatsFolder", title: "Скрыть папку «Все чаты»", icon: "folder"),
        ShadowSettingLink(screen: "customization", slug: "hide-stories", entryId: 99, key: "hideStoriesBar", title: "Скрыть истории", icon: "circle.dashed"),
        ShadowSettingLink(screen: "customization", slug: "hide-gift", entryId: 100, key: "hideGiftButton", title: "Скрыть кнопку подарка", icon: "gift"),
        ShadowSettingLink(screen: "customization", slug: "hide-premium", entryId: 101, key: "hidePremiumBadges", title: "Скрыть значки Premium у имён", icon: "star"),
        ShadowSettingLink(screen: "customization", slug: "hide-ads", entryId: 102, key: "hideSponsoredMessages", title: "Скрыть рекламу в каналах"),
        ShadowSettingLink(screen: "customization", slug: "unlimited-pins", entryId: 104, key: "unlimitedPinnedChats", title: "Безлимитные закрепы", icon: "pin"),
        ShadowSettingLink(screen: "customization", slug: "compact-chats", entryId: 110, key: "compactChatList", title: "Компактный список чатов"),
        ShadowSettingLink(screen: "customization", slug: "hide-greeting", entryId: 116, key: "hideGreetingSticker", title: "Скрыть приветственный стикер"),
        ShadowSettingLink(screen: "customization", slug: "voice-transcription", entryId: 103, key: "localVoiceTranscription", title: "Расшифровка голосовых на устройстве", icon: "waveform"),
        ShadowSettingLink(screen: "customization", slug: "voice-time", entryId: 112, key: "voiceTimeFormat", title: "Время на голосовых", icon: "timer", choices: ShadowVoiceTime.formats.map { ShadowVoiceTime.title($0) }),
        ShadowSettingLink(screen: "customization", slug: "voice-time-round", entryId: 113, key: "voiceTimeRoundVideos", title: "Время на голосовых: также на кружках"),
        ShadowSettingLink(screen: "customization", slug: "voice-time-player", entryId: 114, key: "voiceTimeInPlayer", title: "Время на голосовых: в верхнем плеере"),
        ShadowSettingLink(screen: "customization", slug: "reply-timecode", entryId: 117, key: "replyTimecode", title: "Тайм-код в ответах", icon: "timer", since: "1.4.4"),
        ShadowSettingLink(screen: "customization", slug: "reply-timecode-mode", entryId: 118, key: "replyTimecodeMode", title: "Тайм-код в ответах: режим", parentEntryId: 117, choices: ShadowReplyTimecode.modes.map { ShadowReplyTimecode.modeTitle($0) }, since: "1.4.4"),
        ShadowSettingLink(screen: "customization", slug: "chat-voice-speed", entryId: 119, key: "chatVoiceSpeed", title: "Своя скорость для чатов", icon: "speedometer", since: "1.5.0"),
        ShadowSettingLink(screen: "customization", slug: "chat-voice-speeds", entryId: 120, key: nil, title: "Чаты со своей скоростью", parentEntryId: 119, since: "1.5.0"),
        ShadowSettingLink(screen: "customization", slug: "folders-bottom", entryId: 15, key: "foldersAtBottom", title: "Папки снизу"),
        ShadowSettingLink(screen: "customization", slug: "hide-bottom-search", entryId: 16, key: "hideBottomSearch", title: "Убрать поиск снизу"),
        ShadowSettingLink(screen: "customization", slug: "compact-bottom", entryId: 17, key: "compactBottomBar", title: "Уменьшить интерфейс снизу"),
        ShadowSettingLink(screen: "customization", slug: "bottom-bar-hiding", entryId: 92, key: "bottomBarScrollMode", title: "Скрытие нижней панели", choices: ["Всегда показывать", "Скрывать при прокрутке вниз", "Скрывать и показывать при остановке", "Скрывать при прокрутке вверх и вниз"]),
        ShadowSettingLink(screen: "customization", slug: "profile-id", entryId: 20, key: "showProfileId", title: "ID профиля (Bot API)"),
        ShadowSettingLink(screen: "customization", slug: "profile-dc", entryId: 21, key: "showProfileDC", title: "Дата-центр (DC)"),
        ShadowSettingLink(screen: "customization", slug: "registration-date", entryId: 22, key: "showRegistrationDate", title: "Дата регистрации"),
        ShadowSettingLink(screen: "customization", slug: "chat-streak", entryId: 121, key: "showChatStreak", title: "Дни подряд в профиле", since: "1.8.0"),
        ShadowSettingLink(screen: "customization", slug: "hide-phone", entryId: 23, key: "hideOwnPhoneNumber", title: "Скрыть свой номер", icon: "phone"),
        ShadowSettingLink(screen: "customization", slug: "round-back-camera", entryId: 26, key: "roundVideoUseBackCamera", title: "Кружки на заднюю камеру", icon: "camera"),
        ShadowSettingLink(screen: "customization", slug: "camera-tile", entryId: 27, key: "showCameraTile", title: "Камера в галерее", icon: "camera"),
        ShadowSettingLink(screen: "customization", slug: "camera-live", entryId: 28, key: "cameraTileLivePreview", title: "Живой предпросмотр камеры"),
        ShadowSettingLink(screen: "customization", slug: "camera-compact", entryId: 115, key: "cameraTileCompact", title: "Компактная плитка камеры"),
        ShadowSettingLink(screen: "customization", slug: "round-speed", entryId: 97, key: "customVideoMessageSpeed", title: "Кастомная скорость кружков"),
        ShadowSettingLink(screen: "customization", slug: "confirm-calls", entryId: 31, key: "confirmCalls", title: "Подтверждение звонков", icon: "phone"),
        ShadowSettingLink(screen: "customization", slug: "banner", entryId: 37, key: "customBannerEnabled", title: "Кастомный баннер", icon: "photo"),
        ShadowSettingLink(screen: "customization", slug: "profile-background", entryId: 41, key: "customProfileBackgroundEnabled", title: "Кастомный фон профиля", icon: "photo"),
        ShadowSettingLink(screen: "customization", slug: "profile-background-all", entryId: 42, key: "customProfileBackgroundForOthers", title: "Фон для всех профилей", parentEntryId: 41),
        ShadowSettingLink(screen: "customization", slug: "profile-background-settings", entryId: 43, key: "customProfileBackgroundForSettings", title: "Фон в настройках", parentEntryId: 41),

        // Скриншоты сообщений (ShadowMessageScreenshotEntry)
        ShadowSettingLink(screen: "screenshot", slug: "button", entryId: 0, key: "screenshotEnabled", title: "Кнопка скриншота при выделении", icon: "camera.viewfinder"),
        ShadowSettingLink(screen: "screenshot", slug: "anonymize", entryId: 14, key: "screenshotAnonymize", title: "Анонимный скриншот", icon: "eye.slash"),
        ShadowSettingLink(screen: "screenshot", slug: "avatars", entryId: 4, key: "screenshotAvatars", title: "Скриншот: аватары"),
        ShadowSettingLink(screen: "screenshot", slug: "names", entryId: 5, key: "screenshotNames", title: "Скриншот: имена авторов"),
        ShadowSettingLink(screen: "screenshot", slug: "badges", entryId: 6, key: "screenshotBadges", title: "Скриншот: значки у имени"),
        ShadowSettingLink(screen: "screenshot", slug: "time", entryId: 7, key: "screenshotTime", title: "Скриншот: время и статус"),
        ShadowSettingLink(screen: "screenshot", slug: "reactions", entryId: 8, key: "screenshotReactions", title: "Скриншот: реакции"),
        ShadowSettingLink(screen: "screenshot", slug: "own-name", entryId: 9, key: "screenshotOwnName", title: "Скриншот: своё имя"),
        ShadowSettingLink(screen: "screenshot", slug: "peer-names", entryId: 10, key: "screenshotPeerNames", title: "Скриншот: имена собеседников"),
        ShadowSettingLink(screen: "screenshot", slug: "own-avatar", entryId: 11, key: "screenshotOwnAvatar", title: "Скриншот: своя аватарка"),
        ShadowSettingLink(screen: "screenshot", slug: "peer-avatars", entryId: 12, key: "screenshotPeerAvatars", title: "Скриншот: аватарки собеседников"),

        // Фильтры
        ShadowSettingLink(screen: "filters", slug: "placeholder", entryId: 0, key: "messageFilterShowPlaceholder", title: "Плашка «Скрыто локальным фильтром»"),
        ShadowSettingLink(screen: "filters", slug: "ads-channels", entryId: 40001, key: "adFilterChannels", title: "Реклама в каналах", since: "1.6.0"),
        ShadowSettingLink(screen: "filters", slug: "ads-groups", entryId: 40002, key: "adFilterGroups", title: "Реклама в группах", since: "1.6.0"),
        ShadowSettingLink(screen: "filters", slug: "ads-forwarded", entryId: 40003, key: "adFilterForwarded", title: "Реклама в пересланных", since: "1.6.0"),
        ShadowSettingLink(screen: "filters", slug: "ads-hide-completely", entryId: 40004, key: "adHideCompletely", title: "Скрывать рекламу полностью", since: "1.6.0"),
        // Лента (shadowFeedSettingsController)
        ShadowSettingLink(screen: "feed", slug: "enabled", entryId: 1, key: "feedEnabled", title: "Лента (бета)", since: "1.9.0"),
        ShadowSettingLink(screen: "feed", slug: "position", entryId: 3, key: "feedPosition", title: "Где кнопка ленты", choices: ShadowFeed.Position.allCases.map { $0.title }, since: "1.9.0"),
        ShadowSettingLink(screen: "feed", slug: "autoplay", entryId: 7, key: "feedAutoplay", title: "Автозапуск видео в ленте", since: "1.9.0"),
        ShadowSettingLink(screen: "feed", slug: "folders", entryId: 8, key: "feedShowFolders", title: "Папки Telegram в ленте", since: "1.9.0"),
        ShadowSettingLink(screen: "feed", slug: "muted", entryId: 9, key: "feedIncludeMuted", title: "Каналы без звука в ленте", since: "1.9.0"),
        ShadowSettingLink(screen: "feed", slug: "archived", entryId: 10, key: "feedIncludeArchived", title: "Каналы из архива в ленте", since: "1.9.0"),
        ShadowSettingLink(screen: "feed", slug: "mark-read", entryId: 11, key: "feedMarkRead", title: "Лента отмечает прочитанным", since: "1.9.0"),

        // Подмена профиля (AyuMiscEntry)
        ShadowSettingLink(screen: "profile", slug: "spoof-id", entryId: 1, key: "spoofProfileIdEnabled", title: "Подменить ID"),
        ShadowSettingLink(screen: "profile", slug: "spoof-dc", entryId: 3, key: "spoofProfileDcEnabled", title: "Подменить DC"),
        ShadowSettingLink(screen: "profile", slug: "spoof-phone", entryId: 5, key: "spoofProfilePhoneEnabled", title: "Подменить номер", icon: "phone"),

        // Разное
        ShadowSettingLink(screen: "misc", slug: "story-camera-swipe", entryId: 0, key: "disableStoryCameraSwipe", title: "Отключить свайп к камере", icon: "camera"),
        ShadowSettingLink(screen: "misc", slug: "beta", entryId: 2, key: "updateChannelBeta", title: "Бета-версии"),

        // Защитные: ссылка только открывает
        ShadowSettingLink(screen: "locks", slug: "hide-preview", entryId: 10_002, key: nil, title: "Прятать последнее сообщение", isProtected: true),
        ShadowSettingLink(screen: "locks", slug: "intruder-photo", entryId: 10_009, key: nil, title: "Фото при неверном пароле", isProtected: true),
        ShadowSettingLink(screen: "space", slug: "exclusive", entryId: 8, key: nil, title: "Во втором — только его чаты", isProtected: true)
    ]
}

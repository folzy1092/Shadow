import Foundation

enum ShadowSettingsSearchDestination: Int32 {
    case customization, spy, ghost, misc, backup

    var title: String {
        switch self {
        case .customization: return "Кастомизация"
        case .spy: return "Шпион"
        case .ghost: return "Призрак"
        case .misc: return "Разное"
        case .backup: return "Резервная копия настроек"
        }
    }
}

struct ShadowSettingsSearchItem: Equatable {
    let destination: ShadowSettingsSearchDestination
    let entryId: Int32
    let title: String
    let description: String
    let keywords: String
    var parentEntryId: Int32? = nil
    var id: Int32 { return self.destination.rawValue * 1000 + self.entryId }
    var path: String { return "Shadow → " + self.destination.title }
}

enum ShadowSettingsSearchIndex {
    static let items: [ShadowSettingsSearchItem] = [
        ShadowSettingsSearchItem(destination: .customization, entryId: 1, title: "Секунды в метках времени", description: "Время сообщений с секундами", keywords: "message seconds timestamp"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 2, title: "Значок вместо «Изменено»", description: "Иконка отредактированного сообщения", keywords: "edited pencil"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 90, title: "Свой значок правки", description: "Текст или эмодзи вместо метки правки", keywords: "edited icon marker"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 91, title: "Свой значок удалёнки", description: "Метка сохранённого удалённого сообщения", keywords: "deleted icon marker"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 3, title: "Обычные эмодзи в начале клавиатуры", description: "Порядок разделов эмодзи", keywords: "regular emoji keyboard"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 4, title: "Двойной тап: редактирование", description: "Быстро редактировать своё сообщение", keywords: "double tap edit"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 5, title: "Точное время последнего захода", description: "Показывать точное время вместо приблизительного", keywords: "last seen online онлайн"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 6, title: "Секунды у последнего захода", description: "После включения точного времени захода", keywords: "last seen seconds", parentEntryId: 5),
        ShadowSettingsSearchItem(destination: .customization, entryId: 7, title: "Широкие посты в каналах", description: "Увеличенная ширина сообщений каналов", keywords: "wide channel posts"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 8, title: "Точные просмотры на постах", description: "Полное число просмотров без сокращений", keywords: "exact view count"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 9, title: "Счётчик пересылок", description: "Число пересылок рядом со временем", keywords: "forward count"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 12, title: "Скрыть папку «Все чаты»", description: "Не показывать общую папку", keywords: "hide all chats folder"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 15, title: "Папки снизу", description: "Разместить папки над нижней панелью", keywords: "folders bottom"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 16, title: "Скрыть поиск снизу", description: "Убрать кнопку поиска из нижней панели", keywords: "hide bottom search"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 17, title: "Компактная нижняя панель", description: "Меньшая высота, без подписей вкладок", keywords: "compact bottom tab bar бар"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 20, title: "ID в профиле", description: "Показать числовой ID пользователя", keywords: "profile user id"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 21, title: "Дата-центр в профиле", description: "Показать DC фотографии", keywords: "profile data center dc"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 22, title: "Дата регистрации", description: "Приблизительная дата создания аккаунта", keywords: "registration date"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 23, title: "Скрыть свой номер", description: "Убрать строку телефона из своего профиля", keywords: "hide phone number"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 26, title: "Кружки на заднюю камеру", description: "Начинать запись с основной камеры", keywords: "round video back camera"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 27, title: "Камера в галерее", description: "Показывать плитку камеры во вложениях", keywords: "camera gallery"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 28, title: "Живой предпросмотр камеры", description: "Видео в плитке камеры", keywords: "live camera preview"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 31, title: "Подтверждение звонков", description: "Защита от случайного звонка", keywords: "confirm calls"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 34, title: "Синхронизировать с GitHub", description: "Обновить значки из конфигурации", keywords: "sync github badges стрелочка значок"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 37, title: "Кастомный баннер", description: "Фон верхней части списка чатов", keywords: "custom banner background"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 38, title: "Выбрать изображение баннера", description: "После включения кастомного баннера", keywords: "banner image photo", parentEntryId: 37),
        ShadowSettingsSearchItem(destination: .customization, entryId: 41, title: "Кастомный фон профиля", description: "Свой фон за аватаром и именем", keywords: "custom profile background"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 42, title: "Фон для всех профилей", description: "После включения кастомного фона", keywords: "profile background others", parentEntryId: 41),
        ShadowSettingsSearchItem(destination: .customization, entryId: 43, title: "Фон в настройках", description: "После включения кастомного фона", keywords: "profile background settings", parentEntryId: 41),
        ShadowSettingsSearchItem(destination: .customization, entryId: 44, title: "Выбрать изображение профиля", description: "После включения кастомного фона", keywords: "profile background image", parentEntryId: 41),
        ShadowSettingsSearchItem(destination: .spy, entryId: 1, title: "Сохранять удалённые", description: "Локальная история удалённых сообщений", keywords: "keep deleted anti delete антиреколл"),
        ShadowSettingsSearchItem(destination: .spy, entryId: 2, title: "Сохранять самоуничтожающиеся", description: "Оставлять открытые исчезающие медиа", keywords: "view once self destruct"),
        ShadowSettingsSearchItem(destination: .spy, entryId: 5, title: "История редактирования", description: "Сохранять прежние версии сообщений", keywords: "edit history"),
        ShadowSettingsSearchItem(destination: .spy, entryId: 8, title: "Сохранение защищённого контента", description: "Настройка копирования и пересылки", keywords: "restricted protected copy forward"),
        ShadowSettingsSearchItem(destination: .spy, entryId: 11, title: "Спрашивать перед просмотром истории", description: "Предупреждение перед открытием чужой истории", keywords: "ask story view"),
        ShadowSettingsSearchItem(destination: .spy, entryId: 14, title: "Сохранять исчезающие медиа", description: "Копия во внутренней галерее", keywords: "save destructing media"),
        ShadowSettingsSearchItem(destination: .spy, entryId: 15, title: "Сохранять все входящие медиа", description: "Автоматическая локальная копия вложений", keywords: "save all incoming media"),
        ShadowSettingsSearchItem(destination: .spy, entryId: 16, title: "Лимит галереи", description: "Ограничение объёма сохранённых вложений", keywords: "attachment size storage limit"),
        ShadowSettingsSearchItem(destination: .spy, entryId: 17, title: "Срок хранения медиа", description: "Автоматическая очистка по возрасту", keywords: "auto clean retention age"),
        ShadowSettingsSearchItem(destination: .spy, entryId: 18, title: "Не очищать закреплённые", description: "Исключить закреплённые чаты из очистки", keywords: "keep pinned cleanup"),
        ShadowSettingsSearchItem(destination: .spy, entryId: 19, title: "Не очищать каналы", description: "Исключить каналы из очистки", keywords: "keep channels cleanup"),
        ShadowSettingsSearchItem(destination: .spy, entryId: 20, title: "Не очищать ботов", description: "Исключить ботов из очистки", keywords: "keep bots cleanup"),
        ShadowSettingsSearchItem(destination: .spy, entryId: 21, title: "Хранилище Shadow", description: "Галерея, история и очистка", keywords: "storage archive gallery cache кэш"),
        ShadowSettingsSearchItem(destination: .ghost, entryId: 1, title: "Режим призрака", description: "Главный переключатель скрытия активности", keywords: "ghost mode приватность"),
        ShadowSettingsSearchItem(destination: .ghost, entryId: 2, title: "Не показывать онлайн", description: "Скрывать свой статус при включённом призраке", keywords: "hide online status"),
        ShadowSettingsSearchItem(destination: .ghost, entryId: 3, title: "Не показывать набор текста", description: "Не отправлять статус печати", keywords: "hide typing"),
        ShadowSettingsSearchItem(destination: .ghost, entryId: 4, title: "Не отправлять прочтения", description: "Скрывать галочки прочитанных сообщений", keywords: "hide read receipts"),
        ShadowSettingsSearchItem(destination: .ghost, entryId: 5, title: "Скрывать просмотры историй", description: "Не отмечаться среди зрителей", keywords: "hide story views"),
        ShadowSettingsSearchItem(destination: .ghost, entryId: 8, title: "Отправлять через отложенные сообщения", description: "Отправка с задержкой в режиме призрака", keywords: "scheduled delayed send"),
        ShadowSettingsSearchItem(destination: .ghost, entryId: 9, title: "Отправлять без появления онлайн", description: "Повторно устанавливать статус офлайн", keywords: "send without online offline"),
        ShadowSettingsSearchItem(destination: .misc, entryId: 1, title: "Подменить ID", description: "Визуальная подмена ID в профиле", keywords: "spoof profile id"),
        ShadowSettingsSearchItem(destination: .misc, entryId: 3, title: "Подменить DC", description: "Визуальная подмена дата-центра", keywords: "spoof dc data center"),
        ShadowSettingsSearchItem(destination: .misc, entryId: 5, title: "Подменить номер", description: "Визуальная подмена телефона", keywords: "spoof phone number"),
        ShadowSettingsSearchItem(destination: .backup, entryId: 0, title: "Экспортировать настройки", description: "Перенести настройки без сессий и личных данных", keywords: "export backup json"),
        ShadowSettingsSearchItem(destination: .backup, entryId: 1, title: "Импортировать настройки", description: "Применить файл к текущему аккаунту", keywords: "import settings json"),
        ShadowSettingsSearchItem(destination: .backup, entryId: 2, title: "Отменить последний импорт", description: "Вернуть настройки перед импортом", keywords: "undo restore backup")
    ].sorted { $0.id < $1.id }

    private static func normalized(_ value: String) -> String {
        return value.precomposedStringWithCompatibilityMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ru_RU"))
            .lowercased().replacingOccurrences(of: "ё", with: "е")
    }

    // Built once, contains labels only. No account reads, history or analytics.
    private static let searchText: [Int32: String] = Dictionary(uniqueKeysWithValues: items.map {
        ($0.id, normalized($0.title + " " + $0.description + " " + $0.keywords + " " + $0.path))
    })

    static func search(_ query: String) -> [ShadowSettingsSearchItem] {
        let tokens = normalized(String(query.prefix(256))).split(whereSeparator: { $0.isWhitespace })
        guard !tokens.isEmpty else { return [] }
        return items.filter { item in
            guard let text = searchText[item.id] else { return false }
            return tokens.allSatisfy { text.contains($0) }
        }
    }
}

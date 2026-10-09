import Foundation

enum ShadowSettingsSearchDestination: Int32 {
    case customization, spy, ghost, misc, backup, filters, pushDiagnostics, quickReplies, chatLocks, secondSpace, emergency, autoUpdate, chatStats, feed

    var title: String {
        switch self {
        case .customization: return "Кастомизация"
        case .spy: return "Сохранение"
        case .ghost: return "Призрак"
        case .misc: return "Подмена профиля"
        case .backup: return "Резервная копия настроек"
        case .filters: return "Фильтры"
        case .pushDiagnostics: return "Разное"
        case .quickReplies: return "Шаблоны ответов"
        case .chatLocks: return "Замки чатов"
        case .secondSpace: return "Второе пространство"
        case .emergency: return "Экстренная защита"
        case .autoUpdate: return "Автообновление"
        case .chatStats: return "Итоги чатов"
        case .feed: return "Лента"
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
        ShadowSettingsSearchItem(destination: .pushDiagnostics, entryId: 0, title: "Диагностика push", description: "APNs, подпись приложения, регистрация токена в Telegram и NotificationService", keywords: "notification уведомления push token esign certificate сертификат"),
        ShadowSettingsSearchItem(destination: .pushDiagnostics, entryId: 1, title: "Отключить свайп к камере", description: "Не открывать камеру истории горизонтальным свайпом из списка чатов", keywords: "камера история story camera swipe свайп жест"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 95, title: "@username для ботов", description: "Также для ботов. Доступно после включения @username вместо имени незнакомых. По умолчанию выключено.", keywords: "username юзернейм бот bot имя", parentEntryId: 94),
        ShadowSettingsSearchItem(destination: .customization, entryId: 94, title: "@username вместо имени незнакомых", description: "В списке чатов, заголовке, профиле и подписях сообщений. Сохранённые контакты не меняются.", keywords: "username юзернейм юз ник name contacts"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 111, title: "Кнопки шапки", description: "Свои кнопки слева и справа над списком чатов: нажатие и удержание, до 2 слева и до 3 справа", keywords: "header buttons шапка кнопки навбар navbar быстрые команды прочитать все призрак ссылка"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 92, title: "Скрытие нижней панели", description: "В списке чатов: скрывать вниз или в обе стороны до полной остановки.", keywords: "auto hide bottom tab bar scroll прокрутка"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 1, title: "Секунды в метках времени", description: "Время сообщений с секундами", keywords: "message seconds timestamp"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 2, title: "Значок вместо «Изменено»", description: "Иконка отредактированного сообщения", keywords: "edited pencil"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 90, title: "Свой значок правки", description: "Текст или эмодзи вместо метки правки", keywords: "edited icon marker"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 91, title: "Свой значок удалёнки", description: "Метка сохранённого удалённого сообщения", keywords: "deleted icon marker"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 3, title: "Обычные эмодзи в начале клавиатуры", description: "Порядок разделов эмодзи", keywords: "regular emoji keyboard"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 4, title: "Двойной тап: редактирование", description: "Быстро редактировать своё сообщение", keywords: "double tap edit"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 5, title: "Точное время последнего захода", description: "Показывать точное время вместо приблизительного", keywords: "last seen online онлайн"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 6, title: "Секунды у последнего захода", description: "После включения точного времени захода", keywords: "last seen seconds", parentEntryId: 5),
        ShadowSettingsSearchItem(destination: .customization, entryId: 7, title: "Широкие посты в каналах", description: "Не сжимать пузырь короткого поста по тексту. Сохраняет место для пересылки и пропорции медиа.", keywords: "wide channel posts ширина"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 93, title: "Скриншоты сообщений", description: "Кнопка камеры при выделении, фон чата, своя картинка, белый и чёрный фон, аватары, имена, значки и время", keywords: "screenshot camera photo export скрин снимок"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 8, title: "Точные просмотры на постах", description: "Полное число просмотров без сокращений", keywords: "exact view count"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 9, title: "Счётчик пересылок", description: "Число пересылок рядом со временем", keywords: "forward count"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 12, title: "Скрыть папку «Все чаты»", description: "Не показывать общую папку", keywords: "hide all chats folder"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 15, title: "Папки снизу", description: "Разместить папки над нижней панелью", keywords: "folders bottom"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 16, title: "Скрыть поиск снизу", description: "Убрать кнопку поиска из нижней панели", keywords: "hide bottom search"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 17, title: "Компактная нижняя панель", description: "Меньшая высота, без подписей вкладок", keywords: "compact bottom tab bar бар"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 20, title: "ID в профиле", description: "Показать числовой ID пользователя", keywords: "profile user id"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 21, title: "Дата-центр в профиле", description: "Показать DC фотографии", keywords: "profile data center dc"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 22, title: "Дата регистрации", description: "Приблизительная дата создания аккаунта", keywords: "registration date"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 121, title: "Дни подряд в профиле", description: "«Общаемся N дней подряд» в профиле собеседника: дни, когда писали оба", keywords: "дни подряд серия streak огонёк общаемся профиль"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 23, title: "Скрыть свой номер", description: "Убрать строку телефона из своего профиля", keywords: "hide phone number"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 26, title: "Кружки на заднюю камеру", description: "Начинать запись с основной камеры", keywords: "round video back camera"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 97, title: "Кастомная скорость кружков", description: "Менять скорость и голос перед отправкой: 0.5×–3×", keywords: "round video кружок speed скорость 0.5 0.75 1.25 1.5 2 3 голос"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 27, title: "Камера в галерее", description: "Показывать плитку камеры во вложениях", keywords: "camera gallery"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 28, title: "Живой предпросмотр камеры", description: "Видео в плитке камеры", keywords: "live camera preview"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 115, title: "Компактная плитка камеры", description: "Плитка камеры в галерее занимает одну ячейку вместо двух", keywords: "camera tile compact small gallery камера плитка компакт маленькая ячейка"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 31, title: "Подтверждение звонков", description: "Защита от случайного звонка", keywords: "confirm calls"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 37, title: "Кастомный баннер", description: "Фон верхней части списка чатов", keywords: "custom banner background"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 38, title: "Выбрать изображение баннера", description: "После включения кастомного баннера", keywords: "banner image photo", parentEntryId: 37),
        ShadowSettingsSearchItem(destination: .customization, entryId: 41, title: "Кастомный фон профиля", description: "Свой фон за аватаром и именем", keywords: "custom profile background"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 42, title: "Фон для всех профилей", description: "После включения кастомного фона", keywords: "profile background others", parentEntryId: 41),
        ShadowSettingsSearchItem(destination: .customization, entryId: 43, title: "Фон в настройках", description: "После включения кастомного фона", keywords: "profile background settings", parentEntryId: 41),
        ShadowSettingsSearchItem(destination: .customization, entryId: 44, title: "Выбрать изображение профиля", description: "После включения кастомного фона", keywords: "profile background image", parentEntryId: 41),
        ShadowSettingsSearchItem(destination: .spy, entryId: 1, title: "Сохранять удалённые", description: "Локальная история удалённых сообщений", keywords: "keep deleted anti delete антиреколл"),
        ShadowSettingsSearchItem(destination: .spy, entryId: 2, title: "Сохранять удалённые в секретных чатах", description: "Локально сохранять сообщения и загруженные медиа секретных чатов", keywords: "secret chat секретный чат удаленные фото медиа"),
        ShadowSettingsSearchItem(destination: .spy, entryId: 3, title: "Сохранять самоуничтожающиеся", description: "Оставлять открытые исчезающие медиа", keywords: "view once self destruct"),
        ShadowSettingsSearchItem(destination: .spy, entryId: 6, title: "История редактирования", description: "Сохранять прежние версии сообщений", keywords: "edit history"),
        ShadowSettingsSearchItem(destination: .spy, entryId: 7, title: "Сравнить правки", description: "Отдельно показывать действие сравнения в меню сообщения", keywords: "edit diff comparison сравнение правок"),
        ShadowSettingsSearchItem(destination: .spy, entryId: 10, title: "Сохранение защищённого контента", description: "Настройка копирования и пересылки", keywords: "restricted protected copy forward"),
        ShadowSettingsSearchItem(destination: .spy, entryId: 13, title: "Спрашивать перед просмотром истории", description: "Предупреждение перед открытием чужой истории", keywords: "ask story view"),
        ShadowSettingsSearchItem(destination: .spy, entryId: 16, title: "Сохранять исчезающие медиа", description: "Копия во внутренней галерее", keywords: "save destructing media"),
        ShadowSettingsSearchItem(destination: .spy, entryId: 17, title: "Сохранять все входящие медиа", description: "Автоматическая локальная копия вложений", keywords: "save all incoming media"),
        ShadowSettingsSearchItem(destination: .spy, entryId: 18, title: "Лимит галереи", description: "Ограничение объёма сохранённых вложений", keywords: "attachment size storage limit"),
        ShadowSettingsSearchItem(destination: .spy, entryId: 19, title: "Срок хранения медиа", description: "Автоматическая очистка по возрасту", keywords: "auto clean retention age"),
        ShadowSettingsSearchItem(destination: .spy, entryId: 20, title: "Не очищать закреплённые", description: "Исключить закреплённые чаты из очистки", keywords: "keep pinned cleanup"),
        ShadowSettingsSearchItem(destination: .spy, entryId: 21, title: "Не очищать каналы", description: "Исключить каналы из очистки", keywords: "keep channels cleanup"),
        ShadowSettingsSearchItem(destination: .spy, entryId: 22, title: "Не очищать ботов", description: "Исключить ботов из очистки", keywords: "keep bots cleanup"),
        ShadowSettingsSearchItem(destination: .spy, entryId: 23, title: "Хранилище Shadow", description: "Галерея, история и очистка", keywords: "storage archive gallery cache кэш"),
        ShadowSettingsSearchItem(destination: .ghost, entryId: 12, title: "Предлагать призрак перед историями", description: "Если призрак выключен, спросить перед чужой историей, включить ли его", keywords: "ghost stories история просмотр спросить предложить призрак"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 116, title: "Скрыть приветственный стикер", description: "В пустом чате с незнакомым — без карточки со стикером, чтобы не отправить случайно", keywords: "greeting sticker hello привет стикер пустой чат незнакомый"),
        ShadowSettingsSearchItem(destination: .ghost, entryId: 1, title: "Режим призрака", description: "Главный переключатель скрытия активности", keywords: "ghost mode приватность"),
        ShadowSettingsSearchItem(destination: .ghost, entryId: 2, title: "Не показывать онлайн", description: "Скрывать свой статус при включённом призраке", keywords: "hide online status"),
        ShadowSettingsSearchItem(destination: .ghost, entryId: 3, title: "Не показывать набор текста", description: "Не отправлять статус печати", keywords: "hide typing"),
        ShadowSettingsSearchItem(destination: .ghost, entryId: 4, title: "Не отправлять прочтения", description: "Скрывать галочки прочитанных сообщений", keywords: "hide read receipts"),
        ShadowSettingsSearchItem(destination: .ghost, entryId: 5, title: "Скрывать просмотры историй", description: "Не отмечаться среди зрителей", keywords: "hide story views"),
        ShadowSettingsSearchItem(destination: .ghost, entryId: 8, title: "Отправлять через отложенные сообщения", description: "Отправка с задержкой в режиме призрака", keywords: "scheduled delayed send"),
        ShadowSettingsSearchItem(destination: .ghost, entryId: 9, title: "Отправлять без появления онлайн", description: "Повторно устанавливать статус офлайн", keywords: "send without online offline"),
        ShadowSettingsSearchItem(destination: .filters, entryId: 40001, title: "Реклама в каналах", description: "Скрывать рекламные посты каналов по маркировке: erid, «Реклама. ООО», ИНН, #реклама", keywords: "реклама ads ad erid инн маркировка спонсор партнёрский пост банк скрыть рекламу каналы"),
        ShadowSettingsSearchItem(destination: .filters, entryId: 40002, title: "Реклама в группах", description: "Скрывать сообщения с рекламной маркировкой в группах", keywords: "реклама группы чаты erid ads"),
        ShadowSettingsSearchItem(destination: .filters, entryId: 40003, title: "Реклама в пересланных", description: "Скрывать пересланные рекламные посты в личных чатах и группах", keywords: "реклама пересланные переслали forward erid ads"),
        ShadowSettingsSearchItem(destination: .filters, entryId: 40004, title: "Скрывать рекламу полностью", description: "Без строки «Скрыта реклама» на месте поста", keywords: "реклама полностью плашка строка скрыта реклама"),
        ShadowSettingsSearchItem(destination: .filters, entryId: 0, title: "Фильтры сообщений", description: "Скрывать сообщения по словам и регулярным выражениям, с плашкой или полностью", keywords: "local filter phrase regex регулярка регулярное выражение скрыть слово фильтр плашка обратный"),
        ShadowSettingsSearchItem(destination: .misc, entryId: 1, title: "Подменить ID", description: "Визуальная подмена ID в профиле", keywords: "spoof profile id"),
        ShadowSettingsSearchItem(destination: .misc, entryId: 3, title: "Подменить DC", description: "Визуальная подмена дата-центра", keywords: "spoof dc data center"),
        ShadowSettingsSearchItem(destination: .misc, entryId: 5, title: "Подменить номер", description: "Визуальная подмена телефона", keywords: "spoof phone number"),
        ShadowSettingsSearchItem(destination: .feed, entryId: 1, title: "Лента (бета)", description: "Вкладка с постами всех каналов одной лентой, новые сверху, без рекламы", keywords: "лента feed посты каналы твиттер вкладка бета новости"),
        ShadowSettingsSearchItem(destination: .feed, entryId: 3, title: "Где кнопка ленты", description: "Левее контактов, между чатами и профилем или правее профиля", keywords: "лента кнопка вкладка положение место"),
        ShadowSettingsSearchItem(destination: .feed, entryId: 7, title: "Автозапуск видео в ленте", description: "Видео без звука запускается, когда секунду стоит в середине экрана", keywords: "лента видео автозапуск autoplay"),
        ShadowSettingsSearchItem(destination: .feed, entryId: 8, title: "Папки Telegram в ленте", description: "Ваши папки как вкладки над лентой", keywords: "лента папки вкладки чипы folders"),
        ShadowSettingsSearchItem(destination: .feed, entryId: 9, title: "Каналы без звука в ленте", description: "Посты каналов с выключенными уведомлениями", keywords: "лента без звука muted каналы"),
        ShadowSettingsSearchItem(destination: .feed, entryId: 10, title: "Каналы из архива в ленте", description: "Посты архивированных каналов", keywords: "лента архив archive каналы"),
        ShadowSettingsSearchItem(destination: .feed, entryId: 11, title: "Лента отмечает прочитанным", description: "Пролистали пост в ленте — в канале он прочитан", keywords: "лента прочитано read отметка"),
        ShadowSettingsSearchItem(destination: .chatStats, entryId: 2, title: "Итоги: считать удалённые", description: "Учитывать в итогах чатов сообщения, сохранённые анти-удалением", keywords: "итоги удалённые удаленки deleted статистика"),
        ShadowSettingsSearchItem(destination: .chatStats, entryId: 0, title: "Итоги чатов", description: "Статистика переписки за неделю, месяц, год или 5 лет: кто больше пишет, голосовые, эмодзи, стикеры, часы, сравнение и картинка", keywords: "итоги статистика stats wrapped переписка сравнение чат кто больше пишет сообщения голосовые"),
        ShadowSettingsSearchItem(destination: .autoUpdate, entryId: 0, title: "Сертификат для автообновления", description: "Выбрать .p12, .mobileprovision и пароль, чтобы Shadow сам подписывал и ставил обновления", keywords: "автообновление обновление подпись сертификат p12 mobileprovision профиль esign update sign install"),
        ShadowSettingsSearchItem(destination: .backup, entryId: 0, title: "Экспортировать настройки", description: "Перенести настройки без сессий и личных данных", keywords: "export backup json"),
        ShadowSettingsSearchItem(destination: .backup, entryId: 1, title: "Импортировать настройки", description: "Применить файл к текущему аккаунту", keywords: "import settings json"),
        ShadowSettingsSearchItem(destination: .backup, entryId: 2, title: "Отменить последний импорт", description: "Вернуть настройки перед импортом", keywords: "undo restore backup"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 99, title: "Скрыть истории", description: "Убрать ленту историй над списком чатов", keywords: "stories истории сторис лента hide"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 100, title: "Скрыть кнопку подарка", description: "Убрать кнопку подарка из поля ввода", keywords: "gift подарок кнопка ввод"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 101, title: "Скрыть значки Premium у имён", description: "Звёздочка и эмодзи-статус рядом с именем", keywords: "premium премиум звезда статус emoji status badge"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 102, title: "Скрыть рекламу в каналах", description: "Не загружать спонсорские сообщения", keywords: "ads реклама sponsored спонсор"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 104, title: "Безлимитные закрепы", description: "Без лимита в списке, архиве, папках, Избранном и темах (сверх лимита — только на этом устройстве)", keywords: "pin закреп закрепить лимит unlimited безлимит папки folders темы topics избранное"),
        ShadowSettingsSearchItem(destination: .spy, entryId: 29, title: "Сохранять просмотренные истории", description: "Истории остаются у вас, даже если автор удалил", keywords: "stories истории сохранять архив удалённые истёкшие"),
        ShadowSettingsSearchItem(destination: .spy, entryId: 26, title: "История «в сети»", description: "Когда контакты заходили в Telegram — за 30 дней, в профиле", keywords: "online онлайн в сети история заходы активность статус last seen"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 110, title: "Компактный список чатов", description: "Меньше аватарки, одна строка превью — больше чатов на экране", keywords: "compact компактный список чатов плотный маленькие аватарки строки"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 122, title: "Фоны чатов", description: "Своё фото под строкой выбранных чатов в списке: затемнение, положение, цвет текста подстраивается", keywords: "фон баннер картинка фото обложка строка чата background banner wallpaper cover"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 123, title: "Фото и чаты", description: "Загрузить или удалить фото, выбрать чаты, затемнение и положение", keywords: "фоны чатов фото загрузить удалить привязать чаты", parentEntryId: 122),
        ShadowSettingsSearchItem(destination: .customization, entryId: 106, title: "Одноцветные иконки", description: "Один цвет фона и значка для всех иконок настроек", keywords: "icons иконки цвет color tint тонированные монохром черный серый фон значок тема"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 103, title: "Расшифровка голосовых на устройстве", description: "Распознавание речи без Premium, аудио не уходит с телефона", keywords: "voice голосовые transcription расшифровка текст speech"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 112, title: "Время на голосовых", description: "Сколько осталось, сколько прошло, «прошло / всего» или процент под голосовым", keywords: "voice голосовые время таймкод timecode duration длительность процент percent"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 113, title: "Время на голосовых: также на кружках", description: "Тот же формат времени на видеосообщениях", keywords: "кружки round video видеосообщения время таймкод"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 114, title: "Время в верхнем плеере", description: "Таймкод голосового в полоске плеера над чатом", keywords: "плеер player верхний таймкод время голосовые"),
        ShadowSettingsSearchItem(destination: .customization, entryId: 117, title: "Тайм-код в ответах", description: "Ответ на голосовое или кружок начинается с момента, где вы остановились: «0:53 текст». Собеседник нажимает на 0:53 и слушает с этого места", keywords: "таймкод тайм-код timecode ответ reply голосовое кружок время позиция", parentEntryId: nil),
        ShadowSettingsSearchItem(destination: .customization, entryId: 118, title: "Тайм-код в ответах: режим", description: "Всегда или спрашивать при отправке; ответ можно запомнить для чата на 30 минут", keywords: "таймкод тайм-код спрашивать всегда запомнить", parentEntryId: 117),
        ShadowSettingsSearchItem(destination: .customization, entryId: 119, title: "Своя скорость для чатов", description: "Кнопка скорости в полоске плеера меняет скорость голосовых только этого чата: везде 1.2x, у друга 1.5x", keywords: "скорость голосовых чат speed rate 1.5x 2x ускорение", parentEntryId: nil),
        ShadowSettingsSearchItem(destination: .customization, entryId: 120, title: "Чаты со своей скоростью", description: "Список чатов с личной скоростью голосовых, сброс по одному или всех", keywords: "скорость голосовых сбросить список", parentEntryId: 119),
        ShadowSettingsSearchItem(destination: .quickReplies, entryId: 0, title: "Шаблоны ответов", description: "Свои заготовки текста, вставляются кнопкой в поле ввода", keywords: "templates шаблоны quick replies быстрые ответы заготовки"),
        ShadowSettingsSearchItem(destination: .chatLocks, entryId: 0, title: "Замки чатов", description: "Face ID и пароль на отдельные чаты, спойлер последнего сообщения, сброс замков", keywords: "lock замок пароль face id touch id скрыть чат блокировка спойлер превью последнее сообщение"),
        ShadowSettingsSearchItem(destination: .secondSpace, entryId: 0, title: "Второе пространство", description: "Второй код-пароль открывает скрытые чаты", keywords: "space пространство второй код скрытые чаты спрятать двойной пароль"),
        ShadowSettingsSearchItem(destination: .emergency, entryId: 0, title: "Код под принуждением", description: "Третий код открывает чистое пространство и может выйти из аккаунтов", keywords: "duress принуждение тревога экстренный третий код чистый выход аккаунт паника"),
        ShadowSettingsSearchItem(destination: .emergency, entryId: 1, title: "Тревожный жест", description: "Перевернуть телефон, встряхнуть или тройной тап двумя пальцами", keywords: "panic паника тревога жест перевернуть встряхнуть shake тап tap маскировка full скрыть второе")
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

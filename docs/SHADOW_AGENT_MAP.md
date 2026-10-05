# Shadow: карта проекта для агентов

Shadow — форк Telegram-iOS (раньше назывался AyuGram / Ghostgram). Корневой
`CLAUDE.md` в основном описывает **апстримный** Telegram: Bazel, симуляторы,
Postbox-рефакторинг. Этот файл описывает то, что добавил форк, и то, что
неочевидно при первом заходе в репозиторий.

## 1. Ветки и git

- **Единственная рабочая ветка — `master`** (default branch на GitHub).
  Коммитить и пушить в неё. `main` и прочие `codex/*`, `fix/*`, `ci/*` —
  исторические: на 2026-10-01 всё их полезное содержимое влито в `master`.
- Репозиторий форка — `github.com/folzy1092/Shadow`. В облачных клонах это
  `origin`; в локальном чекауте на Windows
  (`Desktop\projects\iphone app\iphone app\Telegram-iOS`) он называется
  `ghostgram`, а `origin` там указывает на апстрим TelegramMessenger. Пушить
  в `ghostgram master`. Апстрим Telegram отдельным remote не подключён; обновление на новый релиз — `tools/shadow-update.sh`
  (инструкция в `ОБНОВЛЕНИЕ.md`).
- Облачные сессии клонируют репозиторий **неглубоко** (shallow). `git
  merge-base` между ветками может молча ничего не вернуть — сначала
  `git fetch --deepen=400 origin <ветки>`.
- Прежде чем анализировать или чинить, сверьтесь с `git log origin/master`:
  локальный чекаут может отставать, и найденный «баг» окажется уже исправлен.

## 2. Сборка и тесты

- Собрать приложение можно только на macOS + Xcode (Bazel). Под Linux и
  Windows нет ни Xcode, ни `swiftc`: там доступны лишь Python-тесты
  контрактов. На Windows запускать с `PYTHONUTF8=1` (иначе кириллица в
  исходниках читается в cp1251 и тесты падают ложно).
- CI: `.github/workflows/build.yml` — на push в `master` собирает IPA
  (~25–55 мин), перед сборкой гоняет тесты. **Push, где изменены только
  `*.md`, сборку и диагностику не запускает** (`paths-ignore`). Чтобы не
  запускать сборку для другого служебного коммита, добавьте `[skip ci]` в
  сообщение. Новый push в `master` отменяет идущую сборку
  (`cancel-in-progress`).
  - Обе папки контрактов, обе гоняет CI:
    `python3 -B -m unittest discover -s Tests/ShadowSettings -p 'test_*.py'` и
    `python3 -B -m unittest discover -s Tests/ShadowVisualSettings -p 'test_*.py'`
    — **контрактные тесты**: читают исходники как текст и проверяют
    наличие/отсутствие строк. При изменении поведения обновляйте их
    вместе с кодом.
  - `python3 build-system/ci/test_shadow_foundation.py` — компилирует
    отдельные Foundation-only файлы форка с тестами из `Tests/ShadowSettings/*.swift`
    (`-warnings-as-errors`). Нужен `swiftc`.
  - `python3 build-system/ci/test_shadow_postbox.py` — кодеки Postbox.
  - `python3 -m unittest discover -s Tests/ShadowCI` — скрипты CI.
- `.github/workflows/shadow-diagnostics.yml` — быстрый прогон тестов
  (без сборки IPA) на PR и push в `master`.
- Успешная сборка `master` публикуется как GitHub Release `build-<номер>` с
  файлом `Shadow.ipa` (прямая ссылка `releases/download/build-N/Shadow.ipa`,
  всегда свежая — `releases/latest/download/Shadow.ipa`; её же присылает бот).
  **Что объявлять пользователям, решает файл `shadow-update.json`**
  (`enabled`, `build`, `version`, `title`, `notes`, `url`, `minimum_build`);
  приложение читает его с raw.githubusercontent.com (запрос с меткой времени
  обходит кэш CDN), а к релизам GitHub обращается, только если файл недоступен.
- **Данные для приложения лежат в публичном репо `folzy1092/tgfork`**
  (ветка `main`, рядом с `config.json` бейджиков): `shadow-update.json`,
  `shadow-changelog.json`, `shadow-whitelist.json`. Так проверки работают, даже
  если репо Shadow станет закрытым. Сборки с 34730 читают только tgfork;
  копии в корне Shadow оставлены для сборок до 34729 включительно — пока ими
  пользуются, объявление обновления правьте в **обоих** местах.
- **`shadow-changelog.json`** — изменения по сборкам на русском (новые сверху).
  При каждом выпуске добавляйте запись для объявляемой сборки: плашка
  обновления показывает все записи новее установленной сборки. Номер сборки =
  `git rev-list --count HEAD` + `build_number_offset`. Считаются **все**
  коммиты, включая те, что сборку не запускали (только `.md`, `[skip ci]`,
  упавшие и отменённые сборки). Поэтому объявляемый номер = число коммитов
  после вашего коммита + смещение; сверяйте с `releases`. Если сборка упала,
  исправляющий коммит получает следующий номер — переобъявите его в
  `shadow-update.json` и `shadow-changelog.json`.
- Перед пушем гоняйте обе папки контрактов, `Tests/ShadowCI` и (если есть
  `swiftc`) `test_shadow_foundation.py`. Шаг «Parse changed Swift sources» в
  диагностике ловит только синтаксис; ошибки типов видны лишь в полной сборке.
- Секреты `TELEGRAM_API_ID`/`TELEGRAM_API_HASH` подставляются в
  `build-system/shadow-configuration.json` только в CI. В файлы их не писать.

## 3. Где код форка

| Что | Где |
|---|---|
| Ядро фич (без UI) | `submodules/TelegramCore/Sources/AyuGram/` |
| Экраны настроек Shadow | `submodules/SettingsUI/Sources/Ayu*.swift`, `Shadow*.swift` |
| Правки в файлах апстрима | помечены комментариями `Shadow:` / `AyuGram:` (помечено не всё — надёжнее `git diff release-<версия> HEAD -- <файл>`) |
| Список изменённых файлов | `FORK_CHANGES.md` (генерируется `tools/shadow-update.sh --inventory`) |
| Иконки/ассеты форка | `Images.xcassets/.../AyuGram`, `ShadowAppIcon.xcassets` |

Запуск фоновых задач на аккаунт: `TelegramCore/Sources/Account/Account.swift`
(`keepAyuGramSettingsUpdated`, `managedAyuMediaAutoClean`, `startGitConfigIfNeeded`).
UI-проекция настроек выбирается в `TelegramRootController` (`activateAyuGramSettings`).

## 4. Настройки (`AyuGramSettings.swift`) — главные правила

- Хранятся **на аккаунт** в Postbox (`PreferencesKeys.ayuGramSettings`, raw 1000).
- Способы чтения:
  - `currentAyuGramSettings(transaction:)` — в ядре, внутри транзакции.
    **Предпочтительно.**
  - `currentAyuGramSettings(accountId:)` / `(mediaBox:)` — синхронный снимок
    конкретного аккаунта.
  - `ayuGramSettingsCurrent` — **только UI видимого аккаунта**. В ядре и
    фоновых путях не использовать: при нескольких аккаунтах это настройки
    чужого аккаунта (такие баги уже были с отложенной отправкой и presence).
- **Чек-лист нового поля настроек** (пропуск шага = баг; так сломался экспорт
  из-за `ghostAccountMode`):
  1. поле + `defaultSettings` + `init` + `init(from:)` + `encode(to:)` в `AyuGramSettings.swift`;
  2. если поле переносимое — `ShadowSettingsDocument.swift`: множество
     ключей **и** ветка в `validate()` для integer/text;
  3. `ShadowSettingsTransfer.swift`: key path (bool) или запись/чтение (int/text);
  4. UI в `AyuGramSettingsController.swift` и поиск в `ShadowSettingsSearchIndex.swift`;
  5. тест в `Tests/ShadowSettings/DocumentTests.swift` (round-trip).
- Ghost Mode: мастер-флаг `ghostMode`; конкретные фичи читаются через
  `effective*` / `suppressReadReceipts(peerId:)` (учитывают персональные
  правила чатов).

## 5. Где Ghost Mode гасит сетевые сигналы

Если добавляется новый путь, который что-то сообщает серверу, проверьте его здесь:

- онлайн: `State/ManagedAccountPresence.swift`, `TelegramUI/Sources/SharedWakeupManager.swift`;
- прочтения: `State/SynchronizePeerReadState.swift` (включая секретные чаты),
  `TelegramEngine/Messages/ApplyMaxReadIndexInteractively.swift` (форумы),
  `ReplyThreadHistory.swift` (треды/комментарии);
  `readMessageHistoryExplicitly` — намеренное «прочитать» по запросу пользователя;
- набор текста: `State/ManagedLocalInputActivities.swift`;
- голосовые/упоминания/реакции: `ManagedSynchronizeConsumeMessageContentsOperations.swift`,
  `ManagedSynchronizeMarkAllUnseenPersonalMessagesOperations.swift`,
  `MarkMessageContentAsConsumedInteractively.swift`;
- просмотры постов и историй: `AccountViewTracker.swift`, `Stories.swift`;
- отправка без онлайна: `AyuDelayedSend.swift` (через schedule_date) + `EnqueueMessage.swift`;
- уведомления о скриншотах **не отправляются никогда** (`ShadowScreenshotNotices.swift`).

## 5b. Вайтлист устройств и фильтры сообщений

- Вайтлист: `ShadowDeviceAccess.swift` (ID устройства в Keychain,
  `AfterFirstUnlockThisDeviceOnly`, без Face ID) + `TelegramUI/Sources/ShadowDeviceAccessUI.swift`
  (отдельное окно-заглушка поверх всего, ставится в `AppDelegate`).
  Список читается **реальным запросом при каждом заходе**: сначала воркер
  `GET /whitelist` (через GitHub API, `no-store`), запасной путь — raw
  `folzy1092/tgfork/main/shadow-whitelist.json`; на диск (офлайн-кэш) пишется
  только успешный ответ. Отказ из старого кэша не показывается до свежего
  ответа, «Проверка доступа…» — только если ответ дольше 1,5 с, а пока экран
  «Доступ ограничен» открыт, он сам перепроверяет доступ каждые 10 с.
  `"enabled": false` в файле — пускать всех. Залогиненный аккаунт из
  `ShadowDeviceAccess.adminPeerIds` (Folzy 7878830498, matey 1068369028) или
  устройство с флагом `admin` проходит всегда и видит «Доступ устройств».
  Правка списка: Shadow → «Доступ устройств» → «Сохранить» коммитит в
  `folzy1092/tgfork` через воркер (нужен «Ключ администратора» = `ADMIN_SECRET`
  воркера; без него — «Скопировать JSON» и ручной коммит). Кнопки «Принять» в
  боте нет (убрана).
- Запрос доступа: поле `request_url` в вайтлисте → на заглушке кнопка
  «Запросить доступ» → POST на Cloudflare Worker (`tools/shadow-bot`, инструкция
  в его README) → админам сообщение с кнопкой `tg://shadow/access?id=…`.
- IPA-релизы зеркалируются в `folzy1092/tgfork`, если в секретах Shadow есть
  `TGFORK_RELEASE_TOKEN` (fine-grained token, Contents: read/write только на tgfork).
- Фильтры: `ShadowMessageFilters.swift` (регулярка + флаги, matcher кэшируется
  в `AyuGramSettings`), поле `messageFilters` (ключ `messageFiltersV2`, старое
  `messageFilterPhrases` мигрирует), `messageFilterShowPlaceholder`. Скрытие —
  `ChatHistoryEntriesForView`. «В фильтры»: `TextSelectionNode.shadowAddToFilter`
  и меню @username (`ChatControllerOpenUsernameContextMenu`) через
  `ChatControllerInteraction.shadowAddMessageFilter`.

## 5c. Быстрые ссылки и архив

- `shadow://<команда>` = `tg://shadow/<команда>`. Разбор и поиск в тексте —
  `ShadowLinks.swift` (Foundation, тест `LinksTests.swift`), подсветка в
  сообщениях — `ShadowLinksEntities.swift` + `ChatMessageTextBubbleContentNode`,
  вход — `OpenUrl.swift` (до разбора tg://) и `ChatController.openUrl`,
  маршруты — `SettingsUI/Sources/ShadowLinkRouter.swift`. Список команд —
  `docs/shadow-links.md` (контракт-тест сверяет его с маршрутизатором).
- Второе пространство и истории: `shadowFilteredStorySubscriptions`
  (`ChatListController.swift`) убирает истории тех, чьи чаты скрыты в текущем
  пространстве, и перефильтровывает ленту по `ShadowSpaceStore.didChangeNotification`.
- Архив: `ayuArchiveChatController` — только удалённые (с возвратом медиа из
  папки форка, `AyuSavedMedia.restoreMessageMedia`), `ayuEditedArchiveChatController` —
  отредактированные.

## 5d. Версии, ветки обновлений, автокоммит вайтлиста

- Версия форка — `ShadowVersion.fork` (Swift) и `versions.json` ключ `fork`
  (CI, контракт-тест сверяет). Полная версия `ShadowVersion.full` = `12.9.2-1.1.0`.
- **Версию форка поднимать в коммите с изменениями**, оба места сразу
  (`ShadowVersion.fork` и `versions.json` → `fork`): новые фичи — minor
  (1.1.0 → 1.2.0), исправление крупных багов — patch (1.1.0 → 1.1.1).
  Мелкие правки, служебные коммиты и объявления версию не меняют.
  В `shadow-update.json` поле `version` = новая полная версия.
  CI пишет её в заголовок релиза `Shadow <app>-<fork> (<build>)`.
- `shadow-update.json` поддерживает ветки `stable`/`beta` (плоские поля вверху =
  stable, для старых сборок). `ShadowUpdateCheck.parseManifest`/`parseBetaManifest`;
  тумблер `AyuGramSettings.updateChannelBeta` («Разное» → «Бета-версии»);
  `check(betaEnabled:)` выбирает бету, если она новее.
- Автокоммит: `ShadowDeviceAccess.saveWhitelist`/`announce` шлют POST на
  `admin_url` воркера (`tools/shadow-bot`, эндпоинт `/admin`), тот коммитит в
  tgfork токеном `GITHUB_TOKEN`, авторизация — `ADMIN_SECRET` (в Keychain
  приложения, вводится в «Доступ устройств»). Админ по устройству — флаг
  `admin` в вайтлисте (`ShadowDeviceAccess.isAdminDevice`/`hasAdminAccess`).
  Объявление сборок — из того же меню (секция «Объявить сборку»).

## 5e. Кнопки шапки, кружок из галереи, синхронизация аккаунтов

- Кнопки шапки списка чатов: модель `ShadowHeaderButtons.swift` (Foundation,
  тест `HeaderButtonsTests.swift`), поле `AyuGramSettings.headerButtons`
  (ключ `headerButtonsV1`, действия хранятся строками — не enum). Отрисовка и
  действия — конец `ChatListController.swift` (`applyShadowHeaderButtons`,
  `shadowPerformHeaderAction`); стандартная раскладка и маскировка Full идут
  старым кодом. Левых кнопок может быть две: `ChatListHeaderComponent.Content.extraLeftButtons`.
  Экран — `SettingsUI/ShadowHeaderButtonsController.swift`, ссылка `shadow://header`.
  Новое действие = case в `ShadowHeaderAction` + иконка + ветка в `shadowPerformHeaderAction`
  (контракт-тест проверяет все три).
- Кружок из галереи: флаг — пресет `VideoMessage` в `TGVideoEditAdjustments`
  (`isRoundVideo`), кнопка справа от кнопки звука (`TGMediaPickerGalleryInterfaceView`),
  превью — квадрат по центру + круглая маска (`TGMediaPickerGalleryVideoItemView`).
  Квадрат и лимит 60 с применяет `roundVideoAdjustmentsWithDuration:` перед
  отправкой (`LegacyMediaPickers.swift`: флаг `.instantRoundVideo`, без подписи и альбома).
- Синхронизация настроек между аккаунтами: список — `ShadowSettingsSync.swift`
  (UserDefaults, id пользователей), раздача изменений — `TelegramUI/ShadowSettingsSyncManager.swift`
  (ставится в `SharedAccountContextImpl`), экран — `shadowSettingsSyncController`
  в `AyuGramSettingsController.swift`, ссылка `shadow://sync`. Читает только
  сохранённые значения (`shadowStoredAyuGramSettings`), не маску маскировки.
  Не синхронизируется только `ghostLastSeenTimestamp`.

## 5a. Замки чатов и второе пространство

- Замки: `ShadowChatLock.swift` (хранилище), `TelegramUI/Sources/ShadowChatLockUI.swift`
  (Face ID/пароль, шторка). Пока чат заблокирован, лента скрыта целиком
  (`ChatControllerNode.shadowSetChatLockContentHidden`), а не только закрыта.
- Второе пространство: `ShadowSpaces.swift` (видимость чатов, второй код,
  активное пространство только в памяти) + `ShadowSpacesSync.swift` (заглушка
  уведомлений). Код проверяется в `PasscodeEntryController` (экран блокировки),
  фильтры — `chatListNodeEntriesForView`, поиск, частые собеседники.
  Новое место, где показывается список чатов, должно проверять
  `ShadowSpaceStore.shared.isHidden(accountPeerId:peerId:)`.
- Закрытый (под замком или скрытый в текущем пространстве) чат не должен
  открываться и читаться в обход. Точки проверки (список — в
  `docs/specs/2026-10-01-shadow-batch.md`, раздел 8):
  `navigateToChatController` (`SharedAccountContext`), шторка
  `shadowChatLockUpdate` (`ShadowChatLockUI`), вкладки профиля
  (`shadowFilterLockedPanes`, `PeerInfoData`), поиск
  (`ChatListSearchListPaneNode`), баннеры (`ApplicationContext`), превью
  push (`ShadowChatLockPreviews`), строка списка чатов
  (`shadowChatListItemIsLocked`), архив удалённых
  (`AyuArchiveChatContents`). Новый экран, показывающий содержимое чата,
  должен проверять то же самое. «Избранное» (id аккаунта) тоже может быть
  под замком.
- Фото при неверном пароле: `ShadowIntruderLog` (очередь, `isCapturing`),
  `PasscodeUI/ShadowIntruderCamera` (снимок + галерея),
  `TelegramUI/ShadowIntruderDelivery` (отправка в «Избранное»).
- Экстренная защита (`SettingsUI/ShadowEmergencyController`):
  `ShadowDuress.swift` — код под принуждением (проверка в
  `PasscodeEntryController`) и настройки тревожного жеста. Сессия duress
  (`ShadowSpaceStore.setDuressActive`, только в памяти) прячет закрытые
  чаты и чаты второго пространства, а также настройки (`hidesSettings`).
  Заканчивается при вводе настоящего кода. Жесты и выход из аккаунтов:
  `TelegramUI/ShadowDuressUI.swift`, ставится в `SharedAccountContextImpl`.
- Экспорт чата: форматирование в `ShadowChatExport.swift` (Foundation,
  тестируется), сбор из Postbox в `ShadowChatExportCollect.swift`, UI в
  `SettingsUI/ShadowChatExportUI.swift`. Пункт меню профиля
  (`PeerInfoScreenPerformButtonAction`) скрыт для закрытых и скрытых чатов.

## 6. Анти-удаление и архив

- Удалённые сервером чужие сообщения не удаляются, а помечаются
  `DeletedMessageAttribute` (`AyuGramAntiDelete.swift`). Хуки:
  `AccountStateManagementUtils.swift` (`DeleteMessages*`,
  `UpdateMinAvailableMessage`), `HistoryViewStateValidation.swift`,
  `ProcessSecretChatIncomingDecryptedOperations.swift`.
- Свои исходящие и сообщения ботов не сохраняются.
- `UpdateMinAvailableMessage` приходит и при «очистить историю для себя»: на
  нём **нельзя** помечать весь диапазон — только восстанавливать уже помеченные.
- Индекс сохранённого: `AyuForkStore.swift` (preferences raw 1001).
- Медиа хранятся hard-link'ами в `<account>/postbox/ayu-saved-media/`
  (`AyuSavedMedia.swift`, `ShadowSavedMediaFiles.swift`). Время сохранения
  берётся из метаданных, **не из mtime** (mtime у hard-link общий с кэшем).
- История правок: `AyuEditHistory.swift` + `SavedMessageEditsAttribute`.

## 7. Подводные камни

- Удалённый конфиг значков: `GitConfig.swift` (raw.githubusercontent.com/folzy1092/tgfork).
- `AyuGramClientProfile.spoofDesktopWindows = false` намеренно (см. комментарий в файле).
- Значки «изменено/удалено»: см. раздел AyuGram в корневом `CLAUDE.md`
  (PNG с запечённым серым, tint не работает).
- Устаревшие документы: `AYUGRAM_FORK.md`, `SESSION_CONTEXT.md` (ветка
  `ayugram`, пути Windows), `FORK_STATUS_2026-07-16.md` — читать как историю,
  не как текущее состояние.
- **Компилятор Swift не успевает вывести типы** («unable to type-check this
  expression in reasonable time») для длинных цепочек `combineLatest(...) |>
  map |> distinctUntilChanged(isEqual:) |> map`, особенно внутри больших
  `combineLatest` (сборка 34713 упала на этом). Разбивайте на промежуточные
  `let x: Signal<T, NoError> = …` с явными типами.
- Режим маскировки в debug-меню (`ShadowDisguise.swift`): в режиме Full
  чтения настроек возвращают `AyuGramSettings.vanillaSettings`, а записи
  идут в сохранённые значения (`storedAyuGramSettings`). Не записывайте
  значение, прочитанное через `currentAyuGramSettings`/`ayuGramSettingsCurrent`,
  в настройки другого аккаунта: в режиме Full это затрёт настоящие настройки.
- Ответы пользователю — на русском.

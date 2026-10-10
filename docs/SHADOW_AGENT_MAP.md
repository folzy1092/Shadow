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
  сообщение. С 2026-10-08 новый push **не** отменяет идущую сборку:
  группа concurrency своя у каждого коммита, сборки разных коммитов идут
  параллельно (дубли одного push по-прежнему гасят друг друга). Старая
  сборка, закончившая позже новой, не становится `releases/latest`
  (`build-system/ci/shadow_latest_flag.py` → `--latest=false`).
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
  5. тест в `Tests/ShadowSettings/DocumentTests.swift` (round-trip);
  6. **ссылка** в `ShadowSettingLinks.swift` у каждой новой настройки, без
     исключений: тумблер — `key` (`?on/?off/?switch`), выбор из вариантов —
     `key` + `choices` и путь в `ShadowSettingLinksApply.choiceFields`
     (`?value=N`), всё остальное (цвет, текст, экран, картинка) — `key: nil`
     (ссылка только открывает). `entryId` = stableId строки; строка таблицы
     в `docs/shadow-links.md`; `since: "<версия форка>"` — с ним старые версии
     говорят, с какой версии работает ссылка (§5i);
  7. **синхронизация аккаунтов**: всё в `AyuGramSettings` синхронизируется само
     (`ShadowSettingsSync.syncedValue`). Состояние аккаунта, а не настройку,
     явно исключить там (как `ghostLastSeenTimestamp`); настройку вне
     `AyuGramSettings` (файлы, UserDefaults) — довести до синхронизации отдельно,
     как баннеры (`ShadowSettingsSyncManager`).
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

**Призрак перед историями (1.5.2).** Предложение в `OpenStories.swift`
(`openPeerStoriesCustom`): кнопки столбиком — «Включить призрака» сверху,
«Смотреть так» снизу. «Включить призрака» включает призрак только пока
открыты истории: `ShadowStoryGhostSession` (модуль StoryContainerScreen)
пишет прежние `ghostMode`/`hideStoryViews`/`ghostAccountMode` в UserDefaults
(`shadow.storyGhostSession.v1`) до изменения, экран историй держит сессию
(`StoryContainerScreen.shadowGhostSession`) и возвращает значения в
`dismiss(completion:)` и `deinit` (PiP не закрывает экран — призрак
остаётся). Истории не открылись — сессия кончается сразу (`afterDisposed`).
Приложение убили с открытой историей — откат при следующем запуске
(`recoverAfterLaunch` в `SharedAccountContextImpl`). Возвращаются только поля,
которые всё ещё в значении сессии: ручное изменение за время просмотра
сохраняется.

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

- Реклама (1.6.0): `ShadowAdFilter.swift` — маркеры (регулярки без учёта
  регистра: erid, «Реклама. ООО …», ИНН, #реклама, «на правах рекламы»…),
  `builtIn` + файл `shadow-ad-markers.json` в `folzy1092/tgfork` (main;
  `"patterns": ["…"]` или `[{"regex": "…", "note": "…"}]`, пустой или битый
  файл игнорируется). `ShadowAdMarkersStore` грузит его как значки: кэш с
  диска, затем сеть (`Account.swift`). Реферальные ссылки и подписи «По
  вопросам рекламы» маркерами **не** считаются (решение Folzy). Тумблеры
  `adFilterChannels` (вкл), `adFilterGroups`, `adFilterForwarded`,
  `adHideCompletely` (вкл: поста нет; выкл: строка «Скрыта реклама»), раздел
  «РЕКЛАМА» сверху экрана «Фильтры». Свои исходящие не прячутся. Ищется в
  тексте, скрытых ссылках, URL-кнопках и URL превью ссылки.
- Одна проверка «спрятано ли сообщение» для чата и списка чатов:
  `ShadowLocalHide.swift` (`shadowLocalHideReason` → теневой бан / фильтр /
  реклама). `ChatHistoryEntriesForView` делает плашку или убирает сообщение,
  `ChatListItem` при спрятанном последнем сообщении показывает пустое превью
  (без текста, автора, миниатюры и значка типа). Новое место, где видно
  содержимое сообщений (например, лента), должно звать эту же функцию.

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
  (CI, контракт-тест сверяет). Полная версия `ShadowVersion.full` = `12.9.2-1.3.1`.
- **Схема версии форка — Г.О.Ф** (правило Folzy, например `1.1.1`):
  **Г**лобальное (первая цифра) — глобальная переделка;
  **О**бновление (вторая) — базовое обновление, новые фичи (1.2.0 → 1.3.0);
  **Ф**икс (третья) — баг-фиксы и мелкие обновления (1.3.0 → 1.3.1).
  **Переделка или доработка уже существующей функции — это мелкий фикс
  (третья цифра), а не обновление** (правило Folzy, 2026-10-08): например,
  переделка «Призрака перед историями» — 1.5.2, а не 1.6.0. Средняя цифра —
  только для действительно новых функций. В заметках такая переделка идёт
  как «ИСПРАВЛЕНО».
  Поднимать в коммите с изменениями, оба места сразу (`ShadowVersion.fork` и
  `versions.json` → `fork`). Пока версия не объявлена, новые изменения входят
  в неё же. Служебные коммиты и объявления версию не меняют.
  В `shadow-update.json` поле `version` = новая полная версия.
- Объявление сборки: `python3 tools/shadow-announce.py --build N --version V
  --title T --notes notes.txt <tgfork> <shadow>` (по пункту на строку), затем
  коммит в tgfork и в Shadow с `[skip ci]`. Пишет и `shadow-update.json`, и
  запись `shadow-changelog.json` с `version` + `ipa_url` — из неё строится
  «Архив версий» (`ShadowVersionArchive` в `ShadowUpdateCheck.swift`,
  экран `ShadowVersionArchiveController.swift`, `shadow://versions`).
  Объявление из админки (воркер, action `announce`, «Объявить сборку» в
  «Доступ устройств») пишет то же самое: заметки разбирает `parseNotes` в
  `tools/shadow-bot/worker.js` по правилам `parse_notes` скрипта, запись
  той же сборки обновляется, а не дублируется (бета пишет только
  `shadow-update.json`). После правки `worker.js` воркер передеплоить.
  Архив показывает сборки начиная с 34725 (первая с вайтлистом устройств):
  откат ниже обошёл бы проверку устройства.
  CI пишет её в заголовок релиза `Shadow <app>-<fork> (<build>)`.
- **Когда объявлять** (решение Folzy, 2026-10-07): агент объявляет сам, не
  дожидаясь просьбы. Каждая сборка, где есть заметные пользователю изменения,
  получает список изменений и объявляется сразу, как только CI зелёный:
  1. дождаться `success` у CI (`gh run watch`), IPA есть в релизе
     `build-N` tgfork;
  2. поднять версию по Г.О.Ф, если она ещё не объявлена (новое — средняя
     цифра, только исправления — последняя);
  3. написать notes («НОВОЕ: … | раздел» / «ИСПРАВЛЕНО: …») и запустить
     `tools/shadow-announce.py` на клоне tgfork и на Shadow, закоммитить
     tgfork и Shadow (`[skip ci]`), запушить;
  4. сообщить Folzy, что объявлено.
  Новая функция или важный баг (вылет, потеря данных, не открывается экран,
  ломается установка) — объявлять немедленно, отдельной сборкой, не копить.
  Не объявляются только сборки без пользовательских изменений (CI, тесты,
  документация). Непроверенную на устройстве рискованную функцию отметить в
  отчёте Folzy.
- **Список изменений пишет агент** (решение Folzy, 2026-10-07): при каждом
  объявлении сборки агент сам составляет пункты из коммитов с прошлого
  объявленного выпуска. Правила:
  - каждый пункт — **НОВОЕ** (новая функция, тумблер, экран) или
    **ИСПРАВЛЕНО** (баг, вылет, поведение, которое было неправильным);
    служебное (CI, тесты, документация, рефакторинг) не пишется вовсе;
  - по-русски, для пользователя, одной фразой без внутренних имён
    (не `offerGhostBeforeStories`, а «Предлагать призрак перед историями»);
  - у НОВОГО — раздел, где искать: путь как в настройках
    («Призрак», «Чаты и звонки»); у исправлений раздела нет;
  - сначала новое, потом исправления; один пункт на изменение, без дублей
    между сборками (что вошло в объявленную сборку, в следующей не повторять).
  - Формат записи в `shadow-changelog.json` (поля добавляются к старым;
    `items` остаётся для сборок до экрана обновления — туда те же пункты
    строками, исправления с префиксом «Исправлено: »):
    ```json
    {"build": 34780, "date": "2026-10-08", "version": "12.9.2-1.5.0",
     "new": [{"text": "Предлагать призрак перед историями", "where": "Призрак"}],
     "fixed": ["Пасхалки показывают причину, если видео не открылось"],
     "items": ["Предлагать призрак перед историями", "Исправлено: пасхалки показывают причину, если видео не открылось"]}
    ```
  - Экран «Обновление» — `SettingsUI/ShadowUpdateController.swift`
    (строка «Обновление Shadow» вверху хаба, бейдж «1» при новой версии;
    `shadow://updates` открывает хаб и сразу экран): «1.4.0 → 1.5.0»,
    счётчики (`ShadowReleaseSummary`), кнопка («Обновить до X» с парой
    подписи, «Скачать IPA X» без неё), «Настройки обновлений» (сертификат,
    бета, архив версий), затем пункты по сборкам «НОВОЕ · …» /
    «ИСПРАВЛЕНО · …» (`ChangelogEntry.newItems`/`fixedItems`, старые записи —
    «• items»). `tools/shadow-announce.py` и действие воркера `announce`
    пишут `new`/`fixed` из строк «НОВОЕ: текст | раздел» /
    «ИСПРАВЛЕНО: текст» (строка без метки — новое). Совпадение разбора
    проверяет `test_worker_parses_notes_like_the_script` (нужен `node`).
  - Хаб (1.4.0): обновление, поиск, затем группы ПРИВАТНОСТЬ / ВНЕШНИЙ ВИД /
    ИНСТРУМЕНТЫ / АККАУНТЫ И ДАННЫЕ, у строк иконки SF Symbols
    (`ShadowSettingsIcons.swift`, учитывают «Одноцветные иконки»).
    «Кастомизация» разбита на части `ShadowCustomizationPart` (Сообщения,
    Чаты и звонки, Профили, Медиа и камера, Иконки) — это срезы одного экрана
    `ayuCustomizationController(part:)`, поэтому ссылки и поиск с фокусом сами
    выбирают нужную часть; `shadow://customization` открывает экран целиком.
    Новую секцию кастомизации добавлять в `ShadowCustomizationPart.sections`
    (тест `test_hub_redesign_contracts`). «Шпион» переименован в «Сохранение».
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
- Статус идущей сборки в «Проверить обновления» (видно всем, обновляется только
  по нажатию): `ShadowBuildStatus` читает публичный GitHub API — последний run
  `build.yml` на master → его текущий шаг → во время «Build the App» check run
  «Shadow build progress» (заголовок `Build the App [done / total]`, summary
  `build=N`). Check run создаёт и раз в 30 с обновляет
  `build-system/ci/build_progress.py` из `build.log` (Bazel пишет счётчик не реже
  раза в 15 с: `--show_progress_rate_limit` в `configure_bazel.py`); нужен
  `permissions: checks: write`. Ошибки репортера сборку не валят. Если
  переименовать шаг «Build the App» или check run — менять в обоих местах
  (тест `Tests/ShadowCI/test_build_progress.py`). Если сборка упала, первые
  ошибки компилятора лежат в `output.text` этого check run (лог прогона без
  токена не скачать, а check run читается публичным API):
  `curl https://api.github.com/repos/folzy1092/Shadow/commits/<sha>/check-runs?check_name=Shadow%20build%20progress`.
- Не писать голый `Timer` в файлах с `import SwiftSignalKit`: там свой `Timer`,
  тип неоднозначен — `Foundation.Timer` или `SwiftSignalKit.Timer` явно.

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
  (`isRoundVideo`), кнопка над кнопкой звука (`TGMediaPickerGalleryInterfaceView`; справа
  в ряду звука стоит счётчик выбранных «1», раньше он накрывал кнопку),
  превью — квадрат по центру + круглая маска (`TGMediaPickerGalleryVideoItemView`).
  Квадрат и лимит 60 с применяет `roundVideoAdjustmentsWithDuration:` перед
  отправкой (`LegacyMediaPickers.swift`: флаг `.instantRoundVideo`, без подписи и альбома).
- Синхронизация настроек между аккаунтами: список — `ShadowSettingsSync.swift`
  (UserDefaults, id пользователей), раздача изменений — `TelegramUI/ShadowSettingsSyncManager.swift`
  (ставится в `SharedAccountContextImpl`), экран — `shadowSettingsSyncController`
  в `AyuGramSettingsController.swift`, ссылка `shadow://sync`. Читает только
  сохранённые значения (`shadowStoredAyuGramSettings`), не маску маскировки.
  Не синхронизируется только `ghostLastSeenTimestamp`.

## 5f. Ссылки на тумблеры, шаги кнопок шапки, пасхалки

- Каждый тумблер настроек Shadow: `ShadowSettingLinks.swift` (Foundation, тест
  `SettingLinksTests.swift`) — экран, slug, stableId строки, ключ настройки.
  Чтение/запись по ключу — `ShadowSettingLinksApply.swift` (ключи экспорта +
  `linkOnlyBooleanFields`, которые не экспортируются). **Новый тумблер = строка
  в реестре** (контракт-тест сверяет stableId с экраном и ключ с настройками).
- Экран тумблера: `ShadowSettingLinkUI.swift` — открыть с фокусом (плавная
  прокрутка `ItemListController.shadowScrollToItem` + один импульс), подтверждение
  смены из ссылок, меню по зажатию (`shadowSettingsInstallLinkMenu`; экран пишет
  `linkRows.stableIds` в своём сигнале). Защитные (`isProtected`) только открываются.
- Кнопки шапки: у жеста список `ShadowHeaderStep` (до 5), действие `.setting` —
  тумблер по ссылке; тумблеры одной кнопки переключаются вместе
  (`ShadowSettingsTransfer.applying(links:)`). Кнопки шапки меняют без подтверждения.
- Пасхалки: `TelegramUI/ShadowEasterEggs.swift`, вход — `default` в
  `ShadowLinkRouter` через `SharedAccountContext.shadowOpenEasterEgg`. Каналы —
  `easter_egg_channels` в `shadow-whitelist.json` (по умолчанию kartinki5222,
  ayugram_easter), правятся в «Доступ устройств» через действие воркера
  `save_easter_eggs` (воркер передеплоить: `npx wrangler deploy`).
- Баннеры в синхронизации: `AyuSavedMedia.bannersDidChangeNotification` →
  `ShadowSettingsSyncManager` копирует файлы (`copyBanners`), флаг
  `ShadowSettingsSync.syncBanners`.
- Выбор из вариантов (`ShadowSettingLink.choices`, `isChoice`): `?value=N`
  ставит вариант N (`ShadowSettingsTransfer.setInt`, ключи `choiceFields`),
  `ShadowSettingLinks.mode(_:for:)` превращает бессмысленные сочетания
  (`?value` у тумблера, `?on` у выбора) в «только открыть». Есть у
  `voice-time` и `bottom-bar-hiding`; кнопки шапки умеют ставить вариант.
- Профиль на кнопке шапки: действие `.openProfile`, ссылка шага —
  `shadow://me` / `shadow://user?id=|username=` (`ShadowProfileTarget` в
  `ShadowLinks.swift`, `&name=` только для подписи в списке). Иконка — аватарка
  (`ChatListUI/ShadowHeaderAvatars.swift` → `NavigationButtonCustomImages`,
  иконка `img:<key>`; новая картинка = новый ключ). `.sendGift` открывает
  `shadow://gift` (`makePremiumGiftController(.settings(birthdays))`).
- Время на голосовых: `ShadowVoiceTime.swift` (Foundation, тест
  `VoiceTimeTests.swift`), поля `voiceTimeFormat` (0…5), `voiceTimeRoundVideos`,
  `voiceTimeInPlayer`. Пузырь — `ChatMessageInteractiveFileNode.updateStatus`
  (+ запас ширины под длинный формат в layout), кружки — `shadowFormatter` у
  `ChatInstantVideoMessageDurationNode` (ставит
  `ChatMessageInteractiveInstantVideoNode`), верхний плеер — подзаголовок в
  **обоих** `MediaNavigationAccessoryHeaderNode` (`TelegramBaseController` и
  `MediaPlaybackHeaderPanelComponent`). Пока не играет — просто длина.

## 5g. Автообновление с подписью на устройстве (1.4.0, установка 1.4.1), плитка камеры

- Идея из IPA Hub (Feather): «Обновить» в хабе скачивает объявленную сборку,
  подписывает её на iPhone парой .p12 + .mobileprovision и ставит через
  `itms-services`. Модуль `submodules/ShadowSelfUpdate`, экран —
  `SettingsUI/ShadowAutoUpdateController.swift` («Автообновление»,
  `shadow://autoupdate`), прогресс и кнопки — на экране «Обновление»
  (`ShadowUpdateController.swift`, `ShadowProgressItem`).
- Пара хранится **на устройстве**, не в `AyuGramSettings`: файлы в
  Application Support/ShadowSigning (без бэкапа), пароль в Keychain
  (`ThisDeviceOnly`). В экспорт настроек и синхронизацию аккаунтов не входит.
- Шаги (`ShadowSelfUpdater`): загрузка → распаковка (SSZipArchive) →
  `ShadowBundlePreparer` → подпись → упаковка → локальный сервер → установка.
  `ShadowBundlePreparer`: bundle ID = **установленной копии** (`Bundle.main`,
  у ESign это `ph.telegra.Telegra`), id расширений и BGTask по тому же
  префиксу; остаются только те `.appex` (и Watch), что есть у установленной
  копии; в каждое расширение кладётся тот же профиль.
- Подпись — `third-party/zsign` (MIT, Zsign-Package `c4ba9da`): Mach-O/bundle
  код как есть, а `openssl.cpp` заменён на `Sources/openssl_apple.mm`:
  p12 — `SecPKCS12Import`, подпись — `SecKeyCreateSignature`, CMS SignedData
  собирается вручную (формат сверен с `openssl cms -verify`). SHA — CommonCrypto
  через `Sources/shim/openssl/sha.h`. Свой OpenSSL Telegram не подходит
  (`no-cms`, `no-rc2`, `no-des`), второй дал бы конфликт символов. Ошибки zsign —
  `ZLog::LastError()` → текст в хабе.
- Установка (1.4.1, как IPA Hub / Feather «Semi Local + только localhost»):
  `ShadowInstallServer` отдаёт IPA по `http://127.0.0.1:PORT/shadow.ipa`
  (Network.framework, только loopback, Range и HEAD), без DNS и локального TLS.
  Манифест (itms-services требует https) — `https://api.palera.in/genPlist?
  bundleid=&name=&version=&fetchurl=` (`ShadowInstallLinks`), приложение
  заранее проверяет, что он отвечает plist с этим IPA. Ссылку iOS передаёт
  страница `http://127.0.0.1:PORT/install` в `SFSafariViewController`
  (JS-редирект на `itms-services://?action=download-manifest&url=…`).
  «Показать окно установки» без показанного окна переключает Safari ↔
  `UIApplication.open`, остановленный listener перезапускает. Зависимость:
  api.palera.in должен быть доступен с iPhone.
- Маршрут 1.4.0 (HTTPS на `shadow.backloop.dev` с сертификатом из
  `backloop.dev/pack.json`, `ShadowLocalTLSIdentity`) — только запасной:
  сертификат отозван 2026-07-31 (Key Compromise), сервис закрыт. Берётся, лишь
  если palera не ответил, а `SecTrustEvaluateWithError` сертификату доверяет.
- Диагностика (`ShadowInstallDiagnostics`): строка под статусом на
  «Обновлении» — маршрут, манифест palera, Safari/open, getaddrinfo
  `shadow.backloop.dev`, listener, подключения и ошибки TLS, запросы, срок
  сертификата. Если через 10 с (`hintDelay`) iOS не начала загрузку —
  конкретная причина (`cause(now:)`) и кнопки «Показать окно установки»,
  «Поделиться подписанным IPA», «Отменить» (`ShadowBigButtonItem`, стили
  filled / plain / destructive). Пока iOS не скачал IPA, Shadow держит экран
  и фоновую задачу (`beginBackgroundTask`; истёкшая заново начинается при
  возврате в приложение). «Окно показано» (`promptSeen`) считается только по
  уходу из приложения до подсказки; сбой palera важнее этого признака.
- Не проверено на устройстве: обновление приложения самим собой (Feather его
  запрещает для серверного способа), поведение iOS 27 с palera-манифестом.
- Компактная плитка камеры: `AyuGramSettings.cameraTileCompact` (ключ
  `cameraTileCompact`, ссылка `shadow://customization/camera-compact`, строка
  115 в «Кастомизации») — в `MediaPickerScreen` плитка камеры высотой в одну
  ячейку вместо двух. Живой предпросмотр — прежний `cameraTileLivePreview`.

## 5h. Дата регистрации в профиле (1.4.2)

- Логика — `TelegramCore/Sources/AyuGram/ShadowRegistrationDate.swift`
  (Foundation, тест `RegistrationDateTests.swift`), запрос к боту —
  `ShadowRegistrationDateFetch.swift`, строка в профиле —
  `shadowRegistrationDateText` в `PeerInfoProfileItems.swift`.
- Источники по приоритету: месяц от Telegram (`peerSettings.registration_month`,
  приходит для не-контактов; пишется хуками `shadowRecordOfficialRegistrationMonth`
  в `UpdateCachedPeerData.swift` ×2 и `AccountStateManagementUtils.swift`) →
  инлайн-запрос `regdate <id>` к @ayugrambot (как AyuGram Desktop; ответ JSON
  `flag` EXACT/INTERPOLATED/LT/ET + `date`) → локальная оценка по таблице
  опорных точек (кусочно-линейная, после последней точки — экстраполяция
  с ограничением «не позже сегодня»).
- Каждый месяц от Telegram сохраняется (`shadow-registration-dates.json`) и
  становится новой опорной точкой, таблица выпрямляется по возрастанию (PAV).
- Профиль обновляется по `ShadowRegistrationDateStore.didChangeNotification`
  (`shadowRegistrationDateChanges()` в `PeerInfoData.swift`, сигнал статуса
  намеренно без `distinctUntilChanged`).

## 5i. Тайм-код в ответах и ссылки из новых версий (1.4.4)

- Тайм-код: модель `ShadowReplyTimecode.swift` (Foundation, тест
  `ReplyTimecodeTests.swift`), поля `replyTimecode`, `replyTimecodeMode`
  (0 всегда, 1 спрашивать). Позиции голосовых и кружков пишет `MediaManager`
  (`shadowReplyTimecodeDisposable`: последняя позиция каждого сообщения, при
  переходе плеера к другому сообщению — `freeze`). Отправка —
  `ChatControllerNode.sendCurrentMessage` (параметр `shadowReplyTimecode`,
  проверка до `lastSendTimestamp`), кандидат и окно с галочкой «Запомнить для
  чата на 30 мин» — `TelegramUI/Sources/Chat/ShadowReplyTimecodeSend.swift`.
  Тайм-код — обычный текст «0:53 …»: кликабельным его делает сам Telegram
  (timecode-сущность по длительности медиа в ответе). Rich-сообщения,
  редактирование и подписи к медиа не трогаются. Память ответов — только в RAM.
- Ссылки на настройки из новых версий: у `ShadowSettingLink` поле `since`
  (версия появления, ставить у **каждой новой** настройки), `link(_:)` дописывает
  `?v=<since>`. `ShadowLinkRouter`: неизвестный slug на экране настроек и
  неизвестная команда (не пасхалка) → тост `ShadowSettingLinks.unsupportedText`
  («работает с Shadow N, у вас M») с кнопкой «Обновить». Раньше такие ссылки
  молча открывали экран.
- «Ответить с тайм-кодом» (1.5.0): пункт меню сообщения
  (`ChatInterfaceStateContextMenus.swift`, после «Ответить»), свой узел
  `TelegramUI/Sources/Chat/ShadowTimecodeReplyContextItem.swift` — вторая строка
  тикает таймером 0.5 с из `shadowReplyTimecodePosition`. Ставит ответ и
  `0:53 ` в начало поля ввода; работает и при выключенном «Тайм-код в ответах».
- Своя скорость голосовых (1.5.0): тумблер `chatVoiceSpeed`, хранилище
  `ShadowChatVoiceSpeed.swift` (UserDefaults, ключ «аккаунт/чат» → rate×1000,
  тест `ChatVoiceSpeedTests.swift`). `MediaManager` стартует плеер голосовых со
  скоростью чата (`initialVoicePlaybackRate`) и пишет `currentChat`; кнопка
  скорости `MediaPlaybackHeaderPanelComponent.setRate` при включённом тумблере
  пишет скорость чата и **не трогает** общую `voicePlaybackRate`. Другие
  полоски плеера (вложения, поиск, медиа профиля) меняют общую, как раньше.
  Экран списка — `SettingsUI/ShadowChatVoiceSpeedController.swift`.

## 5j. Итоги чатов (1.7.0)

- Движок (Foundation, тест `ChatStatsTests.swift`): `ShadowChatStats.swift` —
  `Item` (одно сообщение), `Builder` (счётчики, ответы, первый за день, серия
  «оба писали», перерывы, лента по дням/месяцам, тепловая карта), `Report`
  (Codable), `ShadowChatStatsStore` (Application Support/shadow-chat-stats/
  <аккаунт>/<чат>.json — **один отчёт на чат**, пересчёт заменяет).
  Время ответа — медиана, паузы > 6 ч не считаются; «первый за день» — день с
  4:00; серия — календарные дни, когда писали оба, сегодня не обрывает.
- Сбор (`ShadowChatStatsCollect.swift`): `loadHistory` дозагружает дыры
  периода через `fetchMessageHistoryHole` по 100 сообщений с паузой 0,35 с
  (как прокрутка вверх), сверху вниз, до сообщения старше начала периода.
  `report` читает период `scanTopMessages` (остановка по `false` починена в
  Postbox: `break scan`), картинки топ-стикеров и кастомных реакций кладёт в
  отчёт как data: URI (миниатюра, ≤ 300 КБ, иначе эмодзи стикера).
- Страница (`ShadowChatStatsPage.swift`): один HTML с данными внутри для
  экрана (WKWebView, mode app — кнопки шлют `shadow` message handler), файла
  (mode file, можно анонимно — `ShadowChatStats.anonymized`) и картинки (mode
  card, 360×640 → снимок 1080×1920). JS читает только поля `Report`/`Person`
  (контракт `test_chat_stats_contracts.py`).
- UI (`SettingsUI/ShadowChatStatsUI.swift`): строка «Итоги чатов» в хабе
  (инструменты), список (свайп — удалить), шторка периода, `ShadowChatStatsJobs`
  (подсчёт идёт и после закрытия экрана), экран отчёта. Вход из профиля:
  «…» → «Итоги чата» (личные чаты и группы, не каналы, не закрытые чаты).

- Итоги 1.11.0 (всё в отчёте, поля опциональные — старые отчёты открываются):
  `Period.previousStart/scanStart` — грузится и сканируется прошлый период
  такой же длины (кроме 5 лет) и всегда не меньше 14 дней; второй `Builder`
  на прошлый период → `Report.previous` (`ShadowChatStats.summary`).
  В `Builder`: `records` (самое длинное сообщение в символах, голосовое,
  кружок, звонок, самый жаркий час), `typicalDay` (медианы по дням от 4:00),
  у `Person` — `moods` (`ShadowChatStats.Mood`, эмодзи текста + реакции),
  `uniqueWords` (личные: от 2 раз, у другого ни разу), ожидания
  `waitLongCount/waitTotalSeconds/waitLongest/waitLongestAt/unanswered`
  (личные: паузы 1–24 ч, больше суток — «без ответа»), `replyPairs` (группы,
  по `Item.replyToAuthorId` из `ReplyMessageAttribute`), `moodTimeline`,
  `twoWeeks` (`ShadowChatStats.twoWeeks`). Страница: блоки на вкладках,
  «Смотреть историей» — слайды `slides()` (просмотр как истории, тап слева —
  назад), «Поделиться этим слайдом» → action `shareSlide` → картинка в режиме
  card с `Options.slide`. «Напоминать раз в месяц» —
  `SettingsUI/ShadowChatStatsReminder.swift`: UserDefaults устройства,
  локальное уведомление 1-го числа в 12:00 с `userInfo["url"] =
  "shadow://stats"` (AppDelegate открывает его по нажатию).

- «Общаемся N дней подряд» (1.8.0): `ShadowChatStreak.swift` — `Walker`
  (сообщения от новых к старым, день засчитан, если писали оба; сегодня не
  обрывает), `ShadowChatStreakStore` (UserDefaults, пересчёт раз в 30 мин или
  в новый день, уведомление `didChangeNotification` перестраивает профиль
  через `shadowRegistrationDateChanges` в `PeerInfoData`). Подсчёт —
  `ShadowChatStatsCollect.chatStreak`: если серия доходит до самого старого
  сохранённого сообщения, дозагружает историю (до 40 раз по 100). Строка в
  профиле (`PeerInfoProfileItems`, id 3512) с 2 дней, тумблер
  `showChatStreak` в «Кастомизация → Профили». Не для ботов, себя, закрытых
  и скрытых чатов.

## 5k. Лента (бета, 1.9.0)

- Вкладка `TelegramUI/ShadowFeedController.swift` (WKWebView). Страница —
  `ShadowFeedPage.html` (Foundation), пишется в
  `tmp/shadow-feed-<аккаунт>/index.html`, грузится `loadFileURL` с доступом к
  папке. Медиа качаются как в чате (`fetchedMediaResource`) и hard-link'ом
  (иначе копией) кладутся рядом с расширением (`.jpg/.mp4`), странице уходит
  `Feed.mediaReady(key, file)`. Видео больше 25 МБ — только постер.
- Посты — `ShadowFeedCollect.swift`: каналы из списка чатов (архив по
  тумблеру), по 40 последних постов не старше 21 дня, **без запросов истории**;
  альбом — один пост; реклама/фильтры (`shadowLocalHideReason`), закрытые и
  скрытые в пространстве каналы не попадают. Прочтение —
  `applyMaxReadIndexInteractively` (правила призрака действуют).
- Мост: страница шлёт `{action: …}` (`ready, chip, more, need, seen, open,
  comments, react, url, readAll, hideChannel, saveCollection,
  removeCollection, order, setting, copyLink`), контракт
  `test_feed_contracts.py` следит, что каждый action обработан.
- Подборки, порядок вкладок, убранные каналы, «вы остановились здесь» —
  `ShadowFeedStore` (UserDefaults на аккаунт). Настройки `feed*` в
  `AyuGramSettings`, экран `SettingsUI/ShadowFeedSettingsController.swift`
  (хаб → «Лента (бета)», ссылки `shadow://feed/...`).
- Место вкладки: `TelegramRootController` (`shadowInsertFeed`,
  `ShadowFeed.Position`): A левее контактов, B между чатами и профилем, C
  правее профиля. Вариант D (отдельный круг как поиск) требует правки
  `TabBarComponent` — не сделан.

## 5l. Фоны чатов (бета, 1.10.0)

- Своё фото под строкой выбранных чатов в списке (все папки и архив; не
  форумы и не «Сохранённые» чаты). Тумблер `chatBannersEnabled`
  («Кастомизация → Чаты и звонки → Фоны чатов», ссылка
  `shadow://customization/chat-banners`), экран «Фото и чаты» —
  `SettingsUI/ShadowChatBannersController.swift`: список фото, «Загрузить
  фото», редактор (превью строки «Folzy · Привет! Как тебе фон? 👀» с
  ползунками «Затемнение» и «Положение фото», фото двигается пальцем по
  превью; запись в хранилище — когда палец отпущен), выбор чатов
  (`makeContactMultiselectionController`, как папки), «Удалить фото».
- Модель (Foundation, тест `ChatBannersTests.swift`):
  `TelegramCore/AyuGram/ShadowChatBanners.swift` — у фото свои чаты,
  затемнение 0…0.9, положение 0…1, `mirrored` (1.10.1, отражение по
  горизонтали — `ShadowChatBannerImage.image(mirrored:)`); чат может быть только у одного фото
  (`setPeers` забирает его у других); видимая полоса
  (`visibleRect`, как aspect fill) и выбор цвета текста по яркости полосы
  после затемнения (`prefersLightText`, порог 0.58).
- Хранилище: `ShadowChatBannerStore.swift`, на аккаунт, только на
  устройстве: папка `shadow-chat-banners/` внутри `ayu-saved-media`
  (`index.json` + `<id>.jpg`, фото ужимается до 2000 px). Изменение →
  `ShadowChatBannerStore.didChangeNotification`. В синхронизацию аккаунтов и
  экспорт настроек входит только тумблер (фото привязаны к чатам аккаунта).
- Список чатов: `ChatListNode.mappedInsertEntries/mappedUpdateEntries`
  создают `ShadowChatBannerBatch` и строке с фото дают свой
  `ChatListPresentationData` (`shadowChatBanner` + тема с инвертированными
  цветами текста, если фото светлое/тёмное — `ShadowChatBannerThemes`, не
  больше двух производных тем на базовую). Смена фото/тумблера пересобирает
  строки (новый экземпляр presentation data, как у замков). Рисует
  `ChatListItemNode.shadowUpdateChatBanner`: фото над `backgroundNode`, под
  разделителем и подсветкой нажатия, едет вместе со свайпом; разделитель
  почти прозрачный. Картинки и профиль яркости кэширует
  `ShadowChatBannerImageCache` (ImageIO, до 1400 px).
- Не проверено на устройстве: кольца онлайна и звезды рисуются цветом фона
  темы поверх фото.
- 1.11.1 — «Все чаты», исключения, «Узор», честное превью:
  - `allChats` (у одного фото максимум: `setAllChats` снимает флаг с других,
    их исключения остаются) + `excludedPeerIds`. Правило
    `banner(peerId:)`: своё фото чата (`peerIds` фото **без** `allChats`) →
    фото «Все чаты», если чат не в исключениях → нет фона. Свои чаты фото
    «Все чаты» лежат в `peerIds` без дела и возвращаются при выключении
    флага (`setPeers` другого фото их забирает, как раньше; флаг и
    исключения не трогает). Новые поля `decodeIfPresent` — старые
    `index.json` читаются как есть.
  - `ShadowChatBannerBatch` строит `ShadowChatBannerResolver` (словарь
    peerId → фото) один раз на пачку; кэш presentationData/тем по
    `banner.id`, как было. «Избранное» и любой новый чат получают общий фон;
    скрытые/закрытые чаты фильтруются раньше, фон их не показывает.
  - «Узор (без стыков)» (`pattern`): `ShadowChatBannerPatternLayer`
    (CAReplicatorLayer) — копии фото во всю ширину строки одна под другой,
    сдвиг `patternShift(rowY:)` от верха списка: строка берёт свою позицию из
    `ChatListItemNode.updateAbsoluteRect` (вызывается и при прокрутке), так
    что соседние строки продолжают друг друга, узор стоит на месте, строки
    едут поверх. Цвет текста — по средней яркости всего фото
    (`averageLuminance`). Ползунок «Положение» в этом режиме скрыт.
  - Превью в редакторе — во всю ширину и высотой настоящей строки
    (`ShadowChatBannerRows.rowHeight(fontSize:compact:)` — та же формула и
    шрифт, что в `ChatListItem`, `listsFontSize` + `compactChatList`); раньше
    карточка была уже и ниже строки, и фото в списке «съезжало». С «Узором»
    в превью три строки. Цвет текста в превью и списке —
    `estimatedRowAspect(fontSize:compact:)`.
  - Экран: тумблер «Все чаты» → вместо «Чаты с этим фоном» пункт
    «Исключения» (тот же выбор чатов), подпись «Свои фото у отдельных чатов
    важнее этого.»; в списке фото «Все чаты» / «Все чаты, кроме N».
    Экспорт/синхронизация — по-прежнему только тумблер `chatBannersEnabled`.

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
  С 1.10.1 снимок и после неудачного Face ID / Touch ID: `LocalAuth.authDetailed`
  отдаёт `biometryRejected` (`LAError.authenticationFailed`; отмена и «Ввести
  пароль» не считаются) — экран код-пароля и `ShadowChatLockUI.authenticate`,
  причина `.biometrics`. Куда идёт снимок — два тумблера устройства
  (UserDefaults, по умолчанию оба вкл): `sendsToSaved` (файл в очередь →
  «Избранное», потом удаляется) и `savesToGallery` (сразу в Фото). Оба выкл —
  `beginCapture` не снимает.
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

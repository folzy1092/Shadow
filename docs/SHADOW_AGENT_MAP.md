# Shadow: карта проекта для агентов

Shadow — форк Telegram-iOS (раньше назывался AyuGram / Ghostgram). Корневой
`CLAUDE.md` в основном описывает **апстримный** Telegram: Bazel, симуляторы,
Postbox-рефакторинг. Этот файл описывает то, что добавил форк, и то, что
неочевидно при первом заходе в репозиторий.

## 1. Ветки и git

- **Единственная рабочая ветка — `master`** (default branch на GitHub).
  Коммитить и пушить в неё. `main` и прочие `codex/*`, `fix/*`, `ci/*` —
  исторические: на 2026-10-01 всё их полезное содержимое влито в `master`.
- `origin` = `github.com/folzy1092/Shadow`. Апстрим Telegram отдельным
  remote не подключён; обновление на новый релиз — `tools/shadow-update.sh`
  (инструкция в `ОБНОВЛЕНИЕ.md`).
- Облачные сессии клонируют репозиторий **неглубоко** (shallow). `git
  merge-base` между ветками может молча ничего не вернуть — сначала
  `git fetch --deepen=400 origin <ветки>`.
- Прежде чем анализировать или чинить, сверьтесь с `git log origin/master`:
  локальный чекаут может отставать, и найденный «баг» окажется уже исправлен.

## 2. Сборка и тесты

- Собрать приложение можно только на macOS + Xcode (Bazel). Под Linux нет ни
  Xcode, ни `swiftc`: там доступны лишь Python-тесты контрактов.
- CI: `.github/workflows/build.yml` — на push в `master`/`main` собирает
  IPA (~45 мин), перед сборкой гоняет тесты:
  - `python3 -B -m unittest discover -s Tests/ShadowSettings -p 'test_*.py'`
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
- Успешная сборка `master` публикуется как GitHub Release `build-<номер>`.
  **Что объявлять пользователям, решает файл `shadow-update.json` в корне**
  (`enabled`, `build`, `version`, `title`, `notes`, `url`, `minimum_build`);
  приложение читает его с raw.githubusercontent.com (кэш до ~5 минут), а
  к релизам GitHub обращается, только если файл недоступен.
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
- Ответы пользователю — на русском.

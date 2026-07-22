# Ghostgram: состояние форка и план обновления до 12.9

Дата ревизии: 2026-07-16. Составлено без каких-либо изменений в репозитории
(никаких fetch/merge/rebase не выполнялось).

---

## 1. Git-репозиторий — есть

`.git` на месте, структура корректная. Особенность: это **partial clone**
(`partialclonefilter = blob:none`, `promisor = true`) — блобы подтягиваются
лениво с сервера. Значит, часть операций с историей требует сети, а первый
`git fetch` после долгого перерыва скачает много объектов.

## 2. Remotes и история

- **Remote `origin`** = `https://github.com/TelegramMessenger/Telegram-iOS.git`
  — официальный апстрим. Отдельного remote `upstream` нет: origin уже и есть
  апстрим. Своего remote у форка нет вообще.
- Клонировал `System Administrator <root@MacBook-Air-Matvey.local>` (Mac товарища).
- **Текущая ветка: `ayugram`.**
- Ветки:
  - `ayugram` — форк, tip `1a0c521d`
  - `master` — точка клона апстрима `6e370e06` (= origin/master на момент клона)
  - `worktree-smart-forward-2` — сброшена на tip ayugram, принадлежит битому worktree (см. §3)

История форка — 10 коммитов поверх апстрима `6e370e06`, автор
`AyuGram Fork <s1gm44aa4@gmail.com>`:

```
1a0c521 mark kept deleted messages + trash badge next to timestamp   ← tip ayugram
dda9f78 build without app extensions (Sideloadly-friendly IPA)
c0610d1 anti-delete + aggressive offline presence
7959a6e Settings screen with hide-online / hide-typing toggles
bc901bc fall back to local container when App Group unavailable
223614b ad-hoc codesign in .bazelrc for Sideloadly builds
12280a3 Add iPhone install guide
fc7cb84 gitignore personal build config (api_hash)
d78ba32 spoof client fingerprint as Telegram Desktop / Windows
40d312a settings model + hide online/typing; anti-delete design
6e370e0 (база апстрима)
```

## 3. Папка `.claude`

Инструкций/настроек от предыдущего разработчика там **нет**. Содержимое —
только `worktrees/smart-forward-2/`: полная устаревшая копия репозитория,
приехавшая с Mac. В `.git/worktrees/smart-forward-2` зарегистрирован
git-worktree, но его `gitdir` указывает на путь Mac
(`/Users/matvej/Desktop/iphone app/...`) — на Windows он битый (dangling).
После стабилизации его можно вычистить (`git worktree prune` + удалить папку),
но это отдельным шагом и не сейчас.

Реальная документация форка — **`AYUGRAM_FORK.md`** в корне. Корневой
`CLAUDE.md` — апстримный файл про сборку/архитектуру Telegram, не про форк.

⚠️ **`AYUGRAM_FORK.md` сильно устарел.** Он описывает только
anti-delete + hide online/typing + fingerprint spoof и утверждает, что правок в
существующих файлах «ровно три». По факту фич и правок в разы больше (§4).

## 4. Что реально закастомлено (по коду)

### Твои 5 фич — все на месте

| Фича | Где |
|---|---|
| Ghost Master flag | `ghostMode` в `submodules/TelegramCore/Sources/AyuGram/AyuGramSettings.swift` — мастер-гейт, каждая ghost-фича = `ghostMode && <флаг>` |
| Forward without author | `ChatControllerForwardMessages.swift`, `ChatPanelInterfaceInteraction.swift`, `ChatControllerLoadDisplayNode.swift`, `ChatInterfaceStateContextMenus.swift` |
| Скрытие индикатора активности | `ManagedLocalInputActivities.swift` (typing), `ManagedAccountPresence.swift` (online) |
| Тихое потребление медиа | `MarkMessageContentAsConsumedInteractively.swift`, `AyuBurnViewOnceMedia.swift`, флаг `keepSelfDestructMedia` |
| Кастомный badge-эмодзи | `AyuGram/GitConfig.swift` (remote-конфиг), `PeerInfoProfileItems.swift`, `PeerInfoScreen.swift`, `Account.swift` |

### Сверх твоего списка (тоже живёт в форке)

- Anti-delete + «graveyard» удалённых сообщений: `AyuGramAntiDelete.swift`,
  `AyuSavedMedia.swift`, `AyuForkStore.swift`, hook в
  `AccountStateManagementUtils.swift`, trash-badge у timestamp
  (`StringForMessageTimestampStatus.swift`, `ChatMessageDateAndStatusNode`)
- История правок сообщений: `AyuEditHistory.swift`, `SavedMessageEditsAttribute.swift`
- Delayed send через scheduled: `AyuDelayedSend.swift`, правки
  `EnqueueMessage.swift`, `PendingMessageManager.swift`
- Hide read receipts (`SynchronizePeerReadState.swift`), hide story views
  (`Stories.swift`, `OpenStories.swift`), exact last seen (`AyuLastSeen.swift`,
  `PresenceStrings.swift`)
- UI: wide channel posts, exact view counts (`ChatMessageBubbleItemNode`),
  folders at bottom / compact bottom bar / hide bottom search
  (`TabBarComponent`, `TabBarContollerNode`, `ChatListController*`),
  hide All-Chats folder
- Allow save restricted content, round-video back camera (`Camera.swift`,
  `VideoMessageCameraScreen`), camera tile в пикере (`MediaPickerScreen`)
- Client fingerprint spoof «Telegram Desktop / Windows»:
  `MTApiEnvironment.h/.m`, `Network.swift`, `AyuGramClientProfile.swift`
- Сборка без app extensions (Sideloadly), ad-hoc codesign в `.bazelrc`,
  фоллбек на локальный контейнер без App Group
- Settings-экраны: `AyuGramSettingsController.swift`, `AyuForkStorageController.swift`
- Иконки: `GhostIcon`/`GhostActiveIcon` imageset'ы, `gen_ghost_icons.py`

Итого правки размазаны по **десяткам апстримных файлов** — это ключевой факт
для выбора стратегии обновления.

## 5. Незакоммиченные изменения — подтвердить не удалось

`git status` выполнить не получилось (тулинг временно не пускал git-команды).
Косвенные признаки: `.git/index` имеет mtime 10 июля, при этом десятки
исходников (включая Ayu-файлы и правленые апстримные) изменены 10–12 июля —
**позже последнего коммита**. Скорее всего, в рабочем дереве есть
незакоммиченный WIP. Проверить перед любыми действиями:

```
git -C "C:\Users\Folzy\Desktop\projects\iphone app\iphone app\Telegram-iOS" status
```

## 6. ⚠️ Главный риск: у форка нет бэкапа

`origin` — официальный Telegram, пушить туда нельзя и некуда. 10 коммитов
форка существуют **только на этом диске**. Неудачный rebase/merge, сбой диска —
и история потеряна. Бэкап — обязательный шаг №0.

## 7. План обновления до 12.9 (черновик, на подтверждение)

1. **Чистое состояние.** `git status`; если есть WIP — закоммитить его на
   `ayugram` (или отдельную ветку). Никаких merge на грязном дереве.
2. **Бэкап форка.** Тег `ayugram-backup-2026-07-16` + **приватный** GitHub-репо
   как второй remote (`git remote add ghostgram <url>` + push ayugram/master/тег).
   Альтернатива/дополнение: `git bundle create ghostgram.bundle --all` на другой диск.
3. **Найти ref 12.9.** `git fetch origin` (первый fetch, из-за partial clone
   будет объёмным), найти тег `release-12.9` или соответствующий коммит.
4. **Merge, а не rebase.** Дока советовала rebase из расчёта «3 правки»; реально
   правок десятки, а rebase проигрывает 10 коммитов по одному — конфликты
   решаются многократно. Один `merge release-12.9` в копию ayugram = один
   проход конфликтов. Работать на throwaway-ветке `merge-12.9-try`, `ayugram`
   не трогать до успешной сборки.
5. **После merge:** `git submodule update --init --recursive`, свериться с
   новым `versions.json` (app станет `12.9`, могли поменяться пины Xcode/Bazel).
6. **Сборка** `debug_sim_arm64` с `--continueOnError`, чинить конфликтные места.
   Прогнать все ghost-фичи руками (сборка возможна только на Mac — учесть).
7. **Финализация:** fast-forward `ayugram` на результат, тег
   `ayugram-12.9`, push в приватный remote. Обновить `AYUGRAM_FORK.md` под
   реальный список фич.

Открытый вопрос: сборка Bazel/Xcode требует macOS — на Windows шаги 1–5
выполнимы, шаг 6 нужен доступ к Mac (или CI на macOS).

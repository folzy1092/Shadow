# Баг отправки файлов + краш при drag&drop — анализ

Дата: 2026-07-20. Форк: **Shadow** (ветка `ayugram`). Составлено без изменений в коде.

## Симптомы

1. Скрепка → выбрать файл в Files → синяя кнопка «Открыть/Отправить» → **нет реакции**.
2. Drag & drop файла из другого приложения в форк → при отпускании пальца **краш**.

В стоковом Telegram и в Swiftgram оба сценария работают → баг специфичен для форка.

---

## Что найдено (пункты 1–5)

### 1 и 2 — Хендлеры пикера и Drop — чистый апстрим, форком НЕ тронуты

- **Document Picker:** `submodules/LegacyMediaPickerUI/Sources/LegacyICloudFilePicker.swift:43`
  — `LegacyICloudFileController: UIDocumentPickerDelegate`, `documentPicker(_:didPickDocumentsAt:)`.
  Вызывающий код: `submodules/TelegramUI/Sources/ChatControllerOpenAttachmentMenu.swift:1186`
  `presentICloudFileGallery(...)` → `legacyICloudFilePicker(...)` → строит `ICloudFileResource`
  → `enqueueMessages`. `git log` по обоим файлам — **только апстрим-коммиты**, ни одного
  Ayu/fork-коммита.

- **Drag & Drop:** `submodules/TelegramUI/Sources/ChatController.swift:9750-9800`
  — `UIDropInteractionDelegate`. Важные детали (апстрим, без правок форка):
  - `canHandle` (строка 9751) принимает **только `kUTTypeImage`**;
  - `performDrop` (строка 9769) делает `session.loadObjects(ofClass: UIImage.self)` и
    force-cast `imageItems as! [UIImage]` (строка 9774).
  `git log` по файлу — **только апстрим-коммиты**.

### 3 — Правки форка на общем пути отправки/сети (коммит cf744cc)

Оба сценария сходятся в `enqueueMessages`, который WIP `cf744cc` модифицирует:

| Файл | Правка | Гейт |
|---|---|---|
| `TelegramCore/Sources/PendingMessages/EnqueueMessage.swift` | `AyuDelayedSend.transform(...)` на каждое исходящее | `effectiveSendViaScheduled` = `ghostMode && sendViaScheduled` |
| `TelegramCore/Sources/Network/FetchedMediaResource.swift` | `ayuAutoSaveHook` на каждый media-fetch | `saveAllIncomingMedia` (default OFF) |
| `TelegramCore/Sources/State/PendingMessageManager.swift` | `ayuReassertOfflineAfterSendIfNeeded()` после send RPC | `effectiveSendViaScheduled/WithoutOnline` |
| `MtProtoKit/Sources/MTApiEnvironment.m`, `Network.swift` (fingerprint spoof) | Проверено — **безобидно** (полнота copy-конструктора + снятие присваивания `systemLangCode`). Сломать аплоад **не может**. | — |

**Ключевой факт:** `AyuDelayedSend.transform` и auto-save хук **гейтятся `ghostMode`/`saveAllIncomingMedia`,
которые по умолчанию выключены**. Пользователь подтвердил: **Ghost Mode постоянно OFF** → эти
хуки — **no-op**. Значит cf744cc как причина **ослаблен**.

### 4 — Стектрейс краша — недоступен

Ни одного `.crash`/`.ips` на диске. Запустить приложение нельзя (Windows; Bazel требует macOS).
Живой стектрейс отсюда получить невозможно.

### 5 — Проверка установленного билда (переопределяет всё)

Распакован установленный **`ipa/Telegram.ipa`**:

| Поле | Значение |
|---|---|
| `CFBundleDisplayName` | **Telegram** (не «Shadow») |
| `CFBundleShortVersionString` | **12.8**, `CFBundleVersion` = 1 |
| `CFBundleIdentifier` | `ph.telegra.Telegraph` |
| `PlugIns` / `Watch` | **отсутствуют** (расширения уже вырезаны) |
| `UIFileSharingEnabled` | `False`, `CFBundleDocumentTypes`: 0 |
| Дата файла | **5 июля** |

Переименование в **«Shadow»** происходит в `Telegram/BUILD` внутри коммита **cf744cc (16 июля)**.
Этот бинарник всё ещё называется **«Telegram»** → это **билд ДО cf744cc. WIP в нём НЕТ.**

---

## Вывод

1. Код пикера и drop — чистый апстрим (не тронут форком).
2. Ghost Mode OFF → WIP-хуки отправки мертвы (no-op).
3. Видимый артефакт (5 июля, «Telegram» 12.8) **старше** WIP → **cf744cc не является причиной**
   для этого бинарника.

Остаются форк-специфичные **всегда включённые** отличия pre-WIP билда — **sideload/build config:**

- вырезанные расширения (`.bazelrc --//Telegram:disableExtensions`);
- ad-hoc codesign (`.bazelrc --ios_signing_cert_name="-"`), пересборка подписи Sideloadly;
- **фоллбек App Group на `~/Documents/appdata` в `AppDelegate.swift`** (коммит bc901bc).

App-Group-фоллбек — **самый вероятный общий подозреваемый** для *pre-send* падения: и импорт из
document picker, и импорт через drag&drop копируют входящий файл в путь, производный от контейнера;
если это предположение о пути неверно — «Открыть» в пикере завершается в никуда, а drop может
падать.

**НО:** пользователь говорит, что стоковый Telegram сайдлоадится так же и работает → это ослабляет
версию с чистым механизмом сайдлоада и возвращает фокус к коду форка.

---

## Что нужно, чтобы точно локализовать (нужен один runtime-факт)

1. **Как называется иконка на телефоне — «Telegram» или «Shadow»?**
   Мгновенно скажет, задействован ли cf744cc.
2. **Крашлог:** на iPhone — Настройки → Конфиденциальность и безопасность → Аналитика и улучшения →
   Данные аналитики → найти `Telegram-…-….ips` от краша drop. Либо через Mac: Xcode → Window →
   Devices and Simulators → View Device Logs. Верхние фреймы → укажу точную строку.

## Открытые варианты следующего шага

- Продолжить в предположении, что это **билд «Telegram» (5 июля)**, и копать путь контейнера из
  App-Group-фоллбека как ломающий импорт файлов; **или**
- Сначала взять крашлог.

Обновление `AYUGRAM_FORK.md` — отдельный шаг после разбора бага (по просьбе пользователя отложено).

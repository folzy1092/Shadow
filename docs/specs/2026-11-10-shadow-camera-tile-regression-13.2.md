# Спек: плитка камеры в галерее сломалась после перехода на 13.2

Дата: 2026-11-10. Автор: сессия-диагност (без устройства и без сборки — только чтение кода).
Для: сессия, которая чинит. Версия форка на момент поломки — Shadow 2.3.0 (база Telegram 13.2),
сборка 37017. Ветка работы — `master` (см. `docs/SHADOW_AGENT_MAP.md` §5q, §5d).

## 0. Что сломалось (со слов Folzy)

В чате → скрепка → вкладка «Галерея»:

1. **Живой предпросмотр включился сам** (в плитке камеры идёт живая картинка, хотя так не было).
2. **Плитка камеры стала большой и игнорирует настройку** (раньше была компактной по настройке
   «Компактная плитка камеры»; теперь всегда в две ячейки высотой).
3. **Нажимаю на плитку → открывается камера → через ~0,5 с камера зависает.**

Всё началось с Shadow 2.3.0 (мерж `release-13.2`, коммит `c2ccc388`). До этого (2.2.x, база 13.1.2) работало.

Не известно (спросить у Folzy / проверить): iOS и устройство, режим «Живой предпросмотр» и
«Камера в галерее» в Кастомизации, включён ли Low Power / экономия энергии, зависает ли всё приложение
или только экран камеры, воспроизводится ли в симуляторе (в симуляторе `.chatCamera` не отличается,
а sticker/avatar-ветка там отключена).

## 1. Проверено чтением кода (факты)

### 1.1. С 13.2 в форк пришли ДВЕ новые подсистемы, под ними — вся галерея

В родителе-Shadow до мержа (`b5f8322c`) не было ни `MediaGrid`, ни `MediaPickerGridHost`. Оба пришли из апстрима:

| Подсистема | Флаг | Дефолт | Где |
|---|---|---|---|
| **MediaGrid v2** — слойная сетка вместо `GridNode` | `context.usesMediaPickerGridV2` | **включена** | `submodules/AccountContext/Sources/MediaPickerGridV2.swift`, `submodules/MediaPickerUI/CLAUDE.md` |
| **Chat media editor V2** — новая камера в плитке (`.chatCamera`) с передачей `CameraHolder` в экран камеры | `context.usesChatMediaEditorV2` / `routesToChatMediaEditorV2(.inlineCameraCell)` | **включён** | `submodules/AccountContext/Sources/ChatMediaEditorV2.swift`, `ChatMediaV2Routing.swift` |

Оба убираются киллсвитчем (app-config `ios_killswitch_disable_media_grid_v2`,
`ios_killswitch_disable_chat_media_editor_v2`) или в Debug Settings (`mediaGridLegacy`,
`chatMediaEditorLegacy`, `submodules/DebugSettingsUI/Sources/DebugController.swift:742-745`).
**Это самый быстрый способ разделить причины — см. §3.**

Форковые настройки плитки (`showCameraTile`, `cameraTileLivePreview`, `cameraTileCompact` в
`TelegramCore/Sources/AyuGram/AyuGramSettings.swift`, UI в `SettingsUI/.../AyuGramSettingsController.swift:1050-1055`)
писались под старую `GridNode`-раскладку и старую ветку камеры.

### 1.2. Симптом 2 (размер плитки) — причина найдена, уверенность высокая

- Форковая компактность живёт ТОЛЬКО в старом пути:
  `submodules/MediaPickerUI/Sources/MediaPickerScreen.swift:2358`
  `let cameraHeight = ayuGramSettingsCurrent.cameraTileCompact ? itemWidth : itemWidth * 2.0 + itemSpacing`
  — это `cutoutRects` для `GridNode`.
- Новая сетка берёт размер плитки не оттуда. В `MediaGridView` слоты камеры зашиты константой:
  `submodules/TelegramUI/Components/MediaGrid/Sources/MediaGridView.swift:303`
  `cameraSlots = [(row 0, col 0), (row 1, col 0)]` — всегда 2 строки. `MediaPickerMediaGridHost.cameraFrame(for:)`
  (`MediaPickerMediaGridHost.swift:971`) лишь подгоняет канвас под уже посчитанный сеткой прямоугольник.
- Итог: `cameraTileCompact` для `MediaGridView` не существует → плитка всегда высокая. Совпадает с жалобой.
- `cameraLevels` (на каких уровнях сетки есть камера) тоже задан без оглядки на форк
  (`MediaPickerMediaGridHost.swift:828`).

Что делать (варианты, выбрать с Folzy):
- (A) Научить `MediaGridView` камере из одной строки: параметр `cameraSlotRows` (1 или 2) вместо статической
  `cameraSlots`; пробросить из хоста `ayuGramSettingsCurrent.cameraTileCompact`. Нужно обновить
  `MediaGridUniformLayout.reservedFrame`, зум-переходы (`cameraRole`, `MediaGridZoomTransition`, строки ~1226-1265),
  `cameraPreviewSize` в `MediaPickerCameraCell.swift` (размер канваса под соотношение 1×1 вместо 1×2) и тесты
  `Tests/MediaGrid*`. Это правка в стороне, которая в апстриме меняется → конфликты в следующих мержах;
  держать правку минимальной и помеченной `// Shadow`.
- (B) Если (A) слишком дорого: на время откатить галерею на `GridNode` для режима `.chatAttachment`
  (форковый флаг поверх `usesMediaPickerGridV2`), оставить v2 для остальных режимов. Минус: теряем зум/уровни,
  которые апстрим считает фичей 13.2.
- Критиковать: настройка «компактная плитка» теперь конфликтует с дизайном v2 (уровни 1–31, камера на 3).
  Если Folzy не против — можно честно признать, что v2 + компактная плитка требует (A), а не латать.

### 1.3. Симптом 1 (живой предпросмотр «сам») — по коду НЕ объясняется, нужна проверка

В новой ветке `.chatCamera` тумблер учтён:
- `MediaPickerScreen.swift` (`case .chatCamera`) → `modernCameraHasLivePreview = fullTranslucency && cameraTileLivePreview`;
- `mediaPickerChatCameraCellCaptureAction` (`TelegramUI/Components/ChatMediaSend/Sources/MediaPickerCameraCell.swift:50`)
  стартует захват только при `hasLivePreview == true`.

То есть при выключенном «Живом предпросмотре» плитка не должна запускать камеру. Значит, одно из:
1. Тумблер у Folzy реально включён (дефолт `true`, `AyuGramSettings.swift:471`, `decodeIfPresent ?? 1`) и раньше
   «живость» просто не была заметна/была иной; сверить в Кастомизации (`shadow://customization/camera-live`).
2. Захват стартует мимо `mediaPickerChatCameraCellCaptureAction`: `cameraTapped()` делает `camera.startCapture()`
   при `!modernCameraHasLivePreview` (это нужно для передачи в экран камеры и штатно), но если `restore()`
   (возврат из камеры, `MediaPickerScreen.swift:~1159`) не срабатывает или срабатывает не там, `chatCameraCaptureState`
   сбрасывается в `nil`, и дальше `updateIsCameraActive()` ведёт себя как «первый раз». Проверить по логам
   (`CameraContext startCapture/stopCapture`, `LegacyCamera.swift:206-212`) — кто вызывает старт при выключенном тумблере.
3. Ветка `.legacyAttachmentCamera` (`TGAttachmentCameraView`) и ветка `.chatCamera` показывают плейсхолдер по-разному;
   «живой» вид может быть заставкой `CameraSimplePreviewView` до `removePlaceholder`, а не реальным потоком.
4. `showCameraTile`/`cameraTileLivePreview` перезаписаны миграцией настроек при 13.2 (маловероятно, но проверить
   `shadow-settings.json`/`ShadowSettingsTransfer` на сброс значений).

Не выдумывать причину: сначала воспроизвести и снять лог (§3).

### 1.4. Симптом 3 (зависание через ~0,5 с после открытия камеры) — причина НЕ установлена

Фактура:
- Нажатие на плитку в `.chatCamera` не создаёт новую камеру: `cameraTapped()` (`MediaPickerScreen.swift:1135`) отдаёт
  **уже созданную** `LegacyCamera` + `previewView` + `parentView` в `controller.openCamera(CameraHolder(...))`;
  дальше `ChatControllerOpenAttachmentMenu.openCamera(cameraView:cameraHolder:entry:)` (`:2114`) открывает экран
  камеры и «усыновляет» этот же объект. Ветка `.legacyAttachmentCamera` (прежняя) такой передачи не делала.
  Передача + свой же `camera.setCaptureMode(.photo)` при `restore()` — главный подозреваемый на гонку между
  остановкой/запуском сессии и экраном камеры.
- Камерный код в 13.2 сильно менялся (новые `CameraCaptureMode`, `CameraCaptureModeChange`,
  `CameraPreviewOrientation`, `CameraVideoOrientation`, `SimulatorPhotoSource`, правки `CameraDevice`/`CameraOutput`/
  `LegacyCamera` +204 строки — `git diff b5f8322c c2ccc388 -- submodules/Camera`), а форк правит камеру точечно
  (`CameraPreviewView` Legacy и Neo, #84 iPhone Duo; `ShadowRoundVideoCameraFallback` для кружков). Кандидаты на
  конфликт «наш код × новая логика»: ориентация превью (Duo-правки #84), `CameraCaptureMode` переключение при
  открытии.
- Совпадение «около полсекунды» похоже на таймер/асинхронный шаг после открытия (например, `removePlaceholder(delay: 0.35)`
  в `.chatCamera`, `scheduleChatCameraCaptureUpdate` через `DispatchQueue.main.async`, переключение режима при
  передаче) — это наблюдение по таймингу, не доказательство.
- Неясно, зависание ли это камеры (сессия не идёт) или UI (главный поток). Это разные баги. Различить: трогается
  ли кнопка закрытия, идёт ли таймер/вспышка, есть ли в `Logger` последние записи `CameraContext`.

## 2. Критическая оценка (честно)

- Три симптома, скорее всего, **один корень**: форк подключил свои настройки к старому пути, а 13.2 включил новый путь
  по умолчанию. Это ожидаемая цена мержа апстримовой переписанной галереи, не случайность.
- Но «зависание камеры» — НЕ доказано, что тот же корень. Не объявлять причиной v2/editor V2, пока тумблеры отладки
  не подтвердят (§3). Ставка: `chatMediaEditorLegacy` лечит симптом 3, `mediaGridLegacy` — симптом 2.
- Плохая идея, которую не делать: молча выключить киллсвитчи у всех пользователей. Это откат фич 13.2 ради
  одной плитки; нужна точечная починка либо форковый флаг.

## 3. План работ

### 3.1. Диагностика (обязательно перед правками)

На устройстве/симуляторе (по возможности с iOS, как у Folzy), сборка 37017 или локальная:

1. Воспроизвести 3 симптома, записать видео (`simctl io recordVideo`, `tools/animation_sheet.py` — см.
   `AGENTS.md`, «Visual features and animations»).
2. Debug Settings (`DebugController.swift`): по очереди
   - «Media picker: legacy grid» (`mediaGridLegacy`) → пропал ли симптом 2 (ожидаем: да);
   - Chat media editor legacy (`chatMediaEditorLegacy`) → пропали ли 1 и 3 (ожидаем: 1 и 3 уходят, т.к. ветка вернётся к `TGAttachmentCameraView`);
   - оба сразу — эталон «как в 2.2.x».
   Записать таблицу «флаги × симптомы» прямо в этот файл.
3. Снять лог: `CameraContext startCapture/stopCapture` + `ShadowApplog`/`Logger` вокруг нажатия на плитку;
   сторонний вопрос: падает ли главный поток (Instruments Time Profiler / `sample`) в момент зависания.
4. Проверить значения `showCameraTile`, `cameraTileLivePreview`, `cameraTileCompact` в рантайме
   (`ayuGramSettingsCurrent`), в режиме маскировки Full они читаются иначе (`ShadowDisguise.swift`, §7 агент-карты).

### 3.2. Правки

- Симптом 2: §1.2 вариант A (предпочтительно) или B. Не терять `// Shadow` пометки и не ломать
  `MediaPickerMediaGridHost` ↔ `MediaPickerGridNodeHost` паритет (CLAUDE.md модуля: «keep it that way»).
- Симптом 1: по итогам §3.1 — либо починить место, которое стартует захват вопреки тумблеру, либо (если тумблер
  реально включён) закрыть как «не баг» и сказать Folzy честно.
- Симптом 3: по итогам §3.1. Если лечится `chatMediaEditorLegacy` — добавить форковый переключатель
  (Кастомизация, раздел «Медиа») «Новая камера в галерее» на `routesToChatMediaEditorV2(.inlineCameraCell)` и
  держать его выключенным по умолчанию, пока гонка в передаче `CameraHolder` не найдена. Поведение при `false` —
  `.legacyAttachmentCamera`, как в 2.2.x.
- Тесты: есть чистые функции `mediaPickerCameraCellBranch`, `mediaPickerChatCameraCellCaptureAction`
  (`ChatMediaSend`) — добавить регрессионные кейсы на форковые настройки (вынести решение «стартовать ли захват»
  с учётом `cameraTileLivePreview` в чистую функцию, если её нет). Для MediaGrid — расширить `Tests/MediaGrid*`
  под камеру в одну строку (если вариант A).

### 3.3. Критерии приёмки

- При `cameraTileCompact = true` плитка занимает одну ячейку на уровнях, где показывается камера; при `false` — две.
- При `cameraTileLivePreview = false` плитка показывает статичную картинку и НЕ запускает захват (проверить в логах).
- Нажатие на плитку открывает камеру, камера не зависает минимум 30 с, фото и видео снимаются, возврат в галерею
  восстанавливает плитку без чёрного кадра.
- `showCameraTile = false` по-прежнему убирает плитку целиком (все ветки).
- Debug-флаги `mediaGridLegacy` / `chatMediaEditorLegacy` не требуются для нормальной работы.
- `python3 build-system/Make/Make.py ... test --target //submodules/MediaPickerUI:MediaPickerGridCellDecorationsTests`
  и целевые тесты MediaGrid зелёные.

## 4. Правила форка, которые касаются этой работы

- Один апдейт = один билд: коммитить локально, тесты, **один** пуш в `master` (CLAUDE.md, «One update = one build»).
- Это исправление — третья цифра Г.О.Ф (`ShadowVersion.fork` + `versions.json` → `fork`, §5d): 2.3.0 → 2.3.1.
- Список изменений пишет агент, тип ИСПРАВЛЕНО, простым русским; после зелёного CI — сразу объявить
  (`tools/shadow-announce.py`, §5d). Время для Folzy — Рига (Europe/Riga).
- Не раздувать правки в апстримных файлах (`MediaGridView`, `MediaPickerScreen`): каждая правка — потенциальный
  конфликт в следующем мерже; помечать `// Shadow` и описывать в `SHADOW_AGENT_MAP`.

## 5. Ссылки

- Мерж: `c2ccc388` «Merge Telegram release-13.2 into Shadow (2.3.0)»; родитель Shadow-стороны `b5f8322c`.
- `docs/SHADOW_AGENT_MAP.md` §5q (база 13.2), §5g/«Компактная плитка камеры», §7.
- `submodules/MediaPickerUI/CLAUDE.md` (сетка v2, маршрутизация), `submodules/TelegramUI/Components/MediaGrid/CLAUDE.md`.
- `docs/shadow-links.md:172-173` (`shadow://customization/camera-tile`, `camera-live`; ссылка `camera-compact` — в агент-карте).

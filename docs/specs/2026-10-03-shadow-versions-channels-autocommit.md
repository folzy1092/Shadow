# Промт для агента: двойная версия, ветки stable/beta, автокоммит вайтлиста

Репозиторий: форк Telegram-iOS «Shadow» (`folzy1092/Shadow`, рабочая ветка
`master`, в локальном чекауте remote называется `ghostgram`). Данные приложения
(манифест обновлений, чейнджлог, вайтлист) лежат в публичном
`folzy1092/tgfork`, ветка `main`, рядом с `config.json` бейджиков. Сначала
прочитай `docs/SHADOW_AGENT_MAP.md` — там правила ветки, CI, номера сборки,
контрактные тесты.

Контекст про существующий код, на который всё опирается:
- `submodules/TelegramCore/Sources/AyuGram/ShadowUpdateCheck.swift` — проверка
  обновлений, разбор манифеста `shadow-update.json`, `Manifest`, `Release`,
  `Status`, `installedBuild`, `installedVersion` (из `CFBundleShortVersionString`).
- `submodules/SettingsUI/Sources/AyuGramSettingsController.swift` — хаб настроек
  Shadow, большая кнопка «Проверить обновления», строка статуса, кнопка
  «Скачать IPA», карточка патч-ноутов (`shadowUpdateNotesText`).
- `submodules/TelegramCore/Sources/AyuGram/ShadowDeviceAccess.swift` — ядро
  вайтлиста: `Whitelist { enabled, devices, requestURL }`, `Device { id, note }`,
  `parse`, `encode`, `decide`, `deviceId` (Keychain), `whitelistURL`
  (`raw.githubusercontent.com/folzy1092/tgfork/main/shadow-whitelist.json`),
  `editURL`, `adminPeerId` (7878830498), `adminPeerIds` (+ matey 1068369028),
  `accessRequestBody(...)`.
- `submodules/SettingsUI/Sources/ShadowDeviceAccessController.swift` — админ-меню
  «Доступ устройств»: черновик списка, «Добавить в список», «Удалить из списка»
  (action sheet по тапу на устройство), «Скопировать JSON», «Открыть файл на
  GitHub». Сейчас изменения НЕ коммитятся: пользователь вручную копирует JSON и
  коммитит через GitHub.
- `tools/shadow-bot/worker.js` + `wrangler.toml` + `README.md` — Cloudflare
  Worker: `POST /request` принимает `{id,name,model,system,build}` и шлёт
  владельцам в Telegram сообщение с кнопкой `tg://shadow/access?id=…`. Секреты:
  `BOT_TOKEN`, `OWNER_CHAT_ID`. Опционально KV `THROTTLE`. Воркер задеплоен на
  `https://shadow-access-bot.denisvasilev817.workers.dev`.
- CI: `.github/workflows/build.yml`. Номер сборки = `git rev-list --count HEAD` +
  `build_number_offset` (сейчас 3730). Релиз `build-<N>` с `Shadow.ipa` в Shadow
  и, если задан секрет `TGFORK_RELEASE_TOKEN`, зеркалом в tgfork. Заголовок
  релиза: `Shadow ${APP_VERSION} (${BUILD_NUMBER})`, где `APP_VERSION` =
  `versions.json.app` (`12.9.2`).
- Контрактные тесты: `Tests/ShadowSettings/test_*.py` (читают исходники как
  текст), Swift-тесты в `Tests/ShadowSettings/*.swift` компилируются
  `build-system/ci/test_shadow_foundation.py`. На Windows гонять с
  `PYTHONUTF8=1`. `swiftc` локально нет — Swift-тесты проверяет только CI.

Сделать три вещи.

## 1. Двойная версия `12.9.2-1.0.0`

Формат: `<версия Telegram>-<версия форка>`, старт форка `1.0.0`. Telegram-версия
уже в `versions.json.app`.

- Добавь версию форка в один источник правды. Вариант: ключ `fork` в
  `versions.json` (`"fork": "1.0.0"`) + константа в Swift, читающая её из
  `Bundle`/Info.plist, либо захардкоженная рядом с `ShadowUpdateCheck`. Нужна
  строка `ShadowVersion.fork` и полная `ShadowVersion.full` =
  `"\(installedVersion)-\(fork)"`.
- CI: прокинь версию форка в Info.plist (как делается для api id/версии) и в
  заголовок релиза: `Shadow ${APP_VERSION}-${FORK_VERSION} (${BUILD_NUMBER})`.
  `APP_VERSION` берётся из `versions.json.app`, `FORK_VERSION` — из
  `versions.json.fork`.
- В хабе настроек (`AyuGramSettingsController.swift`) и в карточке обновления
  показывай полную версию `12.9.2-1.0.0` вместо просто `12.9.2`. Сейчас версию
  даёт `ShadowUpdateCheck.installedVersion` / поле `version` манифеста — там, где
  показывается голая Telegram-версия, показывай полную форк-версию.

## 2. Ветки stable / beta

`shadow-update.json` расширить так, чтобы хранить обе ветки, сохранив обратную
совместимость со сборками, читающими плоские поля (`build`, `version`, `title`,
`notes`, `url`, `ipa_url`). Пример:

```json
{
  "enabled": true,
  "minimum_build": 0,
  "stable": { "build": 34732, "version": "12.9.2-1.0.0", "title": "…", "notes": "…", "url": "…", "ipa_url": "…" },
  "beta":   { "build": 34740, "version": "12.9.2-1.0.1", "title": "…", "notes": "…", "url": "…", "ipa_url": "…" },
  "build": 34732, "version": "12.9.2-1.0.0", "title": "…", "notes": "…", "url": "…", "ipa_url": "…"
}
```

Плоские поля вверху дублируют `stable` — для старых сборок.

- `ShadowUpdateCheck.parseManifest` — если есть `stable`/`beta`, читать их;
  иначе плоские поля (как сейчас).
- Настройка «Бета-версии» в `AyuGramSettings` (bool, по умолчанию off) — по
  чек-листу настроек из `SHADOW_AGENT_MAP.md` §4 (поле, default, init, encode,
  decode; перенос в `ShadowSettingsDocument`/`Transfer`; UI; тест). Тумблер
  показать в хабе рядом с кнопкой обновления или в «Разное».
- Выбор ветки: если «Бета» включена и `beta.build` новее установленного —
  предлагать бету; иначе stable. В статусе и на кнопке «Скачать» показывать
  версию и пометку «Бета — может работать нестабильно».
- Любой пользователь может включить бету сам (так хочет владелец). Админ-панели
  для выкладки релизов не делать: ветку объявляют правкой `shadow-update.json`
  (номер сборки + тип). Это ручная правка файла в tgfork, как сейчас объявление.
- Контракт-тест на `parseManifest` с обеими ветками и с плоским форматом.

## 3. Автокоммит вайтлиста (через воркер)

Цель: из админ-меню «Доступ устройств» кнопки «Добавить»/«Удалить» и кнопки
«Одобрить» в сообщении бота сразу коммитят `shadow-whitelist.json` в
`folzy1092/tgfork`, без ручного копирования JSON.

Воркер (`tools/shadow-bot/worker.js`), новые эндпоинты:
- `POST /admin` — тело `{ action: "add"|"remove", id, note?, telegram_id, auth }`.
  Воркер проверяет, что `telegram_id` ∈ админов (owner + matey), сверяет общий
  секрет `auth` (новый секрет воркера `ADMIN_SECRET`, он же зашит в приложение
  или задаётся в настройках), читает `shadow-whitelist.json` через GitHub
  Contents API, меняет массив `devices`, коммитит обратно с `[skip ci]`.
- Кнопка «Одобрить» в сообщении о запросе доступа (callback_query): воркер на
  апдейты Telegram (`POST /telegram` как webhook, либо отдельный путь) —
  добавляет устройство в вайтлист тем же путём. Потребуется `setWebhook` у бота
  и обработка `callback_query` в воркере.

Новые секреты воркера: `GITHUB_TOKEN` (fine-grained, Contents: read/write ТОЛЬКО
на `folzy1092/tgfork`), `ADMIN_SECRET`, и если делаешь кнопку «Одобрить» —
`WEBHOOK_SECRET` + вызвать `setWebhook`.

Приложение (`ShadowDeviceAccessController.swift`):
- добавить `adminURL` в `ShadowDeviceAccess` (эндпоинт `/admin` воркера; можно
  выводить из `requestURL`, заменив путь, или отдельным полем `admin_url` в
  вайтлисте);
- «Добавить в список» и «Удалить из списка» шлют `POST /admin` с текущим
  `telegram_id` активного аккаунта и секретом; при успехе показывают тост
  «Сохранено», при ошибке — «Не удалось, скопируй JSON вручную» (ручной путь
  через GitHub оставить как запасной);
- `ADMIN_SECRET` держать в Keychain/настройках, не в коде репозитория.

Обнови `tools/shadow-bot/README.md` под новые секреты и шаги. Контракт-тесты
обнови/добавь. Changelog: добавь запись для сборки, которая выйдет (посчитай
номер = число коммитов после твоего + 3730; сверься с релизами). После пуша
дождись диагностики и полной сборки на CI; ошибки типов видны только в полной
сборке (~45 мин). Объявляй сборку правкой `shadow-update.json` в tgfork И в
Shadow (старые сборки читают Shadow) — по указанию владельца.

## Порядок и безопасность

Делай по одному пункту, отдельными коммитами, после каждого гоняй
`PYTHONUTF8=1 python -B -m unittest discover -s Tests/ShadowSettings -p 'test_*.py'`
и `Tests/ShadowVisualSettings`, `Tests/ShadowCI`. Пункт 1 — самый простой,
начни с него. Пункт 3 трогает секреты: токен GitHub и `ADMIN_SECRET` только в
секретах воркера и в Keychain приложения, никогда в git. Токен выписывать строго
на `folzy1092/tgfork` с правом Contents.

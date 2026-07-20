# Установка форка на iPhone — кратко

На реальное устройство нужна **своя подпись** (Apple ID). `fake-codesigning` —
только для симулятора. Есть два пути.

## Что нужно один раз
- iPhone с iOS, кабель, доверенный компьютер (Mac).
- Apple ID (бесплатный подойдёт) или платный Apple Developer ($99/год).
- Bundle id форка (`ph.telegra.Telegra`), team id, а также `api_id`/`api_hash`
  уже прописаны в версионируемом `build-system/shadow-configuration.json` —
  менять что-либо перед пересборкой **не нужно**, всё подставляется автоматически.
  При необходимости поменять только `team_id` под свой аккаунт:
  ```json
  "bundle_id": "ph.telegra.Telegra",
  "team_id":   "<TEAM_ID из developer.apple.com → Membership>"
  ```
  Если хочешь держать секреты вне git — скопируй файл в
  `build-system/personal-configuration.json` (он в `.gitignore`) и указывай его
  в `--configurationPath` вместо shadow-configuration.json.

---

## Путь A — бесплатный Apple ID (проще, но переустановка раз в 7 дней)

У Telegram много расширений (виджет, уведомления, share…), а бесплатный аккаунт
их плохо подписывает — поэтому отключаем их и подписываем в Xcode автоматически.

1. Сгенерировать Xcode-проект без расширений и без готовых профилей:
   ```sh
   python3 build-system/Make/Make.py --overrideXcodeVersion \
     --cacheDir "$HOME/telegram-bazel-cache" \
     generateProject \
     --configurationPath build-system/shadow-configuration.json \
     --codesigningInformationPath build-system/fake-codesigning \
     --disableExtensions --disableProvisioningProfiles
   ```
2. Открыть сгенерированный `Telegram.xcodeproj` в Xcode.
3. Target **Telegram** → вкладка **Signing & Capabilities**:
   - **Automatically manage signing** = вкл,
   - **Team** = твой Apple ID,
   - **Bundle Identifier** = тот же `ph.telegra.Telegra` (из shadow-configuration.json).
4. Подключить iPhone, выбрать его в списке устройств, нажать **Run** (▶).
5. На iPhone: **Настройки → Основные → VPN и управление устройством** → доверять
   своему developer-сертификату.

⚠️ Бесплатная подпись живёт **7 дней** — через неделю приложение перестанет
запускаться, нужно снова нажать Run в Xcode (данные сохраняются).

---

## Путь B — платный Apple Developer ($99/год, «поставил и забыл» на год)

1. На <https://developer.apple.com> создать App ID и **development
   provisioning profile** под свой `bundle_id` (+ профили для расширений, если
   не отключать их), скачать `.mobileprovision`, сложить их в папку, например
   `~/telegram-signing/profiles`, а сертификат `.p12` — в `~/telegram-signing/certs`.
2. Собрать device-IPA:
   ```sh
   python3 build-system/Make/Make.py --overrideXcodeVersion \
     --cacheDir "$HOME/telegram-bazel-cache" \
     build \
     --configurationPath build-system/shadow-configuration.json \
     --codesigningInformationPath ~/telegram-signing \
     --buildNumber=1 --configuration=debug_arm64 \
     --outputBuildArtifactsPath ~/telegram-ipa
   ```
3. Установить готовый `.ipa` на iPhone любым способом:
   - **Xcode → Window → Devices and Simulators** → выбрать iPhone → «+» →
     указать `.ipa`; или
   - **Apple Configurator** (перетащить `.ipa` на устройство).

Профиль живёт год — переустановка не нужна, пока не истечёт.

---

## Примечания
- Сборка под симулятор (`--configuration=debug_sim_arm64` + `fake-codesigning`)
  на iPhone **не ставится** — она только для отладки на Mac.
- Bundle id `ph.telegra.Telegra` зафиксирован в `shadow-configuration.json` и
  подставляется автоматически при каждой сборке/подписи — ручной правки перед
  пересборкой не требуется.
- `api_id`/`api_hash` уже прописаны в `shadow-configuration.json` — на устройстве
  и перед сборкой менять не нужно.
- Отпечаток «Telegram Desktop / Windows» включён в коде и работает одинаково в
  любой сборке (см. `AYUGRAM_FORK.md` §8).

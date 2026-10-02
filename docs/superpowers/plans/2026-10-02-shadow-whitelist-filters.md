# Shadow: вайтлист, кнопка обновления, фильтры — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** вайтлист устройств с админ-меню, крупная кнопка обновления и точные
патч-ноуты, фильтры сообщений как в AyuGram Desktop.

**Architecture:** чистая логика — Foundation-only файлы в
`TelegramCore/Sources/AyuGram/` с Swift-тестами (`build-system/ci/test_shadow_foundation.py`,
гоняются в CI на macOS); UI — `SettingsUI` / `TelegramUI`; контракты —
Python-тесты, читающие исходники как текст.

**Tech Stack:** Swift, AsyncDisplayKit/ItemListUI, SwiftSignalKit, Security (Keychain), Python unittest.

Спек: `docs/specs/2026-10-02-shadow-whitelist-filters.md`.

## Global Constraints

- Ветка `master`, пуш в remote `ghostgram`.
- `swiftc` на Windows нет: Swift-тесты пишутся сейчас, выполняются в CI
  (`shadow-diagnostics.yml`/`build.yml`). Локально — только Python:
  `PYTHONUTF8=1 python -B -m unittest discover -s Tests/ShadowSettings -p 'test_*.py'`
  и то же для `Tests/ShadowVisualSettings`, `Tests/ShadowCI`.
- TelegramCore не импортирует UIKit/Display.
- Чтение настроек в UI — `ayuGramSettings(postbox:)`, в истории чата —
  `currentAyuGramSettings(accountId:)` (как сейчас).
- Админ Telegram ID: `7878830498`.
- Whitelist URL: `https://raw.githubusercontent.com/folzy1092/Shadow/master/shadow-whitelist.json`.
- Тексты UI — по-русски.

---

### Task 1: Ядро вайтлиста `ShadowDeviceAccess`

**Files:**
- Create: `submodules/TelegramCore/Sources/AyuGram/ShadowDeviceAccess.swift`
- Create: `Tests/ShadowSettings/DeviceAccessTests.swift`
- Modify: `build-system/ci/test_shadow_foundation.py` (добавить case)

**Interfaces — Produces:**
```swift
public enum ShadowDeviceAccess {
    public static let adminPeerId: Int64 = 7878830498
    public static let whitelistURL: URL
    public static let editURL: URL   // github.com/folzy1092/Shadow/edit/master/shadow-whitelist.json
    public struct Device: Equatable { public let id: String; public let note: String }
    public struct Whitelist: Equatable { public let enabled: Bool; public let devices: [Device] }
    public enum Decision: Equatable { case allowed, denied, unknown }
    public static func normalize(_ id: String) -> String
    public static func parse(_ data: Data) -> Whitelist?
    public static func decide(deviceId: String, whitelist: Whitelist?) -> Decision
    public static func encode(_ whitelist: Whitelist) -> String   // pretty JSON для админ-меню
    public static var deviceId: String { get }   // Keychain, создаётся при первом обращении
    public static var cachedWhitelist: Whitelist? { get }   // с диска
    public static func refresh(completion: @escaping (Whitelist?) -> Void)  // main queue, nil = ошибка сети
}
```

- [ ] **Step 1: тест** `Tests/ShadowSettings/DeviceAccessTests.swift`:
```swift
import Foundation

@main
struct DeviceAccessTests {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            count += 1
        }
        check(ShadowDeviceAccess.normalize(" ab12-cd34 ") == "AB12-CD34", "Normalize trims and uppercases")
        let json = """
        {"enabled":true,"devices":[{"id":"ab12-cd34-ef56-7890","note":"мой"},{"id":" "},{"note":"без id"}]}
        """
        let list = ShadowDeviceAccess.parse(Data(json.utf8))
        check(list?.enabled == true, "Enabled parsed")
        check(list?.devices.map { $0.id } == ["AB12-CD34-EF56-7890"], "Blank and missing ids dropped")
        check(list?.devices.first?.note == "мой", "Note kept")
        check(ShadowDeviceAccess.parse(Data("nope".utf8)) == nil, "Malformed JSON")
        check(ShadowDeviceAccess.parse(Data("{\"devices\":[]}".utf8))?.enabled == true, "Enabled by default")

        check(ShadowDeviceAccess.decide(deviceId: "ab12-cd34-ef56-7890", whitelist: list) == .allowed, "Listed device allowed, case-insensitive")
        check(ShadowDeviceAccess.decide(deviceId: "FFFF-0000-0000-0000", whitelist: list) == .denied, "Unlisted device denied")
        check(ShadowDeviceAccess.decide(deviceId: "FFFF-0000-0000-0000", whitelist: nil) == .unknown, "No list yet")
        let off = ShadowDeviceAccess.Whitelist(enabled: false, devices: [])
        check(ShadowDeviceAccess.decide(deviceId: "X", whitelist: off) == .allowed, "Disabled list lets everyone in")

        if let list {
            check(ShadowDeviceAccess.parse(Data(ShadowDeviceAccess.encode(list).utf8)) == list, "Encode round-trip")
        }
        print("Shadow device access: \(count) checks passed")
    }
}
```
- [ ] **Step 2:** добавить в `cases` скрипта
  `('device-access', 'submodules/TelegramCore/Sources/AyuGram/ShadowDeviceAccess.swift', 'Tests/ShadowSettings/DeviceAccessTests.swift'),`.
- [ ] **Step 3: реализация** `ShadowDeviceAccess.swift`:
```swift
import Foundation
import Security

// Shadow: device whitelist. The app makes up its own device id (UDID is not
// readable by apps), keeps it in the Keychain so it survives reinstalls signed
// by the same team, and compares it with shadow-whitelist.json on master.
public enum ShadowDeviceAccess {
    public static let adminPeerId: Int64 = 7878830498
    public static let whitelistURL = URL(string: "https://raw.githubusercontent.com/folzy1092/Shadow/master/shadow-whitelist.json")!
    public static let editURL = URL(string: "https://github.com/folzy1092/Shadow/edit/master/shadow-whitelist.json")!

    public struct Device: Equatable {
        public let id: String
        public let note: String
        public init(id: String, note: String) {
            self.id = ShadowDeviceAccess.normalize(id)
            self.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    public struct Whitelist: Equatable {
        public let enabled: Bool
        public let devices: [Device]
        public init(enabled: Bool, devices: [Device]) {
            self.enabled = enabled
            self.devices = devices
        }
    }

    public enum Decision: Equatable {
        case allowed
        case denied
        case unknown
    }

    public static func normalize(_ id: String) -> String {
        return id.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    public static func parse(_ data: Data) -> Whitelist? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let enabled = (object["enabled"] as? Bool) ?? true
        var devices: [Device] = []
        for entry in (object["devices"] as? [[String: Any]]) ?? [] {
            guard let id = entry["id"] as? String, !normalize(id).isEmpty else {
                continue
            }
            devices.append(Device(id: id, note: (entry["note"] as? String) ?? ""))
        }
        return Whitelist(enabled: enabled, devices: devices)
    }

    public static func decide(deviceId: String, whitelist: Whitelist?) -> Decision {
        guard let whitelist else {
            return .unknown
        }
        if !whitelist.enabled {
            return .allowed
        }
        let id = normalize(deviceId)
        return whitelist.devices.contains(where: { $0.id == id }) ? .allowed : .denied
    }

    public static func encode(_ whitelist: Whitelist) -> String {
        let object: [String: Any] = [
            "enabled": whitelist.enabled,
            "devices": whitelist.devices.map { ["id": $0.id, "note": $0.note] }
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            return "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Device id (Keychain)

    private static let keychainService = "shadow.device-access"
    private static let keychainAccount = "device-id"
    private static let lock = NSLock()
    private static var cachedDeviceId: String?

    public static var deviceId: String {
        lock.lock()
        defer { lock.unlock() }
        if let cachedDeviceId {
            return cachedDeviceId
        }
        let value = readKeychain() ?? {
            let raw = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16)
            var groups: [String] = []
            var index = raw.startIndex
            while index < raw.endIndex {
                let end = raw.index(index, offsetBy: 4)
                groups.append(String(raw[index ..< end]))
                index = end
            }
            let generated = groups.joined(separator: "-")
            writeKeychain(generated)
            return generated
        }()
        cachedDeviceId = value
        return value
    }

    private static func baseQuery() -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
    }

    private static func readKeychain() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        let value = normalize(String(decoding: data, as: UTF8.self))
        return value.isEmpty ? nil : value
    }

    private static func writeKeychain(_ value: String) {
        var query = baseQuery()
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    // MARK: - Whitelist cache and fetch

    private static var cacheURL: URL? {
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("shadow-whitelist-cache.json")
    }

    public static var cachedWhitelist: Whitelist? {
        guard let url = cacheURL, let data = try? Data(contentsOf: url) else {
            return nil
        }
        return parse(data)
    }

    public static func refresh(completion: @escaping (Whitelist?) -> Void) {
        var request = URLRequest(url: whitelistURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15.0
        URLSession.shared.dataTask(with: request) { data, response, error in
            var result: Whitelist?
            if error == nil, let status = (response as? HTTPURLResponse)?.statusCode, (200 ..< 300).contains(status), let data, let list = parse(data) {
                result = list
                if let url = cacheURL {
                    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? data.write(to: url, options: .atomic)
                }
            }
            DispatchQueue.main.async {
                completion(result)
            }
        }.resume()
    }
}
```
- [ ] **Step 4:** проверить, что Swift-тест компилируется в CI (локально `swiftc` нет — проверка в Task 9 через диагностику).
- [ ] **Step 5: commit** `Shadow: device whitelist core (Keychain id, parse, decide)`.

### Task 2: Заглушка доступа и подключение в AppDelegate

**Files:**
- Create: `submodules/TelegramUI/Sources/ShadowDeviceAccessUI.swift`
- Modify: `submodules/TelegramUI/Sources/AppDelegate.swift` (после создания `self.window` ~строка 418; `applicationDidBecomeActive` ~строка 2037)
- Create: `Tests/ShadowSettings/test_device_access_contracts.py`

**Interfaces:**
- Consumes: `ShadowDeviceAccess.deviceId`, `.cachedWhitelist`, `.refresh`, `.decide`, `.adminPeerId`.
- Produces: `final class ShadowDeviceAccessGate { init(windowScene: UIWindowScene?, adminLoggedIn: @escaping () -> Bool); func check(force: Bool) }`.

- [ ] **Step 1: контракт-тест** (падает, файлов ещё нет):
```python
"""Source contracts for the device whitelist gate."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SUB = ROOT / "submodules"


def read(path):
    return (SUB / path).read_text(encoding="utf-8")


class DeviceAccessContracts(unittest.TestCase):
    def test_keychain_item_is_silent_and_device_only(self):
        core = read("TelegramCore/Sources/AyuGram/ShadowDeviceAccess.swift")
        self.assertIn("kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly", core)
        self.assertNotIn("SecAccessControl", core)
        self.assertIn("public static let adminPeerId: Int64 = 7878830498", core)

    def test_gate_is_installed_at_launch_and_on_activation(self):
        app = read("TelegramUI/Sources/AppDelegate.swift")
        self.assertIn("ShadowDeviceAccessGate(", app)
        self.assertIn("self.shadowDeviceAccessGate?.check(force: false)", app)

    def test_gate_has_admin_bypass_and_copy(self):
        ui = read("TelegramUI/Sources/ShadowDeviceAccessUI.swift")
        self.assertIn("Доступ ограничен", ui)
        self.assertIn("UIPasteboard.general.string = ShadowDeviceAccess.deviceId", ui)
        self.assertIn("self.adminLoggedIn()", ui)

    def test_whitelist_file_exists_and_skips_ci(self):
        self.assertTrue((ROOT / "shadow-whitelist.json").exists())
        workflow = (ROOT / ".github/workflows/build.yml").read_text(encoding="utf-8")
        self.assertIn("shadow-whitelist.json", workflow)

    def test_foundation_suite_compiles_device_access(self):
        script = (ROOT / "build-system/ci/test_shadow_foundation.py").read_text(encoding="utf-8")
        self.assertIn("Tests/ShadowSettings/DeviceAccessTests.swift", script)


if __name__ == "__main__":
    unittest.main()
```
- [ ] **Step 2: `ShadowDeviceAccessUI.swift`** — отдельный `UIWindow` уровня `.alert + 10`
  поверх всего (не зависит от контроллеров Telegram, перекрывает и экран входа,
  и список чатов). Логика `check(force:)`:
  - `adminLoggedIn()` → скрыть окно, выйти;
  - решение по кэшу: `.allowed` → скрыть; `.denied` → показать «Доступ ограничен»;
    `.unknown` → показать «Проверка доступа…»;
  - если `force` или прошло ≥ 600 с с прошлого запроса — `refresh`; ответ `nil`
    оставляет решение по кэшу (если кэша нет — текст «Нет связи…»),
    иначе — новое решение.
  Экран: чёрный фон, иконка замка (SF Symbol `lock.fill`), заголовок,
  пояснение, ID моноширинным 22pt, кнопки «Скопировать ID»
  (`UIPasteboard.general.string = ShadowDeviceAccess.deviceId`) и «Проверить снова» (`check(force: true)`).
  Ключевые части:
```swift
import Foundation
import UIKit
import TelegramCore

// Shadow: full-screen gate for devices missing from shadow-whitelist.json.
// Lives in its own window so it covers both the auth flow and the main UI.
final class ShadowDeviceAccessGate {
    private let windowScene: UIWindowScene?
    private let adminLoggedIn: () -> Bool
    private var window: UIWindow?
    private var lastFetch: Date?
    private var fetching = false

    init(windowScene: UIWindowScene?, adminLoggedIn: @escaping () -> Bool) {
        self.windowScene = windowScene
        self.adminLoggedIn = adminLoggedIn
    }

    func check(force: Bool) {
        if self.adminLoggedIn() {
            self.hide()
            return
        }
        self.apply(ShadowDeviceAccess.decide(deviceId: ShadowDeviceAccess.deviceId, whitelist: ShadowDeviceAccess.cachedWhitelist), offline: false)
        if self.fetching {
            return
        }
        if !force, let lastFetch = self.lastFetch, Date().timeIntervalSince(lastFetch) < 600.0 {
            return
        }
        self.fetching = true
        ShadowDeviceAccess.refresh { [weak self] whitelist in
            guard let self else { return }
            self.fetching = false
            self.lastFetch = Date()
            if self.adminLoggedIn() {
                self.hide()
                return
            }
            if let whitelist {
                self.apply(ShadowDeviceAccess.decide(deviceId: ShadowDeviceAccess.deviceId, whitelist: whitelist), offline: false)
            } else {
                self.apply(ShadowDeviceAccess.decide(deviceId: ShadowDeviceAccess.deviceId, whitelist: ShadowDeviceAccess.cachedWhitelist), offline: true)
            }
        }
    }

    private func apply(_ decision: ShadowDeviceAccess.Decision, offline: Bool) {
        switch decision {
        case .allowed:
            self.hide()
        case .denied:
            self.show(title: "Доступ ограничен", text: "Это устройство не в списке разрешённых. Отправь ID владельцу Shadow.")
        case .unknown:
            self.show(title: offline ? "Нет связи" : "Проверка доступа…", text: offline ? "Не удалось проверить доступ. Подключись к интернету и нажми «Проверить снова»." : "Секунду, проверяю, разрешено ли это устройство.")
        }
    }
    // show(title:text:) создаёт/обновляет окно с ShadowDeviceAccessViewController,
    // hide() — window?.isHidden = true; window = nil.
}
```
  `ShadowDeviceAccessViewController: UIViewController` — `UIStackView` по центру
  с элементами выше, кнопки `UIButton(type: .system)` с заливкой
  `UIColor.systemBlue`, высота 50, скругление 12; «Проверить снова» вызывает
  замыкание `retry`. Метод `update(title:text:)`.
- [ ] **Step 3: AppDelegate.** Поле `private var shadowDeviceAccessGate: ShadowDeviceAccessGate?`.
  После `self.nativeWindow = window`:
```swift
        // Shadow: device whitelist gate (ShadowDeviceAccess).
        self.shadowDeviceAccessGate = ShadowDeviceAccessGate(windowScene: window.windowScene, adminLoggedIn: { [weak self] in
            return self?.shadowAdminLoggedIn ?? false
        })
        self.shadowDeviceAccessGate?.check(force: true)
```
  Поле `private var shadowAdminLoggedIn = false`; в месте, где появляется
  `sharedApplicationContext` (подписка на `sharedContextPromise`), подписаться на
  `sharedContext.activeAccountContexts` и выставлять
  `shadowAdminLoggedIn = accounts.contains { $0.1.account.peerId.id._internalGetInt64Value() == ShadowDeviceAccess.adminPeerId }`,
  затем `self.shadowDeviceAccessGate?.check(force: false)`.
  В `applicationDidBecomeActive` после `self.maybeCheckForUpdates()`:
  `self.shadowDeviceAccessGate?.check(force: false)`.
- [ ] **Step 4: `shadow-whitelist.json`** в корне:
```json
{
  "enabled": false,
  "devices": []
}
```
  и в `.github/workflows/build.yml` → `paths-ignore` добавить `- 'shadow-whitelist.json'`
  (то же в `shadow-diagnostics.yml`, если там есть `paths-ignore`).
- [ ] **Step 5:** `PYTHONUTF8=1 python -B -m unittest Tests/ShadowSettings/test_device_access_contracts.py` → PASS.
- [ ] **Step 6: commit** `Shadow: device whitelist gate window`.

### Task 3: Админ-меню «Доступ устройств»

**Files:**
- Create: `submodules/SettingsUI/Sources/ShadowDeviceAccessController.swift`
- Modify: `submodules/SettingsUI/Sources/AyuGramSettingsController.swift` (enum `AyuHubEntry`, сборка entries ~строка 448)
- Modify: `Tests/ShadowSettings/test_device_access_contracts.py`

**Interfaces:** Produces `public func shadowDeviceAccessController(context: AccountContext) -> ViewController`.

- [ ] **Step 1: тест** — добавить в контракт:
```python
    def test_admin_menu_is_last_and_admin_only(self):
        hub = read("SettingsUI/Sources/AyuGramSettingsController.swift")
        self.assertIn("case deviceAccess", hub)
        self.assertIn("context.account.peerId.id._internalGetInt64Value() == ShadowDeviceAccess.adminPeerId", hub)
        admin = read("SettingsUI/Sources/ShadowDeviceAccessController.swift")
        self.assertIn("ShadowDeviceAccess.encode(", admin)
        self.assertIn("ShadowDeviceAccess.editURL", admin)
```
- [ ] **Step 2: контроллер** (ItemListController, style `.blocks`). Состояние:
  `remote: Whitelist?` (загружается `refresh`, при ошибке — `cachedWhitelist`),
  `draft: [Device]?` (nil = как remote), `enabled: Bool`, `newId`, `newNote`.
  Секции и entries:
  1. «Это устройство»: `ItemListDisclosureItem` с ID, тап — копировать + toast `UndoOverlayController(.copy(text: "ID скопирован"))`.
  2. «Список» : `ItemListSwitchItem` «Проверка включена» (`enabled`);
     по строке на устройство — `ItemListTextWithLabelItem(label: note.isEmpty ? "без заметки" : note, text: id)` с
     `ItemListEditableItem`-удалением через `setPeerIdWithRevealedOptions`
     не нужно — проще: тап по строке → action sheet «Удалить из списка».
     Статус загрузки — `ItemListTextItem` («Загружаю…», «Не удалось загрузить, показан кэш»).
  3. «Добавить»: `ItemListSingleLineInputItem` «ID устройства», `ItemListSingleLineInputItem` «Заметка», `ItemListActionItem` «Добавить» (нормализует, не дублирует).
  4. «Сохранить»: `ItemListActionItem` «Скопировать JSON» → `UIPasteboard.general.string = ShadowDeviceAccess.encode(Whitelist(enabled:, devices:))` + toast;
     `ItemListActionItem` «Открыть на GitHub» → `context.sharedContext.applicationBindings.openUrl(ShadowDeviceAccess.editURL.absoluteString)`;
     `ItemListTextItem`: «Вставь JSON в файл и нажми Commit. Приложения подхватят список в течение ~5–10 минут.»
- [ ] **Step 3: хаб.** В `AyuHubEntry` добавить `case deviceAccess` (секция `info`, после `.checkUpdates`-удаления — последним),
  `ItemListDisclosureItem(title: "Доступ устройств", label: "", …)`, переход — `pushControllerImpl?(shadowDeviceAccessController(context: context))`.
  В `entries +=` добавлять `.deviceAccess` последним, только если
  `context.account.peerId.id._internalGetInt64Value() == ShadowDeviceAccess.adminPeerId`.
  Дополнить `stableId`, `<` и `==` по образцу соседних case.
- [ ] **Step 4:** контракт-тесты PASS. **Commit** `Shadow: admin device access menu`.

### Task 4: Патч-ноуты и кнопка обновления наверху хаба

**Files:**
- Modify: `submodules/TelegramCore/Sources/AyuGram/ShadowUpdateCheck.swift` (`changes`)
- Modify: `Tests/ShadowSettings/UpdateCheckTests.swift`
- Create: `submodules/SettingsUI/Sources/ShadowBigButtonItem.swift`
- Modify: `submodules/SettingsUI/Sources/AyuGramSettingsController.swift` (~строки 80–130, 386–450)
- Create: `Tests/ShadowSettings/test_update_button_contracts.py`

**Interfaces:**
- Produces: `ShadowBigButtonItem(presentationData: ItemListPresentationData, title: String, enabled: Bool, sectionId: ItemListSectionId, action: @escaping () -> Void)`.

- [ ] **Step 1: Swift-тест** — в `UpdateCheckTests.swift` перед `print`:
```swift
        check(ShadowUpdateCheck.changes(installedBuild: nil, announcedBuild: 34703, entries: entries).map { $0.build } == [34703], "Unknown installed build shows only the announced entry")
        check(ShadowUpdateCheck.changes(installedBuild: 34700, announcedBuild: 34703, entries: entries).map { $0.build } == [34703], "One skipped build — one entry")
```
- [ ] **Step 2: `changes`:**
```swift
    // Entries newer than the installed build and not newer than the announced one.
    // Unknown installed build (re-signed IPA without a numeric CFBundleVersion):
    // only the announced entry, never the whole history.
    public static func changes(installedBuild: Int?, announcedBuild: Int, entries: [ChangelogEntry]) -> [ChangelogEntry] {
        guard let installedBuild else {
            return entries.filter { $0.build == announcedBuild }
        }
        return entries.filter { entry in
            entry.build <= announcedBuild && entry.build > installedBuild
        }
    }
```
- [ ] **Step 3: `ShadowBigButtonItem.swift`** — `ListViewItem, ItemListItem` по образцу
  `ItemListPlaceholderItem` (async layout, `itemListNeighborsGroupedInsets`),
  внутри `SolidRoundedButtonNode(theme: SolidRoundedButtonTheme(backgroundColor: theme.list.itemCheckColors.fillColor, foregroundColor: theme.list.itemCheckColors.foregroundColor), height: 50.0, cornerRadius: 12.0)`,
  прозрачный фон (без блока), ширина `params.width - 32 - insets`, высота 50 + 8 сверху/снизу.
  `enabled == false` → `buttonNode.isEnabled = false` (кнопка в неактивном
  состоянии, текст тот же). `selectable = false`. `buttonNode.pressed = item.action`.
  Импорт `SolidRoundedButtonNode` уже есть в зависимостях SettingsUI
  (`DeleteAccountFooterItem.swift`).
- [ ] **Step 4: хаб.** Заменить `updateBanner(title:text:)` и `checkUpdates(label:enabled:)` на:
  - `case updateButton(enabled: Bool)` → `ShadowBigButtonItem(title: "Проверить обновления", …)` — секция `updateBanner`, **всегда первым**;
  - `case updateStatus(String)` → `ItemListTextItem` под кнопкой (текст статуса);
  - `case downloadButton(String, URL)` → `ShadowBigButtonItem(title: "Скачать IPA (\(build))")`, тап — `arguments.openUrl(url.absoluteString)`;
  - `case updateNotes(title: String, text: String)` → прежний `ItemListInfoItem` с крестиком (`dismissUpdateBanner`), без ссылки «Скачать IPA» в тексте.
  Тексты статуса:
  - idle: `"Установлена сборка \(installed)"`;
  - checking: `"Проверяю…"`, кнопка disabled;
  - upToDate: `"Актуально · сборка \(installed)"`;
  - available: `"У тебя \(installed) → доступна \(release.build)"` + (если `release.changelog.count > 1`) `", пропущено \(release.changelog.count) обновлений"`; при `isRequired` — префикс `"Обязательное. "`;
  - failed: `"Не удалось проверить: \(reason)"`.
  Патч-ноуты: заголовок `release.title`; по блоку на сборку (`"Сборка N · дата:\n• …"`),
  максимум 5 блоков, далее `"…и ещё \(rest) сборок"`; без обрезки по символам.
  Удалить `.checkUpdates` из конца хаба и enum `AyuHubSection.updateCheck`.
- [ ] **Step 5: контракт-тест** `test_update_button_contracts.py`:
```python
"""Source contracts for the update button at the top of the Shadow hub."""
from pathlib import Path
import unittest

SUB = Path(__file__).resolve().parents[2] / "submodules"


class UpdateButtonContracts(unittest.TestCase):
    def test_button_is_first_and_label_is_static(self):
        hub = (SUB / "SettingsUI/Sources/AyuGramSettingsController.swift").read_text(encoding="utf-8")
        self.assertIn('ShadowBigButtonItem(presentationData: presentationData, title: "Проверить обновления"', hub)
        self.assertIn("case updateStatus(String)", hub)
        self.assertIn("case downloadButton(", hub)
        self.assertNotIn("case checkUpdates(", hub)
        self.assertNotIn("[Скачать IPA]", hub)
        first = hub.index("var entries: [AyuHubEntry] = [.updateButton(")
        self.assertLess(first, hub.index("entries.append(.query(query))"))

    def test_unknown_build_does_not_show_history(self):
        core = (SUB / "TelegramCore/Sources/AyuGram/ShadowUpdateCheck.swift").read_text(encoding="utf-8")
        self.assertIn("return entries.filter { $0.build == announcedBuild }", core)


if __name__ == "__main__":
    unittest.main()
```
- [ ] **Step 6:** все Python-контракты PASS (поправить старые, если проверяли `checkUpdates`). **Commit** `Shadow: big update button on top of the hub, per-build notes`.

### Task 5: Модель фильтров и миграция

**Files:**
- Create: `submodules/TelegramCore/Sources/AyuGram/ShadowMessageFilters.swift`
- Create: `Tests/ShadowSettings/MessageFiltersTests.swift`
- Modify: `build-system/ci/test_shadow_foundation.py`
- Modify: `submodules/TelegramCore/Sources/AyuGram/AyuGramSettings.swift` (строки 92, 434–440, 545, 606, 625, 711)
- Modify: `submodules/TelegramCore/Sources/AyuGram/ShadowSettingsDocument.swift`, `ShadowSettingsTransfer.swift` (только bool `messageFilterShowPlaceholder`)
- Modify: `Tests/ShadowSettings/DocumentTests.swift`

**Interfaces — Produces:**
```swift
public struct ShadowMessageFilter: Codable, Equatable {
    public var id: Int64
    public var expression: String
    public var enabled: Bool
    public var caseInsensitive: Bool
    public var reversed: Bool
    public init(id: Int64, expression: String, enabled: Bool = true, caseInsensitive: Bool = true, reversed: Bool = false)
    public static func isValid(expression: String) -> Bool
    public static func escaped(_ text: String) -> String     // NSRegularExpression.escapedPattern
    public static func migrated(phrases: [String]) -> [ShadowMessageFilter]
}
public final class ShadowMessageFilterMatcher {
    public init(filters: [ShadowMessageFilter])
    public var isEmpty: Bool { get }
    public func hides(text: String) -> Bool
}
// AyuGramSettings:
public var messageFilters: [ShadowMessageFilter]
public var messageFilterShowPlaceholder: Bool   // default true
public func matchesMessageFilter(text: String) -> Bool  // через кэшированный matcher
```

- [ ] **Step 1: Swift-тест** `MessageFiltersTests.swift`:
```swift
import Foundation

@main
struct MessageFiltersTests {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            count += 1
        }
        check(ShadowMessageFilter.isValid(expression: "реклама|@alfa\\w+"), "Valid regex")
        check(!ShadowMessageFilter.isValid(expression: "(unclosed"), "Invalid regex")
        check(!ShadowMessageFilter.isValid(expression: "  "), "Blank expression")

        let plain = ShadowMessageFilter(id: 1, expression: "реклама")
        check(ShadowMessageFilterMatcher(filters: [plain]).hides(text: "Тут РЕКЛАМА канала"), "Case-insensitive by default")
        let strict = ShadowMessageFilter(id: 2, expression: "Реклама", caseInsensitive: false)
        check(!ShadowMessageFilterMatcher(filters: [strict]).hides(text: "реклама"), "Case-sensitive")
        let disabled = ShadowMessageFilter(id: 3, expression: "реклама", enabled: false)
        check(!ShadowMessageFilterMatcher(filters: [disabled]).hides(text: "реклама"), "Disabled filter ignored")
        check(ShadowMessageFilterMatcher(filters: [disabled]).isEmpty, "Only disabled filters — empty")
        let reversed = ShadowMessageFilter(id: 4, expression: "важно", reversed: true)
        check(ShadowMessageFilterMatcher(filters: [reversed]).hides(text: "просто текст"), "Reversed hides non-matching")
        check(!ShadowMessageFilterMatcher(filters: [reversed]).hides(text: "это важно"), "Reversed keeps matching")
        let broken = ShadowMessageFilter(id: 5, expression: "(unclosed")
        check(!ShadowMessageFilterMatcher(filters: [broken]).hides(text: "(unclosed"), "Broken regex never matches")

        check(ShadowMessageFilter.escaped("a.b") == "a\\.b", "Escaping")
        let migrated = ShadowMessageFilter.migrated(phrases: ["a.b", " ", "@domrf_bank"])
        check(migrated.map { $0.expression } == ["a\\.b", "@domrf_bank"], "Migration escapes and drops blanks")
        check(migrated.allSatisfy { $0.enabled && $0.caseInsensitive && !$0.reversed }, "Migration defaults")
        check(Set(migrated.map { $0.id }).count == 2, "Migration ids unique")
        check(ShadowMessageFilterMatcher(filters: migrated).hides(text: "пишет @DOMRF_BANK"), "Migrated phrase still matches")

        print("Shadow message filters: \(count) checks passed")
    }
}
```
- [ ] **Step 2:** case в `test_shadow_foundation.py`:
  `('message-filters', 'submodules/TelegramCore/Sources/AyuGram/ShadowMessageFilters.swift', 'Tests/ShadowSettings/MessageFiltersTests.swift'),`.
- [ ] **Step 3: `ShadowMessageFilters.swift`:**
```swift
import Foundation

// Shadow: local message filters, modelled on AyuGram Desktop — a regular
// expression with enabled / case-insensitive / reversed flags. Matching hides
// messages on this device only.
public struct ShadowMessageFilter: Codable, Equatable {
    public var id: Int64
    public var expression: String
    public var enabled: Bool
    public var caseInsensitive: Bool
    public var reversed: Bool

    public init(id: Int64, expression: String, enabled: Bool = true, caseInsensitive: Bool = true, reversed: Bool = false) {
        self.id = id
        self.expression = expression
        self.enabled = enabled
        self.caseInsensitive = caseInsensitive
        self.reversed = reversed
    }

    // Postbox's Codable adapter stores Bool as Int32 elsewhere in AyuGramSettings; keep that here.
    private enum CodingKeys: String, CodingKey {
        case id, expression, enabled, caseInsensitive, reversed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int64.self, forKey: .id)
        self.expression = try container.decode(String.self, forKey: .expression)
        self.enabled = ((try container.decodeIfPresent(Int32.self, forKey: .enabled)) ?? 1) != 0
        self.caseInsensitive = ((try container.decodeIfPresent(Int32.self, forKey: .caseInsensitive)) ?? 1) != 0
        self.reversed = ((try container.decodeIfPresent(Int32.self, forKey: .reversed)) ?? 0) != 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.id, forKey: .id)
        try container.encode(self.expression, forKey: .expression)
        try container.encode((self.enabled ? 1 : 0) as Int32, forKey: .enabled)
        try container.encode((self.caseInsensitive ? 1 : 0) as Int32, forKey: .caseInsensitive)
        try container.encode((self.reversed ? 1 : 0) as Int32, forKey: .reversed)
    }

    public static func isValid(expression: String) -> Bool {
        guard !expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return (try? NSRegularExpression(pattern: expression)) != nil
    }

    public static func escaped(_ text: String) -> String {
        return NSRegularExpression.escapedPattern(for: text)
    }

    public static func migrated(phrases: [String]) -> [ShadowMessageFilter] {
        var result: [ShadowMessageFilter] = []
        for phrase in phrases {
            let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }
            result.append(ShadowMessageFilter(id: Int64(result.count + 1), expression: escaped(trimmed)))
        }
        return result
    }
}

public final class ShadowMessageFilterMatcher {
    private let rules: [(NSRegularExpression, Bool)]

    public init(filters: [ShadowMessageFilter]) {
        self.rules = filters.compactMap { filter in
            guard filter.enabled else {
                return nil
            }
            let options: NSRegularExpression.Options = filter.caseInsensitive ? [.caseInsensitive] : []
            guard let regex = try? NSRegularExpression(pattern: filter.expression, options: options) else {
                return nil
            }
            return (regex, filter.reversed)
        }
    }

    public var isEmpty: Bool {
        return self.rules.isEmpty
    }

    public func hides(text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        for (regex, reversed) in self.rules {
            let found = regex.firstMatch(in: text, options: [], range: range) != nil
            if found != reversed {
                return true
            }
        }
        return false
    }
}
```
- [ ] **Step 4: AyuGramSettings.**
  - Заменить `public var messageFilterPhrases: [String] = []` на
    `public var messageFilters: [ShadowMessageFilter] = []` и
    `public var messageFilterShowPlaceholder: Bool = true`.
  - init-параметр `messageFilterPhrases:` → `messageFilters: [ShadowMessageFilter] = [], messageFilterShowPlaceholder: Bool = true` (поиск вызовов: `grep -rn "messageFilterPhrases:" submodules`).
  - `init(from:)`:
```swift
        if let filters = try? container.decode([ShadowMessageFilter].self, forKey: "messageFiltersV2") {
            self.messageFilters = filters
        } else {
            self.messageFilters = ShadowMessageFilter.migrated(phrases: (try container.decodeIfPresent([String].self, forKey: "messageFilterPhrases")) ?? [])
        }
        self.messageFilterShowPlaceholder = ((try container.decodeIfPresent(Int32.self, forKey: "messageFilterShowPlaceholder")) ?? 1) != 0
```
  - `encode(to:)`: `messageFiltersV2` и `messageFilterShowPlaceholder` (Int32); старый ключ не писать.
  - `matchesMessageFilter(text:)` → через кэш:
```swift
    public func matchesMessageFilter(text: String) -> Bool {
        return shadowMessageFilterMatcher(for: self.messageFilters).hides(text: text)
    }
```
    и рядом (file-private, под `NSLock`) кэш последнего `[ShadowMessageFilter]` → `ShadowMessageFilterMatcher`, чтобы regex не компилировались на каждое сообщение.
- [ ] **Step 5: перенос настроек.** `ShadowSettingsDocument.booleanKeys` += `"messageFilterShowPlaceholder"`;
  в `ShadowSettingsTransfer.swift` добавить key path `\.messageFilterShowPlaceholder`
  по образцу соседних bool. Список фильтров не переносится (документ поддерживает
  только bool/int/text — как и раньше со старыми фразами).
  В `DocumentTests.swift` — round-trip ключа по образцу соседних.
- [ ] **Step 6:** `grep -rn "messageFilterPhrases" submodules` — остались только чтение legacy-ключа и миграция. Python-контракты PASS. **Commit** `Shadow: regex message filters model with migration`.

### Task 6: Экран фильтров, окно добавления, режим скрытия

**Files:**
- Rewrite: `submodules/SettingsUI/Sources/ShadowMessageFiltersController.swift`
- Create: `submodules/SettingsUI/Sources/ShadowMessageFilterEditController.swift`
- Modify: `submodules/TelegramUI/Sources/ChatHistoryEntriesForView.swift:939-963`
- Modify: `submodules/SettingsUI/Sources/ShadowSettingsSearchIndex.swift` (строка «Плашка скрытых фильтром»)
- Create: `Tests/ShadowSettings/test_message_filters_contracts.py`

**Interfaces — Produces:**
```swift
public func shadowMessageFilterEditController(context: AccountContext, filter: ShadowMessageFilter?, initialExpression: String?) -> ViewController
```
(сохраняет сам через `updateAyuGramSettings`; новый id = `max(ids) + 1`).

- [ ] **Step 1: контракт-тест:**
```python
"""Source contracts for AyuGram-style message filters."""
from pathlib import Path
import unittest

SUB = Path(__file__).resolve().parents[2] / "submodules"


def read(path):
    return (SUB / path).read_text(encoding="utf-8")


class MessageFiltersContracts(unittest.TestCase):
    def test_edit_dialog_matches_desktop(self):
        edit = read("SettingsUI/Sources/ShadowMessageFilterEditController.swift")
        for title in ("Выражение", "Включить фильтр", "Без учёта регистра", "Обратный фильтр", "Сохранить"):
            self.assertIn(title, edit)
        self.assertIn("ShadowMessageFilter.isValid(expression:", edit)

    def test_list_has_placeholder_toggle(self):
        screen = read("SettingsUI/Sources/ShadowMessageFiltersController.swift")
        self.assertIn("Скрыто локальным фильтром", screen)
        self.assertIn("messageFilterShowPlaceholder", screen)
        self.assertIn("Добавить фильтр", screen)

    def test_history_hides_completely_when_placeholder_off(self):
        history = read("TelegramUI/Sources/ChatHistoryEntriesForView.swift")
        self.assertIn("shadowSettings.messageFilterShowPlaceholder", history)
        self.assertIn("if !shadowSettings.messageFilters.isEmpty {", history)

    def test_foundation_suite_compiles_filters(self):
        script = (SUB.parent / "build-system/ci/test_shadow_foundation.py").read_text(encoding="utf-8")
        self.assertIn("Tests/ShadowSettings/MessageFiltersTests.swift", script)


if __name__ == "__main__":
    unittest.main()
```
- [ ] **Step 2: окно добавления** (`ShadowMessageFilterEditController.swift`) — `ItemListController`
  с навигацией «Отмена» / «Сохранить» (`ItemListNavigationButton`), заголовок
  «Добавить фильтр» / «Изменить фильтр», показывается модально
  (`ViewControllerPresentationArguments(presentationAnimation: .modalSheet)`).
  Entries: секция «Выражение» с `ItemListSingleLineInputItem` (без автокоррекции и
  автокапитализации); `ItemListTextItem` с ошибкой «Неверное регулярное выражение»,
  если `!isValid`; три `ItemListCheckboxItem` (`style: .left`): «Включить фильтр»,
  «Без учёта регистра», «Обратный фильтр»; подсказка
  «Обычный текст тоже работает. Спецсимволы . * ? ( ) [ ] экранируй \\ или
  добавляй из чата — экранируется само.» «Сохранить» неактивна при невалидном
  выражении; сохраняет (новый — append, существующий — замена по id) и закрывает.
- [ ] **Step 3: экран списка** (`ShadowMessageFiltersController.swift`, переписать):
  - секция 0: `ItemListSwitchItem` «Плашка „Скрыто локальным фильтром“» (`messageFilterShowPlaceholder`),
    `ItemListTextItem`: «Выключено — совпавшие сообщения пропадают из чата полностью.»;
  - секция 1: `ItemListActionItem` «Добавить фильтр» (кнопка с акцентом) → edit-контроллер;
    по `ItemListDisclosureItem` на фильтр: title = expression, label = флаги
    (`"Аа"` если учитывается регистр, `"обратный"`, `"выкл"`), выключенные — `.disabled`-стиль
    (`labelStyle: .text`, титул вторичным цветом нельзя — использовать label «выкл»);
    тап → edit-контроллер с фильтром; удаление — swipe через `ItemListPeerActionItem`
    не подходит, поэтому long-tap не нужен: в edit-контроллере кнопка
    «Удалить фильтр» (destructive) для существующего фильтра.
  - секция 2: `ItemListTextItem` «Совпадения ищутся в тексте и подписях. Скрываются только на этом устройстве; прочтения не отправляются.»
- [ ] **Step 4: история чата** — блок на строках 939–963:
```swift
    let shadowSettings = currentAyuGramSettings(accountId: context.account.id)
    if !shadowSettings.messageFilters.isEmpty {
        let showPlaceholder = shadowSettings.messageFilterShowPlaceholder
        entries = entries.flatMap { entry -> [ChatHistoryEntry] in
            switch entry {
            case let .MessageEntry(message, presentation, isRead, location, selection, attributes):
                guard shadowSettings.matchesMessageFilter(text: message.text) else { return [entry] }
                guard showPlaceholder else { return [] }
                let placeholder = shadowFilteredPlaceholder(message)
                return [.MessageEntry(placeholder, presentation, isRead, location, selection, attributes)]
            case let .MessageGroupEntry(_, messages, presentation):
                // (существующий комментарий про альбомы)
                guard let hiddenItem = messages.first(where: { shadowSettings.matchesMessageFilter(text: $0.0.text) }) else {
                    return [entry]
                }
                guard showPlaceholder else { return [] }
                let (message, isRead, selection, attributes, location) = hiddenItem
                let placeholder = shadowFilteredPlaceholder(message)
                return [.MessageEntry(placeholder, presentation, isRead, location, selection, attributes)]
            default:
                return [entry]
            }
        }
    }
```
  Проверить `shadowFilteredPlaceholder`: текст плашки — «Скрыто локальным фильтром»
  (поправить, если другой).
- [ ] **Step 5:** поиск настроек — обновить запись фильтров в `ShadowSettingsSearchIndex.swift`
  (ключевые слова: «фильтр», «регулярк», «скрыть сообщения», «плашка»). Python PASS.
  **Commit** `Shadow: filters screen and add dialog like AyuGram Desktop`.

### Task 7: «В фильтры» из выделения текста и из меню @username

**Files:**
- Modify: `submodules/TextSelectionNode/Sources/TextSelectionNode.swift` (~строка 770)
- Modify: `submodules/TelegramUI/Components/ChatControllerInteraction/Sources/ChatControllerInteraction.swift` (блок `public var` ~строка 330)
- Modify: `submodules/TelegramUI/Components/Chat/ChatMessageTextBubbleContentNode/Sources/ChatMessageTextBubbleContentNode.swift` (создание `TextSelectionNode`)
- Modify: `submodules/TelegramUI/Sources/ChatController.swift` (после создания `controllerInteraction`)
- Modify: `submodules/TelegramUI/Sources/Chat/ChatControllerOpenUsernameContextMenu.swift` (после пункта «Копировать»)
- Modify: `Tests/ShadowSettings/test_message_filters_contracts.py`

**Interfaces:**
- `TextSelectionNode`: `public var shadowAddToFilter: ((String) -> Void)?` (enum `TextSelectionAction` **не** трогаем — у него 8+ exhaustive switch по проекту).
- `ChatControllerInteraction`: `public var shadowAddMessageFilter: ((String) -> Void)?`.

- [ ] **Step 1: контракт** — добавить в класс:
```python
    def test_quick_add_entry_points(self):
        selection = read("TextSelectionNode/Sources/TextSelectionNode.swift")
        self.assertIn("public var shadowAddToFilter: ((String) -> Void)?", selection)
        self.assertIn('title: "В фильтры"', selection)
        bubble = read("TelegramUI/Components/Chat/ChatMessageTextBubbleContentNode/Sources/ChatMessageTextBubbleContentNode.swift")
        self.assertIn("shadowAddMessageFilter", bubble)
        mention = read("TelegramUI/Sources/Chat/ChatControllerOpenUsernameContextMenu.swift")
        self.assertIn('text: "В фильтры"', mention)
        self.assertIn("ShadowMessageFilter.escaped(", mention)
        chat = read("TelegramUI/Sources/ChatController.swift")
        self.assertIn("controllerInteraction.shadowAddMessageFilter = {", chat)
```
- [ ] **Step 2: TextSelectionNode** — свойство рядом с `enableCopy` и пункт меню сразу после «Копировать»:
```swift
        if let shadowAddToFilter = self.shadowAddToFilter {
            // Shadow: add the selected fragment to local message filters.
            actions.append(ContextMenuAction(content: .text(title: "В фильтры", accessibilityLabel: "В фильтры"), action: { [weak self] in
                shadowAddToFilter(string.string)
                self?.cancelSelection()
            }))
        }
```
- [ ] **Step 3: ChatControllerInteraction** — `public var shadowAddMessageFilter: ((String) -> Void)?` рядом с `canPlayMedia`.
- [ ] **Step 4: ChatMessageTextBubbleContentNode** — там, где создаётся `TextSelectionNode(...)`:
```swift
                    if let shadowAddMessageFilter = item.controllerInteraction.shadowAddMessageFilter {
                        textSelectionNode.shadowAddToFilter = { text in
                            shadowAddMessageFilter(ShadowMessageFilter.escaped(text.trimmingCharacters(in: .whitespacesAndNewlines)))
                        }
                    }
```
  (если модуль не импортирует TelegramCore — он импортирует; проверить `import TelegramCore` в файле.)
- [ ] **Step 5: ChatController** — после присваивания `self.controllerInteraction = controllerInteraction`:
```swift
        // Shadow: "В фильтры" from text selection and mention menus.
        controllerInteraction.shadowAddMessageFilter = { [weak self] expression in
            guard let self else {
                return
            }
            self.chatDisplayNode.dismissInput()
            self.present(shadowMessageFilterEditController(context: self.context, filter: nil, initialExpression: expression), in: .window(.root), with: ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
        }
```
  (`import SettingsUI` в ChatController уже есть? — проверить `grep -n "^import SettingsUI" ChatController.swift`, добавить при отсутствии; зависимость в BUILD есть.)
- [ ] **Step 6: меню @username** — после пункта `Chat_Context_Username_Copy`:
```swift
            // Shadow: hide messages that mention this username.
            items.append(
                .action(ContextMenuActionItem(text: "В фильтры", icon: { theme in return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Hide"), color: theme.contextMenu.primaryColor) }, action: { [weak self] _, f in
                    f(.default)
                    guard let self else {
                        return
                    }
                    let mention = username.hasPrefix("@") ? username : "@" + username
                    self.controllerInteraction?.shadowAddMessageFilter?(ShadowMessageFilter.escaped(mention))
                }))
            )
```
  Перед этим проверить, что ассет `Chat/Context Menu/Hide` существует
  (`ls submodules/TelegramUI/Images.xcassets/Chat/Context\ Menu/ | grep -i hide`);
  если нет — взять существующий (`EyeCrossed`/`Unarchive` и т.п.).
- [ ] **Step 7:** Python PASS. **Commit** `Shadow: add to filters from text selection and @username menu`.

### Task 8: Документация, выпуск, CI

**Files:**
- Modify: `docs/SHADOW_AGENT_MAP.md` (раздел про вайтлист и фильтры)
- Modify: `shadow-changelog.json`, `shadow-update.json`

- [ ] **Step 1:** в `SHADOW_AGENT_MAP.md` добавить подраздел «Вайтлист устройств»: файл `shadow-whitelist.json`, `ShadowDeviceAccess`, окно-заглушка в AppDelegate, админ `7878830498`, `enabled:false` — рубильник.
- [ ] **Step 2:** прогнать всё локально:
  `PYTHONUTF8=1 python -B -m unittest discover -s Tests/ShadowSettings -p 'test_*.py'`,
  `... -s Tests/ShadowVisualSettings ...`, `python -B -m unittest discover -s Tests/ShadowCI`. Всё PASS.
- [ ] **Step 3:** номер сборки = `git rev-list --count HEAD` (после коммита релиза +1) + `build_number_offset`.
  Запись в `shadow-changelog.json` (новая сверху):
  «Вайтлист устройств: доступ только для разрешённых ID», «Большая кнопка
  „Проверить обновления“ наверху настроек Shadow, „Скачать IPA“ отдельной
  кнопкой», «Фильтры как в AyuGram Desktop: регулярки, без учёта регистра,
  обратный; „В фильтры“ из выделения текста и меню @username; можно скрывать
  без плашки». `shadow-update.json` — объявить эту сборку.
- [ ] **Step 4:** commit, `git push ghostgram master`. Дождаться диагностики/сборки
  (`gh run list --repo folzy1092/Shadow -L 3`); ошибки компиляции — чинить
  отдельными коммитами и переобъявлять номер.
- [ ] **Step 5:** после зелёной сборки — сообщить пользователю: поставить IPA,
  открыть админ-меню, скопировать свой ID, заполнить `shadow-whitelist.json`
  и переключить `"enabled": true`.

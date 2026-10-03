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
        # A locked Keychain (background launch before the first unlock) must
        # not mint a new id or delete the stored one.
        self.assertIn("if status == errSecItemNotFound {", core)
        # The device id is never deleted; deletion is only allowed in the
        # admin-secret code (replacing the stored secret).
        self.assertNotIn("SecItemDelete", core.split("MARK: - Admin secret")[0])
        self.assertIn("public static let adminPeerId: Int64 = 7878830498", core)
        self.assertIn("folzy1092/tgfork/main/shadow-whitelist.json", core)
        self.assertIn("github.com/folzy1092/tgfork/edit/main/shadow-whitelist.json", core)

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

    def test_admin_menu_is_last_and_admin_only(self):
        hub = read("SettingsUI/Sources/AyuGramSettingsController.swift")
        self.assertIn("case deviceAccess", hub)
        self.assertIn("let isAdmin = ShadowDeviceAccess.hasAdminAccess(peerId: context.account.peerId.id._internalGetInt64Value())", hub)
        core = read("TelegramCore/Sources/AyuGram/ShadowDeviceAccess.swift")
        self.assertIn("public static let adminPeerIds: Set<Int64> = [adminPeerId, 1068369028]", core)

    def test_gate_does_not_flash_for_accepted_devices(self):
        gate = read("TelegramUI/Sources/ShadowDeviceAccessUI.swift")
        # A stale cached "denied" waits for the server answer.
        self.assertIn("if !fromServer && !self.resolved {", gate)
        # "Checking" appears only if the answer is slow.
        self.assertIn("checkingDelay: TimeInterval = 1.5", gate)
        self.assertIn("self.cancelChecking()", gate)
        core = read("TelegramCore/Sources/AyuGram/ShadowDeviceAccess.swift")
        # Fresh fetch gets past the raw CDN cache.
        self.assertIn('URLQueryItem(name: "t"', core)

    def test_access_request_bot(self):
        gate = read("TelegramUI/Sources/ShadowDeviceAccessUI.swift")
        self.assertIn('"Запросить доступ"', gate)
        self.assertIn("ShadowDeviceAccess.accessRequestBody(", gate)
        worker = (ROOT / "tools/shadow-bot/worker.js").read_text(encoding="utf-8")
        self.assertIn("tg://shadow/access?id=${id}", worker)
        self.assertIn("shadow://access?id=", worker)
        self.assertIn('url.pathname === "/request"', worker)
        admin = read("SettingsUI/Sources/ShadowDeviceAccessController.swift")
        self.assertIn("ShadowDeviceAccess.encode(", admin)
        self.assertIn("ShadowDeviceAccess.editURL", admin)


if __name__ == "__main__":
    unittest.main()

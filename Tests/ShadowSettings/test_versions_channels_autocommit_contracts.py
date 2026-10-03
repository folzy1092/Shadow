"""Contracts for the fork version, stable/beta channels and whitelist autocommit."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SUB = ROOT / "submodules"


def read(path):
    return (SUB / path).read_text(encoding="utf-8")


class VersionContracts(unittest.TestCase):
    def test_fork_version_single_source(self):
        versions = json.loads((ROOT / "versions.json").read_text(encoding="utf-8"))
        self.assertIn("fork", versions)
        core = read("TelegramCore/Sources/AyuGram/ShadowVersion.swift")
        self.assertIn('public static let fork = "%s"' % versions["fork"], core)
        self.assertIn("public static var full: String", core)

    def test_release_title_carries_fork_version(self):
        workflow = (ROOT / ".github/workflows/build.yml").read_text(encoding="utf-8")
        self.assertIn("FORK_VERSION", workflow)
        self.assertIn('--title "Shadow ${APP_VERSION}-${FORK_VERSION} (${BUILD_NUMBER})"', workflow)

    def test_hub_shows_full_version(self):
        hub = read("SettingsUI/Sources/AyuGramSettingsController.swift")
        self.assertIn("ShadowVersion.full", hub)


class ChannelContracts(unittest.TestCase):
    def test_manifest_parses_stable_and_beta(self):
        core = read("TelegramCore/Sources/AyuGram/ShadowUpdateCheck.swift")
        self.assertIn("public static func parseBetaManifest(", core)
        self.assertIn('object["stable"]', core)
        self.assertIn("betaEnabled", core)
        self.assertIn("public let isBeta: Bool", core)

    def test_update_check_busts_cdn_cache(self):
        core = read("TelegramCore/Sources/AyuGram/ShadowUpdateCheck.swift")
        self.assertIn('URLQueryItem(name: "t"', core)

    def test_beta_toggle_and_setting(self):
        settings = read("TelegramCore/Sources/AyuGram/AyuGramSettings.swift")
        self.assertIn("public var updateChannelBeta: Bool = false", settings)
        self.assertIn('forKey: "updateChannelBeta"', settings)
        misc = read("SettingsUI/Sources/ShadowPushDiagnosticsController.swift")
        self.assertIn('"Бета-версии"', misc)
        hub = read("SettingsUI/Sources/AyuGramSettingsController.swift")
        self.assertIn("ShadowUpdateCheck.check(betaEnabled:", hub)


class AutocommitContracts(unittest.TestCase):
    def test_core_has_admin_writes(self):
        core = read("TelegramCore/Sources/AyuGram/ShadowDeviceAccess.swift")
        self.assertIn("public static func saveWhitelist(", core)
        self.assertIn("public static func announce(", core)
        self.assertIn("adminSecret", core)
        self.assertIn('object["admin_url"]', core)
        self.assertIn("public let admin: Bool", core)

    def test_controller_save_and_announce(self):
        admin = read("SettingsUI/Sources/ShadowDeviceAccessController.swift")
        self.assertIn("ShadowDeviceAccess.saveWhitelist(", admin)
        self.assertIn("ShadowDeviceAccess.announce(", admin)
        self.assertIn("ShadowDeviceAccess.setAdminSecret(", admin)
        self.assertIn('"Сделать админом"', admin)
        self.assertIn('"ОБЪЯВИТЬ СБОРКУ"', admin)

    def test_worker_admin_endpoint(self):
        worker = (ROOT / "tools/shadow-bot/worker.js").read_text(encoding="utf-8")
        self.assertIn('url.pathname === "/admin"', worker)
        self.assertIn('"save_whitelist"', worker)
        self.assertIn('"announce"', worker)
        self.assertIn("env.ADMIN_SECRET", worker)
        self.assertIn("env.GITHUB_TOKEN", worker)
        self.assertIn("folzy1092/tgfork", worker)
        self.assertIn("[skip ci]", worker)

    def test_worker_whitelist_endpoint_and_no_accept_button(self):
        worker = (ROOT / "tools/shadow-bot/worker.js").read_text(encoding="utf-8")
        self.assertIn('url.pathname === "/whitelist"', worker)
        self.assertIn('"cache-control": "no-store"', worker)
        self.assertNotIn("callback_data", worker)
        core = read("TelegramCore/Sources/AyuGram/ShadowDeviceAccess.swift")
        self.assertIn("whitelistWorkerURL", core)
        gate = read("TelegramUI/Sources/ShadowDeviceAccessUI.swift")
        self.assertIn("recheckInterval", gate)

    def test_foundation_suite_compiles_version(self):
        script = (ROOT / "build-system/ci/test_shadow_foundation.py").read_text(encoding="utf-8")
        self.assertIn("Tests/ShadowSettings/DeviceAccessTests.swift", script)


if __name__ == "__main__":
    unittest.main()

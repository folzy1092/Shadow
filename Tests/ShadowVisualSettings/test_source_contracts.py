"""Source-level regression checks for account settings and cached tab-bar layout.

Run from the repository root:
    python3 -m unittest discover -s Tests/ShadowVisualSettings -v

These checks do not compile Swift or exercise UIKit. They guard the ownership
and cache-input contracts behind the regression; see docs/shadow-visual-settings.md
for the required device/simulator checks. Set SHADOW_TEST_REVISION to inspect a
Git revision instead of the working tree (useful as a negative control).
"""

import os
from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[2]
CORE = "submodules/TelegramCore/Sources/AyuGram/"
UI = "submodules/TelegramUI/"


def read_source(path):
    revision = os.environ.get("SHADOW_TEST_REVISION")
    if revision:
        return subprocess.check_output(
            ["git", "show", f"{revision}:{path}"], cwd=ROOT, text=True
        )
    return (ROOT / path).read_text()


def section(source, start, end):
    return source.split(start, 1)[1].split(end, 1)[0]


class ShadowVisualSettingsContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.settings = read_source(CORE + "AyuGramSettings.swift")
        cls.root = read_source(UI + "Sources/TelegramRootController.swift")
        cls.node = read_source("submodules/TabBarUI/Sources/TabBarContollerNode.swift")
        cls.component = read_source(UI + "Components/TabBarComponent/Sources/TabBarComponent.swift")
        cls.header = read_source(UI + "Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoHeaderNode.swift")

    def test_transaction_read_has_no_ui_or_mirror_side_effects(self):
        body = section(self.settings, "public func currentAyuGramSettings(transaction:", "public func updateAyuGramSettings(transaction:")
        self.assertIn("transaction.getPreferencesEntry", body)
        for forbidden in ("setAyuGramSettingsCurrent", "UserDefaults", "writeAyu", "activateAyu"):
            self.assertNotIn(forbidden, body)

    def test_transaction_write_only_updates_postbox(self):
        body = section(self.settings, "public func updateAyuGramSettings(transaction:", "public func updateAyuGramSettings(postbox:")
        self.assertIn("transaction.setPreferencesEntry", body)
        self.assertNotIn("setAyuGramSettingsCurrent", body)
        self.assertNotIn("UserDefaults", body)

    def test_cold_start_mirror_has_a_stable_account_key(self):
        self.assertIn('"shadow.settingsMirror.account.\\(accountId.int64)"', self.settings)
        self.assertNotIn('"shadow.settingsMirror"', self.settings)
        self.assertIn("ayuGramSettingsAccountValues[accountId]", self.settings)

    def test_background_subscription_cannot_select_visible_settings(self):
        body = self.settings.split("public func keepAyuGramSettingsUpdated(", 1)[1]
        self.assertIn("accountId: AccountRecordId", body)
        self.assertIn("ayuGramSettingsAccountValues[accountId] = settings", body)
        self.assertIn("ayuSettingsMirrorKey(accountId: accountId)", body)
        for forbidden in ("setAyuGramSettingsCurrent(", "writeAyuBottomBarDefaults("):
            self.assertNotIn(forbidden, body)
        self.assertNotRegex(body, r"ayuGramSettingsActiveAccountId\s*=(?!=)")
        self.assertIn("if ayuGramSettingsActiveAccountId == nil {\n            ayuGramSettingsStateValue = settings\n        }", body)
        account = read_source("submodules/TelegramCore/Sources/Account/Account.swift")
        self.assertIn("keepAyuGramSettingsUpdated(postbox: self.postbox, accountId: self.id)", account)

    def test_stale_roots_cannot_publish_or_restore_another_account(self):
        publish = section(self.settings, "public func setAyuGramSettingsCurrent(", "private func writeAyuBottomBarDefaults(")
        restore = section(self.settings, "public func ayuSyncBottomBarDefaults(", "public enum AyuBottomBarDefaultsKeys")
        for body in (publish, restore):
            self.assertIn("precondition(Thread.isMainThread)", body)
            guard = body.index("guard ayuGramSettingsActiveAccountId == accountId else")
            reject = body.index("return false", guard)
            write = body.index("writeAyuBottomBarDefaults(settings)")
            self.assertLess(reject, write)

    def test_media_hooks_use_the_owning_account(self):
        body = section(self.settings, "public func currentAyuGramSettings(mediaBox:", "public func activateAyuGramSettings(")
        self.assertIn("ayuGramSettingsMediaAccounts[mediaBox.basePath]", body)
        self.assertIn("return AyuGramSettings.defaultSettings", body)
        for filename, flag in (("AyuEditHistory.swift", "saveEditHistory"), ("AyuSavedMedia.swift", "saveAllIncomingMedia")):
            source = read_source(CORE + filename)
            self.assertIn(f"currentAyuGramSettings(mediaBox: mediaBox).{flag}", source)
            self.assertNotIn(f"ayuGramSettingsCurrent.{flag}", source)

    def test_root_selects_its_account_before_creating_ui(self):
        body = section(self.root, "public init(context:", "required public init(coder")
        self.assertLess(body.index("activateAyuGramSettings(accountId: context.account.id)"), body.index("super.init("))

    def test_root_publishes_full_settings_before_relayout(self):
        body = section(self.root, "self.ayuSettingsDisposable = (", "public func updateRootControllers(")
        self.assertIn("ayuGramSettings(postbox: self.context.account.postbox)", body)
        self.assertIn("|> deliverOnMainQueue", body)
        self.assertNotIn("|> map", body)
        self.assertLess(body.index("setAyuGramSettingsCurrent(settings, accountId: self.context.account.id)"), body.index("?.updateLayout(transition:"))
        self.assertNotIn("self.updateRootControllers(", body)

    def test_geometry_cache_includes_both_visual_settings(self):
        params = section(self.node, "private struct Params: Equatable", "private struct LayoutResult")
        for name in ("showTabNames", "hideBottomSearch"):
            self.assertIn(f"let {name}: Bool", params)
            self.assertIn(f"self.{name} = {name}", params)
            self.assertIn(f"{name}: params.{name}", self.node)
        self.assertIn('showTabNames: !defaults.bool(forKey: "shadow.compactBottomBar")', self.node)
        self.assertIn('hideBottomSearch: defaults.bool(forKey: "shadow.hideBottomSearch")', self.node)
        self.assertIn("search: params.hideBottomSearch ? nil", self.node)

    def test_component_equality_includes_settings_and_has_no_hidden_defaults_reads(self):
        equality = section(self.component, "public static func ==(lhs: TabBarComponent", "public final class View:")
        for name in ("showTabNames", "hideBottomSearch"):
            self.assertIn(f"lhs.{name} != rhs.{name}", equality)
        self.assertNotIn("UserDefaults", self.component)
        self.assertNotIn("shadowShowTabNames", self.component)

    def test_measured_normal_and_selected_items_receive_label_visibility(self):
        self.assertEqual(self.component.count("showTabNames: component.showTabNames"), 3)
        item = self.component.split("private final class ItemComponent:", 1)[1]
        self.assertIn("lhs.showTabNames != rhs.showTabNames", item)
        self.assertIn("if component.showTabNames, let titleView", item)
        self.assertIn("titleView.removeFromSuperview()", item)

    def test_profile_uses_its_account_and_refreshes_on_foreground(self):
        self.assertNotIn("ayuGramSettingsCurrent", self.header)
        self.assertIn("currentAyuGramSettings(accountId: context.account.id)", self.header)
        self.assertIn("ayuGramSettings(postbox: context.account.postbox)", self.header)
        self.assertIn("applicationBindings.applicationIsActive |> distinctUntilChanged", self.header)
        self.assertIn("self.ayuSettings = settings", self.header)
        self.assertIn("self.requestUpdateLayout?(false)", self.header)
        self.assertIn("self.ayuSettingsDisposable?.dispose()", self.header)


if __name__ == "__main__":
    unittest.main()

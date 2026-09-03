"""Structural checks; these do NOT replace Swift type-checking or UI tests."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / 'submodules/TelegramCore/Sources/AyuGram'
DOCUMENT = (CORE / 'ShadowSettingsDocument.swift').read_text()
TRANSFER = (CORE / 'ShadowSettingsTransfer.swift').read_text()
UI = (ROOT / 'submodules/SettingsUI/Sources/ShadowSettingsBackupController.swift').read_text()


class TransferContracts(unittest.TestCase):
    def test_bool_allowlist_matches_real_keypaths(self):
        declared = set(re.findall(r'public var (\w+): Bool', (CORE / 'AyuGramSettings.swift').read_text()))
        block = DOCUMENT.split('booleanKeys: Set<String> = [', 1)[1].split(']', 1)[0]
        allowed = set(re.findall(r'"(\w+)"', block))
        paths = dict(re.findall(r'"(\w+)": \\\.([\w.]+)', TRANSFER))
        self.assertEqual(allowed, set(paths))
        nested = {f'messageScreenshot.{name}' for name in re.findall(
            r'public var (\w+): Bool', (CORE / 'ShadowMessageScreenshotSettings.swift').read_text())}
        self.assertLessEqual(set(paths.values()), declared | nested)
        self.assertTrue(all(key == value or (key.startswith('screenshot') and value in nested)
                            for key, value in paths.items()))

    def test_no_private_fields_in_export(self):
        for forbidden in ['spoofProfile', 'customBannerEnabled', 'customProfileBackground', 'api_hash', 'authKey', 'session']:
            self.assertNotIn(forbidden, DOCUMENT)
        self.assertNotIn('JSONEncoder().encode(settings)', TRANSFER)

    def test_import_preserves_unlisted_account_fields(self):
        self.assertIn('var updated = current', TRANSFER)
        self.assertNotIn('var updated = AyuGramSettings.defaultSettings', TRANSFER)

    def test_backup_and_update_share_transaction(self):
        section = TRANSFER.split('public func importShadowSettings', 1)[1].split('public func restoreShadowSettingsBackup', 1)[0]
        self.assertEqual(section.count('postbox.transaction'), 1)
        self.assertLess(section.index('guard current == expected'), section.index('transaction.setPreferencesEntry'))
        self.assertLess(section.index('ShadowSettingsBackup(settings: current)'), section.index('updateAyuGramSettings(transaction:'))

    def test_no_process_global_settings_or_io_in_transaction(self):
        self.assertNotIn('UserDefaults', TRANSFER)
        self.assertNotIn('FileManager', TRANSFER)
        self.assertNotIn('UserDefaults', UI)

    def test_import_bounds_file_read_and_releases_scope(self):
        self.assertIn('maximumBytes + 1', UI)
        self.assertIn('defer { if scoped { url.stopAccessingSecurityScopedResource() } }', UI)
        self.assertIn('NSFileCoordinator', UI)

    def test_native_share_has_ipad_anchor_and_cleanup(self):
        self.assertIn('popover.sourceView = owner.view', UI)
        self.assertIn('share.completionWithItemsHandler', UI)
        self.assertIn('shadow-export-', UI)

    def test_apply_uses_captured_account_not_active_global(self):
        self.assertIn('importShadowSettings(postbox: self.context.account.postbox', UI)
        self.assertIn('restoreShadowSettingsBackup(postbox: self.context.account.postbox', UI)


if __name__ == '__main__':
    unittest.main()

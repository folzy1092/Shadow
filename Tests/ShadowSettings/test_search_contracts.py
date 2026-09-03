"""Cross-check the static search catalog against the real settings entry IDs."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
UI_ROOT = ROOT / 'submodules/SettingsUI/Sources'
CATALOG = (UI_ROOT / 'ShadowSettingsSearchIndex.swift').read_text()
UI = (UI_ROOT / 'AyuGramSettingsController.swift').read_text()


class SearchContracts(unittest.TestCase):
    def test_destinations_reference_existing_entries(self):
        enums = {'customization': 'AyuCustomizationEntry', 'spy': 'AyuSpyEntry',
                 'ghost': 'AyuGhostEntry', 'misc': 'AyuMiscEntry'}
        ids = {'backup': {0, 1, 2}}
        for destination, name in enums.items():
            enum = UI.split(f'private enum {name}:', 1)[1].split('\nprivate ', 1)[0]
            ids[destination] = {int(i) for i in re.findall(r'case \.\w+: return (-?\d+)', enum)}
        entries = re.findall(r'ShadowSettingsSearchItem\(destination: \.(\w+), entryId: (\d+)', CATALOG)
        self.assertGreaterEqual(len(entries), 50)
        self.assertEqual(len(entries), len(set(entries)))
        for destination, entry in entries:
            self.assertIn(int(entry), ids[destination], (destination, entry))

    def test_search_contains_labels_only(self):
        for token in ('import Postbox', 'AccountContext', 'UserDefaults', 'URLSession', 'updateAyuGramSettings'):
            self.assertNotIn(token, CATALOG)

    def test_global_search_reuses_same_navigation(self):
        global_search = (UI_ROOT / 'Search/SettingsSearchableItems.swift').read_text()
        self.assertIn('ShadowSettingsSearchIndex.items.map', global_search)
        self.assertIn('shadowSettingsSearchDestinationController(context: context, item: item)', global_search)

    def test_all_screens_install_focus(self):
        self.assertEqual(UI.count('shadowSettingsInstallFocus(controller:'), 4)
        backup = (UI_ROOT / 'ShadowSettingsBackupController.swift').read_text()
        self.assertIn('shadowSettingsInstallFocus(controller:', backup)

    def test_highlight_has_no_settings_side_effects(self):
        navigation = (UI_ROOT / 'ShadowSettingsSearchNavigation.swift').read_text()
        self.assertIn('target.parentEntryId', navigation)
        self.assertIn('.now() + 1.5', navigation)
        self.assertIn('UIAccessibility.isReduceMotionEnabled', navigation)
        self.assertNotIn('updateAyuGramSettings', navigation)


if __name__ == '__main__':
    unittest.main()

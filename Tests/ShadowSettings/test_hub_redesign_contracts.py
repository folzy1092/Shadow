"""Source contracts for the Shadow hub layout (1.4.0): icons, customization parts."""
from pathlib import Path
import re
import unittest

SETTINGS_UI = Path(__file__).resolve().parents[2] / "submodules/SettingsUI/Sources"


class HubRedesignContracts(unittest.TestCase):
    def setUp(self):
        self.hub = (SETTINGS_UI / "AyuGramSettingsController.swift").read_text(encoding="utf-8")

    def test_every_customization_section_is_in_a_part(self):
        sections = self.hub.split("private enum AyuCustomizationSection: Int32 {", 1)[1].split("}", 1)[0]
        names = set(re.findall(r"case (\w+)", sections))
        parts = self.hub.split("var sections: [AyuCustomizationSection] {", 1)[1].split("func contains", 1)[0]
        covered = set(re.findall(r"\.(\w+)", parts)) & names
        # Build info moved to the update screen; badge sync is hidden.
        self.assertEqual(names - covered, {"buildInfo", "githubConfig"})

    def test_focus_and_links_pick_the_part(self):
        self.assertIn("let part = requestedPart ?? focus.flatMap { shadowCustomizationPart(for: $0) }", self.hub)
        self.assertIn("let entries = part.map { part in allEntries.filter { part.contains($0.section) } } ?? allEntries", self.hub)

    def test_icons_are_drawn_not_bundled(self):
        icons = (SETTINGS_UI / "ShadowSettingsIcons.swift").read_text(encoding="utf-8")
        self.assertIn("UIImage(systemName: symbol, withConfiguration: configuration)", icons)
        self.assertIn("shadowMonochromeSettingsIconColors", icons)
        self.assertIn("shadowSymbolIconLock.lock()", icons)
        self.assertIn("icon: shadowSymbolIcon(symbol, color: color)", self.hub)

    def test_hub_stable_ids_follow_display_order(self):
        block = self.hub.split("    var stableId: Int32 {", 1)[1].split("    static func <", 1)[0]
        order = ["update", "query", "privacyHeader", "ghost", "spy", "chatLocks", "secondSpace", "emergency",
                 "appearanceHeader", "toolsHeader", "messageScreenshot", "filters", "quickReplies", "misc",
                 "pushDiagnostics", "accountsHeader", "hiddenAccounts", "settingsSync", "backup", "crashReports", "deviceAccess"]
        ids = []
        for name in order:
            match = re.search(r"case (?:let )?\." + name + r"(?:\([^)]*\))?: return (\d+)", block)
            self.assertIsNotNone(match, name)
            ids.append(int(match.group(1)))
        self.assertEqual(ids, sorted(ids))
        self.assertEqual(len(ids), len(set(ids)))


if __name__ == "__main__":
    unittest.main()

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

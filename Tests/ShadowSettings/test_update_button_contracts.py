"""Source contracts for the update button at the top of the Shadow hub."""
from pathlib import Path
import unittest

SUB = Path(__file__).resolve().parents[2] / "submodules"


class UpdateButtonContracts(unittest.TestCase):
    def test_update_row_is_first_and_opens_the_screen(self):
        hub = (SUB / "SettingsUI/Sources/AyuGramSettingsController.swift").read_text(encoding="utf-8")
        self.assertIn("case update(detail: String, badge: Bool)", hub)
        self.assertIn('title: "Обновление Shadow", titleBadge: badge ? "1" : nil', hub)
        self.assertIn('detail = "Актуально · \(ShadowVersion.fork)"', hub)
        self.assertNotIn("case checkUpdates(", hub)
        self.assertNotIn("[Скачать IPA]", hub)
        first = hub.index("var entries: [AyuHubEntry] = [.update(detail: detail, badge: badge), .query(query)]")
        self.assertGreater(first, 0)
        screen = (SUB / "SettingsUI/Sources/ShadowUpdateController.swift").read_text(encoding="utf-8")
        self.assertIn('entries.append(.mainButton("Проверить обновления", !checking))', screen)
        self.assertIn('ItemListSectionHeaderItem(presentationData: presentationData, text: "НАСТРОЙКИ ОБНОВЛЕНИЙ"', screen)
        # Update settings sit above the list of changes.
        self.assertLess(screen.index("entries.append(.settingsHeader)"), screen.index("entries.append(.buildHeader(release: Int32(position)"))

    def test_unknown_build_does_not_show_history(self):
        core = (SUB / "TelegramCore/Sources/AyuGram/ShadowUpdateCheck.swift").read_text(encoding="utf-8")
        self.assertIn("return entries.filter { $0.build == announcedBuild }", core)


if __name__ == "__main__":
    unittest.main()

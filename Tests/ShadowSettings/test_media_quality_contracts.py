"""Source contracts: «Качество фото» — HD or files by default (1.13.0)."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SUB = ROOT / "submodules"


def read(path):
    return (SUB / path).read_text(encoding="utf-8")


class MediaQualityContracts(unittest.TestCase):
    def test_settings_and_export(self):
        settings = read("TelegramCore/Sources/AyuGram/AyuGramSettings.swift")
        self.assertIn("public var mediaSendQuality: Int32 = 0", settings)
        self.assertIn('forKey: "mediaSendQuality")', settings)
        self.assertIn('key == "mediaSendQuality" && (0...2).contains(number)', read("TelegramCore/Sources/AyuGram/ShadowSettingsDocument.swift"))
        self.assertIn('values["mediaSendQuality"]', read("TelegramCore/Sources/AyuGram/ShadowSettingsTransfer.swift"))
        self.assertIn('slug: "media-quality", entryId: 130, key: "mediaSendQuality"', read("TelegramCore/Sources/AyuGram/ShadowSettingLinks.swift"))

    def test_picker(self):
        picker = read("MediaPickerUI/Sources/MediaPickerScreen.swift")
        self.assertIn("|| ayuGramSettingsCurrent.mediaSendQuality == ShadowMediaSendQuality.alwaysHD", picker)
        self.assertIn("asFile: strongSelf.subject.asFile || strongSelf.shadowSendsAsFileByDefault()", picker)
        self.assertIn("editingContext.price(for: item) != nil || editingContext.spoiler(for: item)", picker)
        screen = read("SettingsUI/Sources/AyuGramSettingsController.swift")
        self.assertIn("case .mediaSendQuality: return 130", screen)


if __name__ == "__main__":
    unittest.main()

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
UI = ROOT / "submodules/SettingsUI/Sources"
CAMERA = ROOT / "submodules/TelegramUI/Components/VideoMessageCameraScreen/Sources"


class VideoMessageCameraRollbackContracts(unittest.TestCase):
    # This PR exists to run the full GitHub Actions validation for the rollback.
    def test_custom_round_video_controls_are_not_exposed(self):
        controller = (UI / "AyuGramSettingsController.swift").read_text()
        search = (UI / "ShadowSettingsSearchIndex.swift").read_text()

        self.assertNotIn('text: "КАСТОМНЫЕ КРУЖКИ"', controller)
        self.assertNotIn('title: "0.5× на кружках"', controller)
        self.assertNotIn('title: "Кастомная скорость кружков"', controller)
        self.assertNotIn('title: "0.5× на кружках"', search)
        self.assertNotIn('title: "Кастомная скорость кружков"', search)

    def test_round_video_starts_with_stock_front_camera(self):
        camera = (CAMERA / "VideoMessageCameraScreen.swift").read_text()

        self.assertIn("let isFrontPosition = true", camera)
        self.assertNotIn("ayuGramSettingsCurrent.roundVideoUseBackCamera", camera)


if __name__ == "__main__":
    unittest.main()

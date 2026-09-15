from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / "submodules/TelegramCore/Sources/AyuGram"
UI = ROOT / "submodules/SettingsUI/Sources"
CAMERA = ROOT / "submodules/TelegramUI/Components/VideoMessageCameraScreen/Sources"


class VideoMessageSpeedContracts(unittest.TestCase):
    def test_setting_is_opt_in_and_transferable(self):
        settings = (CORE / "AyuGramSettings.swift").read_text()
        document = (CORE / "ShadowSettingsDocument.swift").read_text()
        transfer = (CORE / "ShadowSettingsTransfer.swift").read_text()

        self.assertIn("public var customVideoMessageSpeed: Bool", settings)
        self.assertIn("customVideoMessageSpeed: false", settings)
        self.assertIn('forKey: "customVideoMessageSpeed"', settings)
        self.assertIn('"customVideoMessageSpeed"', document)
        self.assertIn('"customVideoMessageSpeed": \\.customVideoMessageSpeed', transfer)

    def test_customization_exposes_the_requested_control(self):
        controller = (UI / "AyuGramSettingsController.swift").read_text()
        search = (UI / "ShadowSettingsSearchIndex.swift").read_text()

        self.assertIn('text: "КАСТОМНЫЕ КРУЖКИ"', controller)
        self.assertIn('title: "Кастомная скорость кружков"', controller)
        self.assertIn("s.customVideoMessageSpeed = value", controller)
        self.assertIn('title: "Кастомная скорость кружков"', search)

    def test_preview_cycles_requested_rates_and_bakes_them_before_sending(self):
        camera = (CAMERA / "VideoMessageCameraScreen.swift").read_text()
        preview = (CAMERA / "ResultPreviewView.swift").read_text()

        self.assertIn("[0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0]", camera)
        self.assertIn("cycleVideoMessageSpeed", camera)
        self.assertIn("shadowPrepareVideoMessageSpeed", camera)
        self.assertIn("composition.scaleTimeRange", camera)
        self.assertIn("customVideoMessageSpeedEnabled", camera)
        self.assertIn("audioTimePitchAlgorithm = .varispeed", preview)
        self.assertIn("playImmediately(atRate: self.playbackRate)", preview)


if __name__ == "__main__":
    unittest.main()

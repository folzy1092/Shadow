from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / "submodules/TelegramCore/Sources/AyuGram"
UI = ROOT / "submodules/SettingsUI/Sources"
CAMERA = ROOT / "submodules/TelegramUI/Components/VideoMessageCameraScreen/Sources"
LOW_LEVEL_CAMERA = ROOT / "submodules/Camera/Sources/CameraDevice.swift"


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

    def test_ultra_wide_round_video_is_an_opt_in_hardware_switch(self):
        settings = (CORE / "AyuGramSettings.swift").read_text()
        document = (CORE / "ShadowSettingsDocument.swift").read_text()
        transfer = (CORE / "ShadowSettingsTransfer.swift").read_text()
        controller = (UI / "AyuGramSettingsController.swift").read_text()
        search = (UI / "ShadowSettingsSearchIndex.swift").read_text()
        camera = (CAMERA / "VideoMessageCameraScreen.swift").read_text()
        low_level_camera = LOW_LEVEL_CAMERA.read_text()

        self.assertIn("public var roundVideoUltraWide: Bool", settings)
        self.assertIn("roundVideoUltraWide: false", settings)
        self.assertIn('"roundVideoUltraWide"', document)
        self.assertIn('"roundVideoUltraWide": \\.roundVideoUltraWide', transfer)
        self.assertIn('title: "0.5× на кружках"', controller)
        self.assertIn('title: "0.5× на кружках"', search)
        self.assertIn("toggleRoundVideoUltraWide", camera)
        self.assertIn("self.camera?.rampZoom(self.roundVideoZoom", camera)
        self.assertIn("max(0.5, device.minAvailableVideoZoomFactor)", low_level_camera)

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

    def test_speed_control_handles_taps_before_the_preview_circle(self):
        camera = (CAMERA / "VideoMessageCameraScreen.swift").read_text()
        self.assertIn("videoMessageSpeedButtonTag", camera)
        self.assertIn("tag: videoMessageSpeedButtonTag", camera)
        self.assertIn("findTaggedView(tag: videoMessageSpeedButtonTag)", camera)
        self.assertIn("return speedButton.hitTest(speedPoint, with: event) ?? speedButton", camera)


if __name__ == "__main__":
    unittest.main()

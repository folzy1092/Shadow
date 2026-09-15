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



if __name__ == "__main__":
    unittest.main()

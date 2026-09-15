from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / "submodules/TelegramCore/Sources/AyuGram"
CAMERA = ROOT / "submodules/TelegramUI/Components/VideoMessageCameraScreen/Sources"


class RoundVideoCameraRollbackContracts(unittest.TestCase):
    def test_custom_round_video_features_are_removed(self):
        settings = (CORE / "AyuGramSettings.swift").read_text()
        camera = (CAMERA / "VideoMessageCameraScreen.swift").read_text()

        self.assertNotIn("roundVideoUltraWide", settings)
        self.assertNotIn("customVideoMessageSpeed", settings)
        self.assertNotIn("handleRecordingZoomPan", camera)
        self.assertNotIn("shadowVideoMessageSpeed", camera)


if __name__ == "__main__":
    unittest.main()

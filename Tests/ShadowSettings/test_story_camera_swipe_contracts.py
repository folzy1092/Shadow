from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / "submodules/TelegramCore/Sources/AyuGram"
SETTINGS_UI = ROOT / "submodules/SettingsUI/Sources"
CHAT_LIST_UI = ROOT / "submodules/ChatListUI/Sources"


class StoryCameraSwipeContracts(unittest.TestCase):
    def test_setting_is_persisted_and_included_in_backups(self):
        settings = (CORE / "AyuGramSettings.swift").read_text()
        document = (CORE / "ShadowSettingsDocument.swift").read_text()
        transfer = (CORE / "ShadowSettingsTransfer.swift").read_text()

        self.assertIn("public var disableStoryCameraSwipe: Bool", settings)
        self.assertIn('forKey: "disableStoryCameraSwipe"', settings)
        self.assertIn('"disableStoryCameraSwipe"', document)
        self.assertIn('"disableStoryCameraSwipe": \\.disableStoryCameraSwipe', transfer)

    def test_misc_screen_exposes_the_toggle(self):
        controller = (SETTINGS_UI / "ShadowPushDiagnosticsController.swift").read_text()
        hub = (SETTINGS_UI / "AyuGramSettingsController.swift").read_text()
        search = (SETTINGS_UI / "ShadowSettingsSearchIndex.swift").read_text()

        self.assertIn("func shadowMiscController", controller)
        self.assertIn('title: "Отключить свайп к камере"', controller)
        self.assertIn("settings.disableStoryCameraSwipe = value", controller)
        self.assertIn("shadowMiscController(context: context)", hub)
        self.assertIn('title: "Отключить свайп к камере"', search)

    def test_chat_list_gates_only_story_camera_swipe(self):
        controller = (CHAT_LIST_UI / "ChatListController.swift").read_text()
        node = (CHAT_LIST_UI / "ChatListControllerNode.swift").read_text()

        self.assertIn("disableStoryCameraSwipe: ayuGramSettingsValue.disableStoryCameraSwipe", controller)
        self.assertIn("!self.disableStoryCameraSwipe, self.controller?.isStoryPostingAvailable", node)


if __name__ == "__main__":
    unittest.main()

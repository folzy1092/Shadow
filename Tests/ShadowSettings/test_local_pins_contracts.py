"""Source contracts: «Закрепить у себя» — local pins in any chat (1.13.0)."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SUB = ROOT / "submodules"


def read(path):
    return (SUB / path).read_text(encoding="utf-8")


class LocalPinsContracts(unittest.TestCase):
    def test_header_merges_local_pins(self):
        controller = read("TelegramUI/Sources/ChatController.swift")
        self.assertIn("return shadowMergeLocalPins(server: ChatControllerImpl.topPinnedMessageState(", controller)
        chat = read("TelegramUI/Sources/Chat/ShadowLocalPinsChat.swift")
        self.assertIn("ShadowLocalPinStore.didChangeNotification", chat)
        self.assertIn("!message.tags.contains(.pinned)", chat)

    def test_unpin_and_list_stay_local(self):
        load = read("TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift")
        self.assertIn("if let strongSelf = self, strongSelf.shadowHandleLocalPinUnpin(messageId: id) {", load)
        self.assertIn("if strongSelf.shadowOpenLocalPinList(messageId: messageId) {", load)

    def test_message_menu(self):
        menus = read("TelegramUI/Sources/ChatInterfaceStateContextMenus.swift")
        self.assertIn('isLocallyPinned ? "Открепить у себя" : (canPin ? "Закрепить у себя" : "Закрепить")', menus)
        self.assertIn('"Закреплено только у вас"', menus)

    def test_foundation_suite(self):
        runner = (ROOT / "build-system/ci/test_shadow_foundation.py").read_text(encoding="utf-8")
        self.assertIn("'Tests/ShadowSettings/LocalPinsTests.swift'", runner)


if __name__ == "__main__":
    unittest.main()

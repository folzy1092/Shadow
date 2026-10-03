"""Second space hides stories of chats hidden in the current space."""
from pathlib import Path
import unittest

SUB = Path(__file__).resolve().parents[2] / "submodules"


class StoriesSpaceContracts(unittest.TestCase):
    def test_story_bar_filtered_by_active_space(self):
        src = (SUB / "ChatListUI/Sources/ChatListController.swift").read_text(encoding="utf-8")
        fn = src.split("func shadowFilteredStorySubscriptions", 1)[1].split("\n}", 1)[0]
        self.assertIn("ShadowSpaceStore.shared", fn)
        self.assertIn("store.isHidden(accountPeerId: accountPeerId, peerId: $0.peer.id.toInt64())", fn)
        self.assertIn("ShadowSpaceStore.didChangeNotification", fn)


if __name__ == "__main__":
    unittest.main()

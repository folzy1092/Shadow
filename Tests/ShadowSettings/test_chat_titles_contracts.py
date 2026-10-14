"""Source contracts: «Своё название» — local chat names (1.13.0)."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SUB = ROOT / "submodules"


def read(path):
    return (SUB / path).read_text(encoding="utf-8")


class ChatTitlesContracts(unittest.TestCase):
    def test_every_title_reads_the_store(self):
        title = read("LocalizedPeerData/Sources/PeerTitle.swift")
        self.assertIn("if let customTitle = self.shadowCustomTitle(accountPeerId: accountPeerId) {", title)
        self.assertIn("ShadowDisguise.shared.isFull", title)
        for path in ("TelegramUI/Components/ChatTitleView/Sources/ChatTitleView.swift", "TelegramUI/Components/ChatTitleView/Sources/ChatTitleComponent.swift"):
            self.assertIn("if let customTitle = EnginePeer(peer).shadowCustomTitle(", read(path), path)

    def test_list_reloads_and_menu(self):
        node = read("ChatListUI/Sources/Node/ChatListNode.swift")
        self.assertIn("forName: ShadowChatTitleStore.didChangeNotification", node)
        menus = read("ChatListUI/Sources/ChatContextMenus.swift")
        self.assertIn("func shadowRenameChat(", menus)
        self.assertIn('"Своё название"', menus)
        self.assertIn('"//submodules/PromptUI:PromptUI"', (SUB / "ChatListUI/BUILD").read_text(encoding="utf-8"))
        runner = (ROOT / "build-system/ci/test_shadow_foundation.py").read_text(encoding="utf-8")
        self.assertIn("'Tests/ShadowSettings/ChatTitlesTests.swift'", runner)


if __name__ == "__main__":
    unittest.main()

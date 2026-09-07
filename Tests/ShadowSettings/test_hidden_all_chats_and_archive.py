from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
CHAT_LIST_UI = ROOT / "submodules/ChatListUI/Sources"
PEER_INFO = ROOT / "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources"


class HiddenAllChatsAndArchiveContracts(unittest.TestCase):
    def test_hidden_all_chats_cannot_be_selected_by_swipe(self):
        controller = (CHAT_LIST_UI / "ChatListController.swift").read_text()
        node = (CHAT_LIST_UI / "ChatListControllerNode.swift").read_text()

        self.assertIn("hideAllChatsFromSwipe = true", controller)
        self.assertIn("hideAllChatsFromSwipe: hideAllChatsFromSwipe", controller)
        self.assertIn("return self.availableFilters.filter { $0 != .all }", node)
        self.assertIn("let swipeFilters = self.navigableFilters", node)
        self.assertIn("swipeFilters.firstIndex", node)
        self.assertIn("let switchToId = swipeFilters[updatedIndex].id", node)
        self.assertIn("let navigableFilters = strongSelf.chatListDisplayNode.mainContainerNode.navigableFilters", controller)
        self.assertIn("mainContainerNode.navigableFilters.contains(.all)", controller)

    def test_archive_is_permanent_shortcut_below_saved_messages(self):
        items = (PEER_INFO / "PeerInfoSettingsItems.swift").read_text()
        actions = (PEER_INFO / "PeerInfoScreenSettingsActions.swift").read_text()
        section = (PEER_INFO / "PeerInfoScreen.swift").read_text()

        saved_index = items.index("interaction.openSettings(.savedMessages)")
        archive_index = items.index('text: "Открыть архив"')
        calls_index = items.index("interaction.openSettings(.recentCalls)")
        self.assertLess(saved_index, archive_index)
        self.assertLess(archive_index, calls_index)
        self.assertIn("case archive", section)
        self.assertIn("case .archive:", actions)
        self.assertIn("location: .chatList(groupId: .archive)", actions)
        self.assertNotIn("showArchiveShortcut", items)


if __name__ == "__main__":
    unittest.main()

"""Source contracts: a locked chat (or Saved Messages) cannot be read around the lock."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SUB = ROOT / "submodules"


def read(path):
    return (SUB / path).read_text(encoding="utf-8")


class ChatLockBypassContracts(unittest.TestCase):
    def test_saved_messages_can_be_locked(self):
        menus = read("ChatListUI/Sources/ChatContextMenus.swift")
        self.assertIn("if items.isEmpty || ShadowDisguise.shared.isFull {", menus)
        self.assertIn("let isSavedMessages = peerId == context.account.peerId", menus)
        controller = read("ChatListUI/Sources/ChatListController.swift")
        self.assertIn("let candidates = peerIds.sorted(by: { $0.toInt64() < $1.toInt64() })", controller)
        item = read("ChatListUI/Sources/Node/ChatListItem.swift")
        self.assertIn("if case .savedMessagesChats = item.chatListLocation, store.isLocked(accountPeerId: accountPeerId, peerId: accountPeerId)", item)
        self.assertIn("} else if inlineAuthorPrefix == nil, shadowIsLocked, draftState != nil {", item)

    def test_archive_item_is_back(self):
        menus = read("ChatListUI/Sources/ChatContextMenus.swift")
        self.assertIn("&& peerId != context.account.peerId\n", menus)

    def test_side_doors_are_closed(self):
        profile = read("TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoData.swift")
        self.assertIn("return shadowFilterLockedPanes(panes, accountPeerId: accountPeerId, peerId: lockedPeerId)", profile)
        search = read("ChatListUI/Sources/ChatListSearchListPaneNode.swift")
        self.assertIn("if ShadowChatLockStore.shared.isLocked(accountPeerId: shadowAccountPeerId, peerId: messageId.peerId.toInt64()) {", search)
        app = read("TelegramUI/Sources/ApplicationContext.swift")
        self.assertIn("// Shadow: no in-app banner (text, sender, media) for a locked chat.", app)
        self.assertIn("ShadowChatLockPreviews.sync(engine: shadowEngine, accountPeerId: shadowAccountPeerId)", app)
        archive = read("SettingsUI/Sources/AyuArchiveChatContents.swift")
        self.assertIn("if ShadowChatLockStore.shared.isLocked(accountPeerId: accountPeerId, peerId: id.peerId.toInt64()) || ShadowSpaceStore.shared.isHidden(", archive)
        previews = read("TelegramCore/Sources/AyuGram/ShadowChatLockPreviews.swift")
        self.assertIn("displayPreviews: .hide", previews)
        self.assertIn("if ShadowDisguise.shared.isFull {", previews)

    def test_relock_keeps_same_chat_open_below(self):
        chat = read("TelegramUI/Sources/ChatController.swift")
        self.assertIn("if !stillInStack, !sameChatStillOpen, let peerId = self.chatLocation.peerId {", chat)


    def test_chat_hidden_in_active_space_cannot_be_opened(self):
        shared = read("TelegramUI/Sources/SharedAccountContext.swift")
        gate = shared.index("if ShadowSpaceStore.shared.isHidden(accountPeerId: accountPeerId, peerId: peerId) {")
        self.assertLess(gate, shared.index("navigateToChatControllerImpl(params)", gate))
        ui = read("TelegramUI/Sources/ShadowChatLockUI.swift")
        self.assertIn("let hiddenInSpace = ShadowSpaceStore.shared.isHidden(", ui)
        self.assertIn("overlay.setUnavailable(hiddenInSpace)", ui)
        self.assertIn("!hiddenInSpace && !overlay.didAutoAuthenticate", ui)
        self.assertIn("forName: ShadowSpaceStore.didChangeNotification", ui)
        profile = read("TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoData.swift")
        self.assertIn("|| spaces.isHidden(accountPeerId: accountPeerId.toInt64(), peerId: peerId.toInt64())", profile)


if __name__ == "__main__":
    unittest.main()

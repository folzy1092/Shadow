"""Source contracts for the shadow ban and fully hidden messages being read."""
from pathlib import Path
import unittest

SUB = Path(__file__).resolve().parents[2] / "submodules"


def read(path):
    return (SUB / path).read_text(encoding="utf-8")


class ShadowBanContracts(unittest.TestCase):
    def test_setting_round_trips(self):
        settings = read("TelegramCore/Sources/AyuGram/AyuGramSettings.swift")
        self.assertIn("public var shadowBannedPeerIds: [Int64] = []", settings)
        self.assertIn('forKey: "shadowBannedPeerIdsV1"', settings)
        self.assertIn("try container.encode(self.shadowBannedPeerIds, forKey: \"shadowBannedPeerIdsV1\")", settings)

    def test_history_hides_banned_authors_but_not_own_messages(self):
        # One check for the chat and the chat list (ShadowLocalHide.swift).
        hide = read("TelegramCore/Sources/AyuGram/ShadowLocalHide.swift")
        self.assertIn("authorId != accountPeerId, settings.isShadowBanned(peerId: authorId.toInt64())", hide)
        self.assertIn('"Скрыто: теневой бан"', hide)
        history = read("TelegramUI/Sources/ChatHistoryEntriesForView.swift")
        self.assertIn("let accountPeerId = context.account.peerId", history)
        self.assertIn("shadowLocalHideReason(messages[index].0, settings: shadowSettings, accountPeerId: accountPeerId)", history)

    def test_entry_points(self):
        peer_info = read("TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreenPerformButtonAction.swift")
        self.assertIn('"Теневой бан"', peer_info)
        self.assertIn("shadowToggleShadowBan(context: self.context, peerId: peer.id", peer_info)
        filters = read("SettingsUI/Sources/ShadowMessageFiltersController.swift")
        self.assertIn('"ТЕНЕВОЙ БАН"', filters)

    def test_fully_hidden_messages_do_not_keep_the_chat_unread(self):
        node = read("TelegramUI/Sources/ChatHistoryListNode.swift")
        self.assertIn("if strongSelf.isScrollAtBottomPosition, let lastMessageId", node)
        self.assertIn("!shadowSettings.messageFilterShowPlaceholder) || !shadowSettings.shadowBannedPeerIds.isEmpty", node)


if __name__ == "__main__":
    unittest.main()

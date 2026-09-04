"""Integration contracts only; actual formatting is tested with Swift in CI."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class PeerNameContracts(unittest.TestCase):
    def read(self, path):
        return (ROOT / 'submodules' / path).read_text()

    def test_unknown_contact_state_falls_back(self):
        source = self.read('TelegramCore/Sources/AyuGram/ShadowPeerName.swift')
        self.assertIn('isContact == false', source)
        self.assertIn('!isSelf', source)
        self.assertNotIn('UserDefaults', source)

    def test_channel_titles_are_not_replaced(self):
        source = self.read('LocalizedPeerData/Sources/PeerTitle.swift')
        self.assertIn('guard case let .user(user) = self', source)
        self.assertIn('isBot: user.botInfo != nil, botsEnabled: botsEnabled', source)
        self.assertIn('?? self.displayTitle', source)

    def test_chat_list_contacts_and_account_refresh(self):
        source = self.read('ChatListUI/Sources/Node/ChatListNode.swift')
        self.assertEqual(source.count('isContact: isContact,\n'), 2)
        self.assertIn('self.shadowNamesDisposable.dispose()', source)
        self.assertIn('ayuGramSettings(postbox: context.account.postbox)', source)
        self.assertIn('preferUsernameForNonContacts: state.presentationData.preferUsernameForNonContacts', source)

    def test_toggle_persistence_and_search(self):
        settings = self.read('TelegramCore/Sources/AyuGram/AyuGramSettings.swift')
        self.assertIn('public var preferUsernameForNonContacts: Bool = false', settings)
        self.assertEqual(settings.count('forKey: "preferUsernameForNonContacts"'), 2)
        ui = self.read('SettingsUI/Sources/AyuGramSettingsController.swift')
        self.assertIn('entries.append(.preferUsernameForNonContacts(settings.preferUsernameForNonContacts))', ui)
        self.assertIn('entryId: 94', self.read('SettingsUI/Sources/ShadowSettingsSearchIndex.swift'))

    def test_history_uses_account_snapshot(self):
        source = self.read('TelegramUI/Sources/ChatHistoryListNode.swift')
        self.assertIn('ayuGramSettings(postbox: self.context.account.postbox)', source)
        self.assertIn('preferUsernameForNonContacts: shadowSettings.preferUsernameForNonContacts', source)

    def test_bot_preference_defaults_to_names_and_is_portable(self):
        settings = self.read('TelegramCore/Sources/AyuGram/AyuGramSettings.swift')
        self.assertIn('public var preferUsernameForBots: Bool = false', settings)
        self.assertIn('decodeIfPresent(Int32.self, forKey: "preferUsernameForBots")) ?? 0', settings)
        self.assertIn('encode((self.preferUsernameForBots ? 1 : 0) as Int32', settings)
        for file in ['ShadowSettingsTransfer.swift', 'ShadowSettingsDocument.swift']:
            self.assertIn('"preferUsernameForBots"', self.read('TelegramCore/Sources/AyuGram/' + file))
        ui = self.read('SettingsUI/Sources/AyuGramSettingsController.swift')
        self.assertIn('if settings.preferUsernameForNonContacts {\n        entries.append(.preferUsernameForBots(settings.preferUsernameForBots))', ui)
        self.assertIn('case .preferUsernameForBots: return (9, 3)', ui)

    def test_bot_preference_reaches_every_title_surface(self):
        for file in [
            'ChatListUI/Sources/Node/ChatListItem.swift',
            'TelegramUI/Components/ChatTitleView/Sources/ChatTitleView.swift',
            'TelegramUI/Components/ChatTitleView/Sources/ChatTitleComponent.swift',
            'TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoHeaderNode.swift',
            'TelegramUI/Components/Chat/ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift',
        ]:
            source = self.read(file)
            calls = [line for line in source.splitlines() if '.shadowDisplayTitle(' in line or '.shadowUsername(' in line]
            self.assertTrue(calls, file)
            for line in calls:
                self.assertIn('botsEnabled:', line, file)
        for file in ['ChatListUI/Sources/Node/ChatListNode.swift', 'TelegramUI/Components/ChatTitleView/Sources/ChatTitleView.swift', 'TelegramUI/Components/ChatTitleView/Sources/ChatTitleComponent.swift']:
            self.assertIn('map { ($0.preferUsernameForNonContacts, $0.preferUsernameForBots) }', self.read(file))


if __name__ == '__main__':
    unittest.main()

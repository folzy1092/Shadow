"""Source contracts for the "Чистый интерфейс" toggles (spec 2026-10-01)."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SUB = ROOT / "submodules"


def read(path):
    return (SUB / path).read_text()


class CleanInterfaceContracts(unittest.TestCase):
    def test_settings_fields_round_trip(self):
        settings = read("TelegramCore/Sources/AyuGram/AyuGramSettings.swift")
        for name in ("hideStoriesBar", "hideGiftButton", "hidePremiumBadges", "hideSponsoredMessages", "localVoiceTranscription"):
            self.assertIn(f"public var {name}: Bool", settings)
            self.assertIn(f'forKey: "{name}")) ??', settings)
            self.assertIn(f'as Int32, forKey: "{name}")', settings)
        self.assertIn('forKey: "quickReplyTemplates"', settings)

    def test_stories_bar_is_filtered_for_both_subscriptions(self):
        source = read("ChatListUI/Sources/ChatListController.swift")
        self.assertEqual(source.count("shadowFilteredStorySubscriptions(context: self.context"), 2)
        self.assertIn("settings.hideStoriesBar", source)

    def test_gift_button_toggle(self):
        source = read("TelegramUI/Sources/ChatInterfaceInputContexts.swift")
        self.assertIn("!shadowHideGiftButton && !premiumConfiguration.isPremiumDisabled", source)

    def test_sponsored_context_is_not_created(self):
        source = read("TelegramUI/Sources/ChatControllerNode.swift")
        self.assertIn("!currentAyuGramSettings(accountId: context.account.id).hideSponsoredMessages", source)

    def test_premium_badges_hidden_at_name_sites(self):
        sites = {
            "ChatListUI/Sources/Node/ChatListItem.swift": 4,
            "TelegramUI/Components/ChatTitleView/Sources/ChatTitleView.swift": 2,
            "TelegramUI/Components/ChatTitleView/Sources/ChatTitleComponent.swift": 2,
            "TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoHeaderNode.swift": 2,
            "ContactsPeerItem/Sources/ContactsPeerItem.swift": 2,
            "ItemListPeerItem/Sources/ItemListPeerItem.swift": 2,
            "TelegramUI/Components/Chat/ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift": 3,
        }
        for path, count in sites.items():
            self.assertEqual(read(path).count("hidePremiumBadges"), count, path)

    def test_settings_screen_is_reachable_and_searchable(self):
        hub = read("SettingsUI/Sources/AyuGramSettingsController.swift")
        self.assertIn("case .cleanInterface: return shadowCleanInterfaceController(context: context, focus: item)", hub)
        index = read("SettingsUI/Sources/ShadowSettingsSearchIndex.swift")
        self.assertEqual(index.count("destination: .cleanInterface"), 5)


if __name__ == "__main__":
    unittest.main()

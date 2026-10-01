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
        for name in ("hideStoriesBar", "hideGiftButton", "hidePremiumBadges", "hideSponsoredMessages", "localVoiceTranscription"):
            self.assertIn(f"entries.append(.{name}(settings.{name}))", hub)
        self.assertFalse((SUB / "SettingsUI/Sources/ShadowCleanInterfaceController.swift").exists())
        index = read("SettingsUI/Sources/ShadowSettingsSearchIndex.swift")
        for entry in (99, 100, 101, 102, 103):
            self.assertIn(f"destination: .customization, entryId: {entry},", index)

    def test_local_voice_transcription(self):
        node = read("TelegramUI/Components/Chat/ChatMessageInteractiveFileNode/Sources/ChatMessageInteractiveFileNode.swift")
        helper = node.split("private func shadowUsesLocalVoiceTranscription", 1)[1]
        self.assertIn("arguments.file.isVoice, !arguments.associatedData.isPremium", helper)
        self.assertIn(".localVoiceTranscription", helper)
        self.assertIn("if shadowLocalTranscription || context.sharedContext.immediateExperimentalUISettings.localTranscription", node)
        self.assertIn("if !shadowLocalTranscription && transcriptionText == nil", node)

    def test_quick_reply_templates(self):
        state = read("ChatPresentationInterfaceState/Sources/ChatTextInputPanelState.swift")
        self.assertEqual(state.count("shadowTemplates"), 4)
        icon = read("TelegramUI/Components/Chat/ChatTextInputPanelNode/Sources/AccessoryItemIconButton.swift")
        self.assertIn("case .shadowTemplates:", icon)
        self.assertIn(".suggestPost, .shadowTemplates:", icon)
        panel = read("TelegramUI/Components/Chat/ChatTextInputPanelNode/Sources/ChatTextInputPanelNode.swift")
        self.assertIn("self.shadowPresentQuickReplyTemplates()", panel)
        contexts = read("TelegramUI/Sources/ChatInterfaceInputContexts.swift")
        self.assertIn("accessoryItems.append(.shadowTemplates)", contexts)
        screen = read("SettingsUI/Sources/ShadowQuickRepliesController.swift")
        self.assertIn("shadowNormalizedQuickReplyTemplates", screen)
        self.assertIn('"//submodules/PromptUI:PromptUI"', (SUB / "SettingsUI/BUILD").read_text())

    def test_update_check_release_pipeline(self):
        workflow = (ROOT / ".github/workflows/build.yml").read_text()
        self.assertIn("contents: write", workflow)
        self.assertIn('TAG="build-${BUILD_NUMBER}"', workflow)
        self.assertIn("gh release create", workflow)
        self.assertIn('ASSET="$RUNNER_TEMP/Shadow.ipa"', workflow)
        self.assertEqual(workflow.count('TAIL="Скачать IPA: ${IPA_URL}"'), 2)
        check = read("TelegramCore/Sources/AyuGram/ShadowUpdateCheck.swift")
        self.assertIn('let prefix = "build-"', check)
        self.assertIn("releases/latest", check)
        self.assertIn("master/shadow-update.json", check)
        import json
        manifest = json.loads((ROOT / "shadow-update.json").read_text())
        self.assertIsInstance(manifest["enabled"], bool)
        self.assertIsInstance(manifest["build"], int)
        self.assertIn("update-check", (ROOT / "build-system/ci/test_shadow_foundation.py").read_text())

    def test_unlimited_pinned_chats(self):
        toggle = read("TelegramCore/Sources/TelegramEngine/Peers/TogglePeerChatPinned.swift")
        self.assertIn("if !shadowUnlimited, count > limitCount", toggle)
        settings = read("TelegramCore/Sources/AyuGram/AyuGramSettings.swift")
        self.assertIn('forKey: "unlimitedPinnedChats")) ?? 1) != 0', settings)
        hub = read("SettingsUI/Sources/AyuGramSettingsController.swift")
        self.assertIn("entries.append(.unlimitedPinnedChats(settings.unlimitedPinnedChats))", hub)


if __name__ == "__main__":
    unittest.main()

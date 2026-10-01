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
        hub = read("SettingsUI/Sources/AyuGramSettingsController.swift")
        self.assertIn("ItemListInfoItem(", hub)
        self.assertIn("arguments.dismissUpdateBanner()", hub)
        self.assertIn("[Скачать IPA]", hub)
        self.assertFalse((SUB / "SettingsUI/Sources/ShadowUpdatesController.swift").exists())

    def test_changelog_file_and_banner(self):
        import json
        log = json.loads((ROOT / "shadow-changelog.json").read_text())
        builds = [entry["build"] for entry in log["entries"]]
        self.assertEqual(builds, sorted(builds, reverse=True))
        for entry in log["entries"]:
            self.assertTrue(entry["items"])
        manifest = json.loads((ROOT / "shadow-update.json").read_text())
        # The announced build must have release notes.
        self.assertIn(manifest["build"], builds)
        check = read("TelegramCore/Sources/AyuGram/ShadowUpdateCheck.swift")
        self.assertIn("master/shadow-changelog.json", check)
        hub = read("SettingsUI/Sources/AyuGramSettingsController.swift")
        self.assertIn("for entry in release.changelog {", hub)

    def test_app_icons(self):
        build = (ROOT / "Telegram/BUILD").read_text()
        for name in ("ShadowIcon", "CalculatorIcon", "NotesIcon", "WeatherIcon"):
            self.assertIn(f'"{name}",', build)
            folder = ROOT / f"Telegram/Telegram-iOS/{name}.alticon"
            self.assertTrue((folder / f"{name}@2x.png").exists(), name)
            self.assertTrue((folder / f"{name}@3x.png").exists(), name)
        icon = (ROOT / "Telegram/Telegram-iOS/Telegram.icon/icon.json").read_text()
        self.assertIn('"PlaneShadow.svg"', icon)
        self.assertTrue((ROOT / "Telegram/Telegram-iOS/Telegram.icon/Assets/PlaneShadow.svg").exists())
        delegate = read("TelegramUI/Sources/AppDelegate.swift")
        self.assertIn('PresentationAppIcon(name: "ShadowIcon", imageName: "ShadowIcon", isDefault: true)', delegate)

    def test_compact_chat_list(self):
        item = read("ChatListUI/Sources/Node/ChatListItem.swift")
        self.assertEqual(item.count("avatarDiameter = floor(avatarDiameter * 0.75)"), 2)
        self.assertIn("measureLayout.size.height * (shadowCompact ? 2.0 : 3.0)", item)
        node = read("ChatListUI/Sources/Node/ChatListNode.swift")
        self.assertIn(".withCompactChatList(enabled.2)", node)
        hub = read("SettingsUI/Sources/AyuGramSettingsController.swift")
        self.assertIn("entries.append(.compactChatList(settings.compactChatList))", hub)

    def test_online_history(self):
        updates = read("TelegramCore/Sources/TelegramEngine/../UpdatePeers.swift")
        self.assertIn("currentAyuGramSettings(transaction: transaction).onlineHistory", updates)
        self.assertIn("transaction.isPeerContact(peerId: peerId)", updates)
        profile = read("TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoProfileItems.swift")
        self.assertIn("shadowOnlineHistoryController(context: context, peerId: user.id)", profile)
        self.assertIn("'online-history'", (ROOT / "build-system/ci/test_shadow_foundation.py").read_text())

    def test_saved_stories(self):
        stories = read("TelegramCore/Sources/TelegramEngine/Messages/Stories.swift")
        self.assertIn("shadowArchiveViewedStory(account: account, peerId: peerId, id: id)", stories)
        archive = read("TelegramCore/Sources/AyuGram/ShadowStoryArchive.swift")
        self.assertIn("currentAyuGramSettings(transaction: transaction).saveViewedStories", archive)
        # Copies what the viewer downloaded; never fetches on its own.
        self.assertNotIn("fetchedMediaResource", archive)
        hub = read("SettingsUI/Sources/AyuGramSettingsController.swift")
        self.assertIn("pushControllerImpl?(shadowSavedStoriesController(context: context))", hub)

    def test_unlimited_pinned_chats(self):
        toggle = read("TelegramCore/Sources/TelegramEngine/Peers/TogglePeerChatPinned.swift")
        self.assertIn("if !shadowUnlimited, count > limitCount", toggle)
        self.assertIn("!currentAyuGramSettings(transaction: transaction).unlimitedPinnedChats, updatedData.includePeers.peers.count > userLimitsConfiguration.maxFolderChatsCount", toggle)
        peers = read("TelegramCore/Sources/TelegramEngine/Peers/TelegramEnginePeers.swift")
        self.assertIn("if !shadowUnlimited && threadIds.count + 1 > limit", peers)
        filtering = read("TelegramCore/Sources/TelegramEngine/Peers/ChatListFiltering.swift")
        self.assertIn("rejectedFilterIds", filtering)
        self.assertIn("return remoteFilters.first(where: { $0.id == filter.id })", filtering)
        settings = read("TelegramCore/Sources/AyuGram/AyuGramSettings.swift")
        self.assertIn('forKey: "unlimitedPinnedChats")) ?? 1) != 0', settings)
        hub = read("SettingsUI/Sources/AyuGramSettingsController.swift")
        self.assertIn("entries.append(.unlimitedPinnedChats(settings.unlimitedPinnedChats))", hub)


    def test_monochrome_settings_icons(self):
        resources = read("TelegramPresentationData/Sources/Resources/PresentationResourcesSettings.swift")
        self.assertIn("if backgroundColors != nil, let monochrome = shadowMonochromeSettingsIconColors {", resources)
        self.assertIn("context.setFillColor(glyphColor.cgColor)", resources)
        # Static icons are computed so they follow the setting without a restart.
        self.assertNotIn("public static let proxy = renderSettingsIcon", resources)
        self.assertIn("public static var proxy: UIImage? { return renderSettingsIcon(", resources)
        self.assertIn("import TelegramCore", resources)
        items = read("TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoSettingsItems.swift")
        self.assertNotIn('icon: UIImage(bundleImageName: "Chat/Context Menu/', items)
        self.assertIn("PresentationResourcesSettings.shadowArchive", items)
        settings = read("TelegramCore/Sources/AyuGram/AyuGramSettings.swift")
        for name in ("monochromeSettingsIcons", "settingsIconBackgroundColor", "settingsIconGlyphColor"):
            self.assertIn(f'forKey: "{name}")', settings)
        hub = read("SettingsUI/Sources/AyuGramSettingsController.swift")
        self.assertIn("entries.append(.monochromeSettingsIcons(settings.monochromeSettingsIcons))", hub)
        self.assertIn("if #available(iOS 14.0, *) {", hub)
        self.assertIn("@available(iOS 14.0, *)\nprivate final class ShadowSystemColorPicker", hub)


if __name__ == "__main__":
    unittest.main()

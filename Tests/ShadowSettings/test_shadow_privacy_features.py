from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / "submodules/TelegramCore/Sources"
UI = ROOT / "submodules/TelegramUI"
SETTINGS_UI = ROOT / "submodules/SettingsUI/Sources"


class ShadowPrivacyFeatures(unittest.TestCase):
    def test_local_read_never_uses_interactive_sync(self):
        source = (CORE / "TelegramEngine/Messages/ApplyMaxReadIndexInteractively.swift").read_text()
        local = source.split("func _internal_markAllChatsAsReadLocally", 1)[1]
        self.assertIn("transaction.applyIncomingReadMaxId(index.id)", local)
        self.assertNotIn("network.request", local)
        self.assertNotIn("applyInteractiveReadMaxIndex(index)", local)

    def test_explicit_read_keeps_selected_max_id(self):
        source = (CORE / "TelegramEngine/Messages/TelegramEngineMessages.swift").read_text()
        explicit = source.split("public func readMessageHistoryExplicitly", 1)[1].split("public func sendScheduledMessageNowInteractively", 1)[0]
        self.assertIn("peerId: index.id.peerId, maxId: index.id.id", explicit)
        self.assertIn("localMessageId: index.id", explicit)
        self.assertIn("messages.readDiscussion", explicit)
        self.assertNotIn("suppressReadReceipts", explicit)

    def test_server_read_all_uses_server_boundary_and_reports_result(self):
        engine = (CORE / "TelegramEngine/Messages/TelegramEngineMessages.swift").read_text()
        action = (UI / "Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreenSettingsActions.swift").read_text()
        read_all = engine.split("public func markAllChatsAsReadOnServerExplicitly", 1)[1].split("public func getRelativeUnreadChatListIndex", 1)[0]
        self.assertIn("maxId: Int32.max - 1", read_all)
        self.assertIn("let batchSize = 16", read_all)
        self.assertIn("_internal_markAllChatsAsReadLocally", read_all)
        self.assertIn('title: "Прочтение завершено"', action)
        self.assertIn("result.failed", action)

    def test_main_settings_has_both_actions(self):
        source = (UI / "Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoSettingsItems.swift").read_text()
        self.assertIn('text: "Прочитать локально"', source)
        self.assertIn('text: "Прочитать на сервере"', source)
        self.assertIn("items[.shadowReads]", source)

    def test_protected_forward_is_one_copy_action(self):
        menu = (UI / "Sources/ChatInterfaceStateContextMenus.swift").read_text()
        # Only real copy protection forwards as a copy; a private channel without
        # restrictions forwards natively.
        self.assertIn("let shouldForwardAsCopy = !shadowDisguiseFull && isServerCopyProtected", menu)
        self.assertNotIn("isPrivateChannel", menu)
        panel = (UI / "Components/Chat/ChatMessageSelectionInputPanelNode/Sources/ChatMessageSelectionInputPanelNode.swift").read_text()
        self.assertNotIn("channel.addressName == nil", panel.split("private var shouldForwardAsCopy")[1].split("@objc private func forwardButtonPressed")[0])
        protected = menu.split("if shouldForwardAsCopy {", 1)[1].split("} else if data.messageActions.options.contains(.forward)", 1)[0]
        self.assertEqual(protected.count("ContextMenuActionItem"), 1)
        self.assertIn("forwardMessagesAsCopy", protected)
        self.assertNotIn("without author", protected.lower())

    def test_forward_owns_temp_file_until_enqueue(self):
        source = (UI / "Sources/ChatControllerForwardMessages.swift").read_text()
        self.assertIn("ayuTemporaryUploadCopy", source)
        self.assertIn("EngineTempBox.shared.dispose", source)
        self.assertIn("finishCopyEnqueue()", source)

    def test_chat_rules_are_account_scoped_and_used(self):
        settings = (CORE / "AyuGram/AyuGramSettings.swift").read_text()
        reads = (CORE / "State/SynchronizePeerReadState.swift").read_text()
        typing = (CORE / "State/ManagedLocalInputActivities.swift").read_text()
        self.assertIn("chatPrivacyRules", settings)
        self.assertIn("suppressReadReceipts(peerId: peerId)", reads)
        self.assertIn("suppressInputActivity(peerId: peerId", typing)
        self.assertTrue((SETTINGS_UI / "ShadowChatPrivacyController.swift").exists())

        profile = (UI / "Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoProfileItems.swift").read_text()
        menu = (UI / "Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreenPerformButtonAction.swift").read_text()
        self.assertNotIn('text: "Правила Shadow"', profile)
        self.assertIn('text: "Правила Shadow"', menu)
        self.assertIn("shadowChatPrivacyController(context: self.context", menu)
        self.assertIn("user.botInfo == nil", menu)

    def test_settings_store_chat_rules_without_mixing_dictionary_keys_and_values(self):
        settings = (CORE / "AyuGram/AyuGramSettings.swift").read_text()
        self.assertIn("private struct ShadowChatPrivacyRuleRecord", settings)
        self.assertIn('forKey: "chatPrivacyRulesV2"', settings)
        self.assertIn("try container.encode(self.readReceipts", settings)
        self.assertNotIn('try container.encode(self.chatPrivacyRules, forKey: "chatPrivacyRules")', settings)

    def test_filters_and_edit_comparison_have_visible_entries(self):
        hub = (SETTINGS_UI / "AyuGramSettingsController.swift").read_text()
        history = (SETTINGS_UI / "AyuArchiveChatContents.swift").read_text()
        menu = (UI / "Sources/ChatInterfaceStateContextMenus.swift").read_text()
        self.assertIn('title: "Фильтры"', hub)
        self.assertIn("Скрыто локальным фильтром", (UI / "Sources/ChatHistoryEntriesForView.swift").read_text())
        self.assertIn("ayuEditComparisonChatController", history)
        self.assertIn('text: "Сравнить правки"', menu)
        self.assertIn("showEditComparisonAction", hub)
        self.assertIn("ayuGramSettingsCurrent.showEditComparisonAction", menu)

    def test_filter_hides_a_whole_media_album_as_one_safe_placeholder(self):
        source = (UI / "Sources/ChatHistoryEntriesForView.swift").read_text()
        block = source.split("case let .MessageGroupEntry(_, messages, presentation):", 1)[1].split("case let .MessageEntry", 1)[0]
        self.assertIn("guard let hiddenItem = messages.first", block)
        self.assertIn("shadowFilteredPlaceholder(message, text: placeholderText(message))", block)
        self.assertIn("return [.MessageEntry(placeholder", block)
        self.assertNotIn("return messages.map", block)
        self.assertIn("private func shadowFilteredPlaceholder", source)
        for safe_field in ("groupingKey: nil", "forwardInfo: nil", "attributes: []", "media: []", "associatedMedia: [:]"):
            self.assertIn(safe_field, source)

    def test_hidden_accounts_are_local_and_filtered_from_switcher(self):
        storage = (CORE / "AyuGram/ShadowHiddenAccounts.swift").read_text()
        hub = (SETTINGS_UI / "AyuGramSettingsController.swift").read_text()
        settings_screen = (UI / "Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreen.swift").read_text()
        self.assertIn("shadow.hiddenAccountPeerIds.v1", storage)
        self.assertIn('title: "Скрытие аккаунтов"', hub)
        self.assertIn("ShadowHiddenAccounts.setHidden", hub)
        self.assertIn("context.sharedContext.activeAccountContexts", hub)
        self.assertNotIn("activeAccountsAndPeers(context: context)", hub)
        self.assertIn("ShadowHiddenAccounts.signal()", settings_screen)
        self.assertIn("!hiddenIds.contains", settings_screen)

    def test_main_settings_use_requested_flat_sections(self):
        hub = (SETTINGS_UI / "AyuGramSettingsController.swift").read_text()
        expected = [
            "Кастомизация",
            "Шпион",
            "Призрак",
            "Фильтры",
            "Подмена профиля",
            "Скрытие аккаунтов",
            "Резервная копия настроек",
            "Разное",
        ]
        root = hub.split("private enum AyuHubEntry", 1)[1].split("private final class AyuHubArguments", 1)[0]
        for title in expected:
            self.assertIn(f'title: "{title}"', root)
        self.assertIn("entries += [.customization, .spy, .ghost, .filters, .misc, .hiddenAccounts, .settingsSync, .backup, .pushDiagnostics, .quickReplies, .chatLocks, .secondSpace, .emergency, .infoFooter]", hub)

    def test_account_addition_has_no_client_premium_limit(self):
        paths = [
            SETTINGS_UI / "LogoutOptionsController.swift",
            SETTINGS_UI / "DeleteAccountOptionsController.swift",
            SETTINGS_UI / "Search/SettingsSearchableItems.swift",
            UI / "Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreenSettingsActions.swift",
        ]
        for path in paths:
            source = path.read_text()
            self.assertNotIn("maximumAvailableAccounts", source, path)
            self.assertNotIn("maximumNumberOfAccounts", source, path)

    def test_cleanup_and_restore_regressions(self):
        store = (CORE / "AyuGram/AyuForkStore.swift").read_text()
        media = (CORE / "AyuGram/AyuSavedMedia.swift").read_text()
        transfer = (CORE / "AyuGram/ShadowSettingsTransfer.swift").read_text()
        self.assertNotIn("maxEntries = 5000", store)
        self.assertIn("keepPeerIds.contains(ref.peer)", store)
        self.assertIn("messagesRemoved", media)
        self.assertIn("max(current.ghostLastSeenTimestamp", transfer)

    def test_history_range_trim_restores_already_kept_deleted_messages(self):
        anti_delete = (CORE / "AyuGram/AyuGramAntiDelete.swift").read_text()
        state = (ROOT / "submodules/TelegramCore/Sources/State/AccountStateManagementUtils.swift").read_text()

        self.assertIn("func ayuGramKeptDeletedMessagesInRange", anti_delete)
        self.assertIn("message.attributes.contains(where: { $0 is DeletedMessageAttribute })", anti_delete)
        trim = state.split("case let .UpdateMinAvailableMessage(id):", 1)[1].split("case let .UpdatePeerChatInclusion", 1)[0]
        self.assertIn("ayuGramKeptDeletedMessagesInRange", trim)
        self.assertIn("transaction.addMessages(keptDeletedMessages, location: .Random)", trim)
        self.assertIn("keptResourceIdSet.contains", trim)
        # The range trim is also sent for "clear history for me"; it must not
        # turn the cleared range into anti-delete ghosts.
        kept_range = anti_delete.split("func ayuGramKeptDeletedMessagesInRange", 1)[1].split("\nfunc ", 1)[0]
        self.assertNotIn("scanTopMessages", kept_range)
        self.assertNotIn("ayuGramMarkMessagesDeleted", kept_range)
        # Every caller must match the signature (no mediaBox argument).
        for path in ROOT.joinpath("submodules/TelegramCore/Sources").rglob("*.swift"):
            for call in path.read_text().split("ayuGramKeptDeletedMessagesInRange(")[1:]:
                self.assertNotIn("mediaBox:", call.split(")", 1)[0], str(path))

    def test_screenshot_notices_are_never_sent(self):
        core = (CORE / "SecretChats/SetSecretChatMessageAutoremoveTimeoutInteractively.swift").read_text()
        body = core.split("func _internal_addSecretChatMessageScreenshot", 1)[1].split("enqueueMessages", 1)[0]
        self.assertIn("shadowSuppressScreenshotNotices", body)
        preview = (ROOT / "submodules/GalleryUI/Sources/SecretMediaPreviewController.swift").read_text()
        handler = preview.split("screenCaptureEvents()", 1)[1].split("historyScreenshot", 1)[0]
        self.assertIn("shadowSuppressScreenshotNotices", handler)
        switch = (CORE / "AyuGram/ShadowScreenshotNotices.swift").read_text()
        self.assertIn("shadowSuppressScreenshotNotices: Bool = true", switch)

    def test_secret_chat_media_is_capturable(self):
        gallery = (ROOT / "submodules/GalleryUI/Sources/Items/ChatImageGalleryItem.swift").read_text()
        line = [l for l in gallery.splitlines() if "self.imageNode.captureProtected =" in l][0]
        self.assertNotIn("SecretChat", line)
        self.assertNotIn("isSecret", line)
        controller = (ROOT / "submodules/TelegramUI/Sources/ChatController.swift").read_text()
        pinch = controller.split("makePinchController(", 1)[0].rsplit("let isSecret", 1)[1]
        self.assertNotIn("SecretChat", pinch.split("\n", 1)[0])

    def test_kept_deleted_messages_disable_server_actions(self):
        menus = (ROOT / "submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift").read_text()
        self.assertIn("ayuIsKeptDeleted", menus)
        common = (ROOT / "submodules/TelegramUI/Components/Chat/ChatMessageItemCommon/Sources/ChatMessageItemCommon.swift").read_text()
        reactions = common.split("func canAddMessageReactions", 1)[1].split("\npublic func ", 1)[0]
        self.assertIn("DeletedMessageAttribute", reactions)


if __name__ == "__main__":
    unittest.main()

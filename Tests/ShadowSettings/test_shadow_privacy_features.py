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
        self.assertIn("maxId: index.id.id", explicit)
        self.assertIn("messages.readDiscussion", explicit)
        self.assertNotIn("suppressReadReceipts", explicit)

    def test_main_settings_has_both_actions(self):
        source = (UI / "Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoSettingsItems.swift").read_text()
        self.assertIn('text: "Прочитать локально"', source)
        self.assertIn('text: "Прочитать на сервере"', source)
        self.assertIn("items[.shadowReads]", source)

    def test_private_or_protected_forward_is_one_copy_action(self):
        menu = (UI / "Sources/ChatInterfaceStateContextMenus.swift").read_text()
        self.assertIn("let shouldForwardAsCopy = isServerCopyProtected || isPrivateChannel", menu)
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

    def test_filters_and_edit_comparison_have_visible_entries(self):
        hub = (SETTINGS_UI / "AyuGramSettingsController.swift").read_text()
        history = (SETTINGS_UI / "AyuArchiveChatContents.swift").read_text()
        menu = (UI / "Sources/ChatInterfaceStateContextMenus.swift").read_text()
        self.assertIn('title: "Фильтры сообщений"', hub)
        self.assertIn("Скрыто локальным фильтром", (UI / "Sources/ChatHistoryEntriesForView.swift").read_text())
        self.assertIn("ayuEditComparisonChatController", history)
        self.assertIn('text: "Сравнить правки"', menu)

    def test_cleanup_and_restore_regressions(self):
        store = (CORE / "AyuGram/AyuForkStore.swift").read_text()
        media = (CORE / "AyuGram/AyuSavedMedia.swift").read_text()
        transfer = (CORE / "AyuGram/ShadowSettingsTransfer.swift").read_text()
        self.assertNotIn("maxEntries = 5000", store)
        self.assertIn("keepPeerIds.contains(ref.peer)", store)
        self.assertIn("messagesRemoved", media)
        self.assertIn("max(current.ghostLastSeenTimestamp", transfer)


if __name__ == "__main__":
    unittest.main()

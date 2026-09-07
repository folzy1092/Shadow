from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / "submodules/TelegramCore/Sources"
AYU = CORE / "AyuGram"
SETTINGS_UI = ROOT / "submodules/SettingsUI/Sources"


class SecretChatPreservationContracts(unittest.TestCase):
    def test_setting_is_explicit_opt_in_and_transferable(self):
        settings = (AYU / "AyuGramSettings.swift").read_text()
        document = (AYU / "ShadowSettingsDocument.swift").read_text()
        transfer = (AYU / "ShadowSettingsTransfer.swift").read_text()

        self.assertIn("public var keepDeletedSecretChatMessages: Bool", settings)
        self.assertIn("keepDeletedSecretChatMessages: false", settings)
        self.assertIn('forKey: "keepDeletedSecretChatMessages"', settings)
        self.assertIn('"keepDeletedSecretChatMessages"', document)
        self.assertIn('"keepDeletedSecretChatMessages": \\.keepDeletedSecretChatMessages', transfer)

    def test_spy_screen_has_separate_secret_chat_toggle(self):
        controller = (SETTINGS_UI / "AyuGramSettingsController.swift").read_text()
        search = (SETTINGS_UI / "ShadowSettingsSearchIndex.swift").read_text()

        self.assertIn('title: "Сохранять удалённые в секретных чатах"', controller)
        self.assertIn("s.keepDeletedSecretChatMessages = value", controller)
        self.assertIn('title: "Сохранять удалённые в секретных чатах"', search)

    def test_secret_delete_and_clear_history_use_archive_path(self):
        processor = (CORE / "State/ProcessSecretChatIncomingDecryptedOperations.swift").read_text()
        anti_delete = (AYU / "AyuGramAntiDelete.swift").read_text()

        self.assertIn("keepDeletedSecretChatMessages", processor)
        self.assertIn("ayuGramMarkMessagesDeleted", processor)
        self.assertIn("ayuGramHandleSecretChatClearHistory", processor)
        self.assertIn("Namespaces.Message.SecretIncoming", anti_delete)
        self.assertIn("Namespaces.Message.SecretOutgoing", anti_delete)
        self.assertIn("ayuForkStoreRecordKeptDeleted", anti_delete)

    def test_downloaded_secret_media_is_copied_and_view_once_is_retained(self):
        saved_media = (AYU / "AyuSavedMedia.swift").read_text()
        consumed = (CORE / "TelegramEngine/Messages/MarkMessageContentAsConsumedInteractively.swift").read_text()

        self.assertIn("preserveSecretChatMedia", saved_media)
        self.assertIn("currentAyuGramSettings(mediaBox: mediaBox).keepDeletedSecretChatMessages", saved_media)
        self.assertIn("keepSecretChatMedia", consumed)
        self.assertIn("ayuKeepSelfDestructMedia = settings.keepDeletedSecretChatMessages", consumed)


if __name__ == "__main__":
    unittest.main()

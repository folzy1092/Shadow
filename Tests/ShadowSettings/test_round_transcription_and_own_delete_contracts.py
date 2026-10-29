"""Source contracts for round-video transcription on the device and «Удалить мои сообщения»."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SUB = ROOT / "submodules"


def read(path):
    return (SUB / path).read_text(encoding="utf-8")


class RoundVideoTranscriptionContracts(unittest.TestCase):
    NODE = "TelegramUI/Components/Chat/ChatMessageInteractiveInstantVideoNode/Sources/ChatMessageInteractiveInstantVideoNode.swift"

    def test_audio_track_is_extracted_locally(self):
        source = read("Media/LocalAudioTranscription/Sources/LocalAudioTranscription.swift")
        self.assertIn("public func extractAudioTrackForTranscription(videoPath: String)", source)
        self.assertIn("AVAssetExportPresetAppleM4A", source)
        self.assertIn("shadow-round-\\(token).mp4", source)
        self.assertIn("linkItem(atPath: videoPath", source)

    def test_round_videos_use_the_voice_toggle(self):
        node = read(self.NODE)
        helper = node.split("private func shadowUsesLocalRoundVideoTranscription", 1)[1]
        self.assertIn("!item.associatedData.isPremium", helper)
        self.assertIn("Namespaces.Peer.SecretChat", helper)
        self.assertIn("isInstantVideo", helper)
        self.assertIn(".localVoiceTranscription", helper)

    def test_button_and_local_path(self):
        node = read(self.NODE)
        self.assertIn("import LocalAudioTranscription", node)
        self.assertIn("&& shadowUsesLocalRoundVideoTranscription(item: item)", node)
        self.assertIn("if !shadowLocalTranscription && transcriptionText == nil", node)
        self.assertIn("extractAudioTrackForTranscription(videoPath: path)", node)
        self.assertIn("storeLocallyTranscribedAudio(messageId: messageId", node)
        build = (SUB / "TelegramUI/Components/Chat/ChatMessageInteractiveInstantVideoNode/BUILD").read_text(encoding="utf-8")
        self.assertIn('"//submodules/Media/LocalAudioTranscription"', build)


class DeleteOwnMessagesContracts(unittest.TestCase):
    CORE = "TelegramCore/Sources/AyuGram/ShadowDeleteOwnMessages.swift"
    MENU = "ChatListUI/Sources/ChatContextMenus.swift"

    def test_search_is_server_side_from_self(self):
        core = read(self.CORE)
        self.assertIn("fromId: accountPeerId", core)
        self.assertIn('query: ""', core)
        self.assertIn("type: .forEveryone", core)
        self.assertIn("pageDelay", core)

    def test_availability(self):
        core = read(self.CORE)
        availability = core.split("public static func isAvailable", 1)[1].split("static func idsToDelete", 1)[0]
        self.assertIn("user.id != accountPeerId", availability)
        self.assertIn("default:\n            // Secret chats", availability.replace("\r\n", "\n"))
        self.assertIn("case .group = channel.info", availability)

    def test_periods(self):
        core = read(self.CORE)
        for title in ("За последние 24 часа", "За последнюю неделю", "За последний месяц", "За всё время"):
            self.assertIn(f'"{title}"', core)

    def test_menu_item_confirms_and_can_stop(self):
        menu = read(self.MENU)
        self.assertIn('"Удалить мои сообщения"', menu)
        self.assertIn("shadowConfirmDeleteOwnMessages(context: context, peerId: peerId, period: period", menu)
        confirm = menu.split("func shadowConfirmDeleteOwnMessages", 1)[1]
        self.assertIn("ShadowDeleteOwnMessages.isAvailable(peer: peer", confirm)
        self.assertIn("type: .destructiveAction", confirm)
        run = menu.split("private func shadowRunDeleteOwnMessages", 1)[1]
        self.assertIn('customUndoText: "Стоп"', run)
        self.assertIn("disposable.dispose()", run)


if __name__ == "__main__":
    unittest.main()

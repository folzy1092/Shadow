"""Source contracts for the deleted / edited archive split."""
from pathlib import Path
import unittest

SUB = Path(__file__).resolve().parents[2] / "submodules"


def read(path):
    return (SUB / path).read_text(encoding="utf-8")


class ArchiveSplitContracts(unittest.TestCase):
    def test_deleted_tab_shows_only_deleted_messages(self):
        archive = read("SettingsUI/Sources/AyuArchiveChatContents.swift")
        self.assertIn("guard message.attributes.contains(where: { $0 is DeletedMessageAttribute }) else {", archive)
        self.assertIn("refs = store.keptDeleted", archive)
        self.assertIn("refs = store.editHistory", archive)
        self.assertNotIn("store.keptDeleted + store.editHistory", archive)
        self.assertIn("public func ayuEditedArchiveChatController(context: AccountContext, peerId: PeerId? = nil) -> ViewController", archive)

    def test_deleted_media_comes_back_from_the_fork_copy(self):
        archive = read("SettingsUI/Sources/AyuArchiveChatContents.swift")
        self.assertIn("AyuSavedMedia.restoreMessageMedia(mediaBox: mediaBox, message: message)", archive)
        media = read("TelegramCore/Sources/AyuGram/AyuSavedMedia.swift")
        self.assertIn("public static func restoreMessageMedia(mediaBox: MediaBox, message: Message) -> Int", media)
        self.assertIn("mediaBox.storePathsForId(entry.resource.id).complete", media)

    def test_storage_screen_has_two_tabs(self):
        storage = read("SettingsUI/Sources/AyuForkStorageController.swift")
        self.assertIn("ayuEditedArchiveChatController(context: context, peerId: peerId)", storage)
        self.assertIn("ayuArchiveChatController(context: context, peerId: peerId)", storage)
        self.assertIn('title: "Отредактированные сообщения"', storage)
        self.assertNotIn('"Открыть архив"', storage)


if __name__ == "__main__":
    unittest.main()

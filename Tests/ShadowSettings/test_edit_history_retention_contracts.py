"""Source contracts for «Срок хранения правок» (2.0.0): edit versions age out on their own period."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SUB = ROOT / "submodules"
CORE = "TelegramCore/Sources/AyuGram/"


def read(path):
    return (SUB / path).read_text(encoding="utf-8")


class EditHistoryRetentionContracts(unittest.TestCase):
    def test_setting_is_stored_and_transferred(self):
        settings = read(CORE + "AyuGramSettings.swift")
        self.assertIn("public var editHistoryRetention: Int32", settings)
        self.assertIn("editHistoryRetention: ShadowEditHistoryRetention.followDeleted,", settings)
        self.assertIn('forKey: "editHistoryRetention")', settings)
        self.assertIn('try container.encode(self.editHistoryRetention, forKey: "editHistoryRetention")', settings)
        document = read(CORE + "ShadowSettingsDocument.swift")
        self.assertIn('"editHistoryRetention"', document)
        self.assertIn('key == "editHistoryRetention" && (0...9).contains(number)', document)
        transfer = read(CORE + "ShadowSettingsTransfer.swift")
        self.assertIn('values["editHistoryRetention"] = .integer(Int64(settings.editHistoryRetention))', transfer)
        self.assertIn('case "editHistoryRetention": updated.editHistoryRetention = ShadowEditHistoryRetention.normalized(', transfer)

    def test_link_search_and_row(self):
        links = read(CORE + "ShadowSettingLinks.swift")
        self.assertIn('slug: "edit-history-retention", entryId: 40, key: "editHistoryRetention"', links)
        self.assertIn('"editHistoryRetention": \\.editHistoryRetention', read(CORE + "ShadowSettingLinksApply.swift"))
        self.assertIn("entryId: 40, title: \"Срок хранения правок\"", read("SettingsUI/Sources/ShadowSettingsSearchIndex.swift"))
        ui = read("SettingsUI/Sources/AyuGramSettingsController.swift")
        self.assertIn("case .editHistoryRetention: return 40", ui)
        self.assertIn("case .editHistoryRetention: return 19.1", ui)
        self.assertIn("entries.append(.editHistoryRetention(settings.editHistoryRetention))", ui)
        self.assertIn("s.editHistoryRetention = choice", ui)
        self.assertIn("shadow://spy/edit-history-retention", (ROOT / "docs/shadow-links.md").read_text(encoding="utf-8"))

    def test_cleanup_prunes_versions_with_their_own_period(self):
        media = read(CORE + "AyuSavedMedia.swift")
        self.assertIn("ShadowEditHistoryRetention.maxAge(choice: settings.editHistoryRetention, deletedMaxAge: settings.mediaAutoCleanInterval)", media)
        # Both the periodic pass and the «run now» button prune.
        self.assertEqual(media.count("ayuForkStorePruneEditHistory(transaction: transaction"), 2)
        store = read(CORE + "AyuForkStore.swift")
        prune = store[store.index("func ayuForkStorePruneEditHistory"):]
        prune = prune[:prune.index("// Strip the stored edit versions")]
        self.assertIn("guard maxAge > 0 else", prune)
        self.assertIn("keepPeerIds.contains(ref.peer)", prune)
        self.assertIn("ShadowEditHistoryRetention.isExpired(versionDate: $0.date, now: now, maxAge: maxAge)", prune)
        # A message with no version left loses the attribute and leaves the index.
        self.assertIn("if !kept.isEmpty {\n                attributes.append(SavedMessageEditsAttribute(versions: kept))", prune)
        self.assertIn("if !kept.isEmpty {\n            remaining.append(ref)", prune)
        self.assertIn("AyuSavedMedia.removeEditHistoryMedia(", prune)


if __name__ == "__main__":
    unittest.main()

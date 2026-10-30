"""Source contracts for the account backup in the keychain (2.1.0, docs/specs/2026-10-30-shadow-2.1.0-session-backup.md)."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SUB = ROOT / "submodules"


def read(path):
    return (SUB / path).read_text(encoding="utf-8")


class SessionBackupContracts(unittest.TestCase):
    def setUp(self):
        self.core = read("TelegramCore/Sources/AyuGram/ShadowSessionBackup.swift")

    def test_storage_is_local_but_in_encrypted_backups(self):
        # Folzy's decision: no iCloud Keychain, but carried by an encrypted iPhone backup.
        self.assertIn("kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked\n", self.core)
        self.assertNotIn("ThisDeviceOnly", self.core.split("// MARK: - Keychain")[1])
        self.assertNotIn("kSecAttrSynchronizable", self.core)

    def test_absent_records_never_wipe_the_backup(self):
        sync = self.core[self.core.index("public static func sync("):self.core.index("private static func reportIfRestoredRecently")]
        # Only a logged-out record removes its item; a fresh install has no records at all.
        self.assertIn("for peerId in loggedOut.subtracting(live)", sync)
        self.assertEqual(sync.count("remove(peerId:"), 1)
        self.assertNotIn("removeAll()", sync)

    def test_restore_skips_present_and_switches(self):
        restore = self.core[self.core.index("public static func restoreAll("):]
        self.assertIn("where !present.contains(entry.peerId)", restore)
        self.assertIn(".backupData(AccountBackupDataAttribute(data: entry.data))", restore)
        self.assertIn("transaction.setCurrentId(firstId)", restore)

    def test_app_keeps_the_backup_in_sync_and_reports_dead_sessions(self):
        shared = read("TelegramUI/Sources/SharedAccountContext.swift")
        self.assertIn("ShadowSessionBackup.sync(records: view.records)", shared)
        self.assertIn("ShadowSessionBackup.restoreFailedNotification", shared)
        self.assertIn('title: "Скопировать"', shared)

    def test_login_screen_offers_one_button_after_face_id(self):
        login = read("AuthorizationUI/Sources/ShadowSessionRestore.swift")
        self.assertIn('"Восстановить аккаунты (\\(count))"', login)
        self.assertIn("evaluatePolicy(.deviceOwnerAuthentication", login)
        self.assertIn("UIPasteboard.general.string = text", login)
        controller = read("AuthorizationUI/Sources/AuthorizationSequencePhoneEntryController.swift")
        self.assertIn("self.shadowOfferSessionRestore()", controller)


if __name__ == "__main__":
    unittest.main()

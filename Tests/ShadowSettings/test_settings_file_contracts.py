"""Source contracts: the settings file type (1.9.1)."""
from pathlib import Path
import plistlib
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class SettingsFileContracts(unittest.TestCase):
    def test_type_declared_in_every_plist(self):
        build = (ROOT / "Telegram/BUILD").read_text(encoding="utf-8")
        exported = build.split("<key>UTExportedTypeDeclarations</key>", 1)[1].split("<key>CFBundleDocumentTypes</key>", 1)[0]
        documents = build.split("<key>CFBundleDocumentTypes</key>", 1)[1].split("<key>LSSupportsOpeningDocumentsInPlace</key>", 1)[0]
        self.assertIn("<string>app.shadow.settings</string>", exported)
        self.assertIn("<string>shadow-settings</string>", exported)
        self.assertIn("<string>app.shadow.settings</string>", documents)
        self.assertNotIn("public.json", documents)
        for name in ("Telegram/Telegram-iOS/InfoBazel.plist", "Telegram/Telegram-iOS/Info.plist"):
            plist = plistlib.loads((ROOT / name).read_bytes())
            self.assertEqual(plist["UTExportedTypeDeclarations"][0]["UTTypeIdentifier"], "app.shadow.settings")
            self.assertEqual(plist["CFBundleDocumentTypes"][0]["LSItemContentTypes"], ["app.shadow.settings"])
            self.assertFalse(plist["LSSupportsOpeningDocumentsInPlace"])
            self.assertEqual(plist["UTImportedTypeDeclarations"][0]["UTTypeIdentifier"], "org.telegram.Telegram-iOS.theme")

    def test_opening_paths(self):
        app = (ROOT / "submodules/TelegramUI/Sources/AppDelegate.swift").read_text(encoding="utf-8")
        self.assertIn("if ShadowSettingsFile.isSettingsFile(url) {", app)
        self.assertIn("appLockContext.isCurrentlyLocked", app.split("private func shadowOpenSettingsFile", 1)[1])
        chat = (ROOT / "submodules/TelegramUI/Sources/OpenChatMessage.swift").read_text(encoding="utf-8")
        self.assertIn("ShadowSettingsFile.isSettingsFileName(fileName)", chat)
        backup = (ROOT / "submodules/SettingsUI/Sources/ShadowSettingsBackupController.swift").read_text(encoding="utf-8")
        self.assertIn("ShadowSettingsFile.exportFileName", backup)
        self.assertIn("if ShadowDisguise.shared.hidesSettings {", backup)
        self.assertIn("Аккаунт: ", backup)
        doc = (ROOT / "submodules/TelegramCore/Sources/AyuGram/ShadowSettingsDocument.swift").read_text(encoding="utf-8")
        self.assertIn('public static let exportFileName = "Shadow.shadow-settings"', doc)

    def test_export_carries_every_setting(self):
        core = ROOT / "submodules/TelegramCore/Sources/AyuGram"
        settings = (core / "AyuGramSettings.swift").read_text(encoding="utf-8")
        transfer = (core / "ShadowSettingsTransfer.swift").read_text(encoding="utf-8")
        encoded = set(re.findall(r'forKey: "(\w+)"\)', settings.split("public func encode(to encoder", 1)[1]))
        exported = set(re.findall(r'"(\w+)"', transfer))
        # Stored under another name in the file, or account state.
        renamed = {"messageFiltersV2", "shadowBannedPeerIdsV1", "headerButtonsV1", "chatPrivacyRulesV2", "messageScreenshot"}
        state = {"ghostLastSeenTimestamp"}
        self.assertEqual(encoded - exported - renamed - state, set())


if __name__ == "__main__":
    unittest.main()

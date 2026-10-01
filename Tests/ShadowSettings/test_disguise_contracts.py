"""Source contracts for the disguise mode (debug menu) and intruder photo delivery."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SUB = ROOT / "submodules"


def read(path):
    return (SUB / path).read_text(encoding="utf-8")


class DisguiseContracts(unittest.TestCase):
    def test_settings_readers_are_masked_but_writes_use_stored_values(self):
        settings = read("TelegramCore/Sources/AyuGram/AyuGramSettings.swift")
        self.assertIn("public static var vanillaSettings: AyuGramSettings", settings)
        self.assertIn("return shadowDisguiseMasked(ayuGramSettingsStateValue)", settings)
        self.assertIn("return shadowDisguiseMasked(storedAyuGramSettings(transaction: transaction))", settings)
        self.assertIn("let current = storedAyuGramSettings(transaction: transaction)", settings)
        self.assertIn("shadowDisguiseModeSignal())", settings)
        self.assertIn("public func setShadowDisguiseMode(_ mode: ShadowDisguise.Mode)", settings)

    def test_full_mode_turns_off_device_features(self):
        self.assertIn("ShadowDisguise.shared.isFull", read("TelegramCore/Sources/AyuGram/ShadowChatLock.swift"))
        self.assertIn("ShadowDisguise.shared.isFull", read("TelegramCore/Sources/AyuGram/ShadowSpaces.swift"))
        self.assertIn("ShadowDisguise.shared.isFull", read("TelegramCore/Sources/AyuGram/ShadowHiddenAccounts.swift"))
        self.assertIn("!ShadowDisguise.shared.isFull", read("TelegramCore/Sources/AyuGram/ShadowIntruderLog.swift"))
        history = read("TelegramUI/Sources/ChatHistoryEntriesForView.swift")
        self.assertIn("if ShadowDisguise.shared.isFull {", history)
        self.assertIn("$0 is DeletedMessageAttribute", history)

    def test_settings_entry_points_are_hidden(self):
        items = read("TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoSettingsItems.swift")
        self.assertIn("let shadowShowsSettings = !ShadowDisguise.shared.hidesSettings", items)
        chat_list = read("ChatListUI/Sources/ChatListController.swift")
        self.assertIn("ghostContextAction = { [weak self] _, _ in", chat_list)

    def test_debug_menu_switch_needs_owner(self):
        debug = read("DebugSettingsUI/Sources/DebugController.swift")
        self.assertIn("case shadowDisguise(ShadowDisguise.Mode, Bool)", debug)
        self.assertIn("ShadowDisguise.requiresAuthentication(from: current, to: target)", debug)
        self.assertIn("sharedContext.shadowDisguiseAuthenticate(", debug)
        # The disguise rows sit below "Network X" / "Download X".
        self.assertLess(debug.index("entries.append(.enableNetworkExperiments("), debug.index("entries.append(.shadowDisguise(mode"))

    def test_intruder_photo_goes_to_gallery_and_waits_for_capture(self):
        camera = read("PasscodeUI/Sources/ShadowIntruderCamera.swift")
        self.assertIn("PHAssetCreationRequest.forAsset()", camera)
        self.assertNotIn("requestAuthorization", camera.split("private static func saveToPhotoLibrary")[1])
        delivery = read("TelegramUI/Sources/ShadowIntruderDelivery.swift")
        self.assertIn("if log.isCapturing {", delivery)
        self.assertIn("ShadowIntruderLog.didSaveNotification", delivery)

    def test_foundation_suite_compiles_disguise(self):
        script = (ROOT / "build-system/ci/test_shadow_foundation.py").read_text(encoding="utf-8")
        self.assertIn("Tests/ShadowSettings/DisguiseTests.swift", script)


if __name__ == "__main__":
    unittest.main()

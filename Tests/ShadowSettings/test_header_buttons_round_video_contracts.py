"""Source contracts: custom header buttons, round video from the gallery, settings sync."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
SUB = ROOT / "submodules"


def read(path):
    return (SUB / path).read_text(encoding="utf-8")


class HeaderButtonsContracts(unittest.TestCase):
    def test_setting_is_stored_and_decoded(self):
        settings = read("TelegramCore/Sources/AyuGram/AyuGramSettings.swift")
        self.assertIn("public var headerButtons: ShadowHeaderButtons = .stock", settings)
        self.assertIn('forKey: "headerButtonsV1"', settings)
        self.assertEqual(settings.count('"headerButtonsV1"'), 2)

    def test_actions_are_stored_as_strings(self):
        # Postbox's Codable adapter traps on raw enums (test_shadow_postbox.py).
        model = read("TelegramCore/Sources/AyuGram/ShadowHeaderButtons.swift")
        self.assertNotIn("ShadowHeaderAction: String, Codable", model)
        self.assertIn("public var actionValue: String", model)
        self.assertIn("Foundation", model)
        self.assertNotIn("import Postbox", model)

    def test_every_action_is_handled(self):
        model = read("TelegramCore/Sources/AyuGram/ShadowHeaderButtons.swift")
        enum = model.split("public enum ShadowHeaderAction", 1)[1].split("public init(storedValue", 1)[0]
        actions = re.findall(r"^\s+case (\w+)$", enum, re.M)
        self.assertGreaterEqual(len(actions), 20)
        chat_list = read("ChatListUI/Sources/ChatListController.swift")
        perform = chat_list.split("fileprivate func shadowPerformHeaderAction", 1)[1]
        icons = chat_list.split("private func shadowHeaderButtonIcon", 1)[1].split("\n}\n", 1)[0]
        for action in actions:
            self.assertIn(f".{action}", perform, action)
            self.assertIn(f".{action}", icons, action)

    def test_header_uses_custom_buttons_outside_disguise(self):
        chat_list = read("ChatListUI/Sources/ChatListController.swift")
        self.assertIn("!ShadowDisguise.shared.isFull && !shadowHeader.buttons.isStock", chat_list)
        self.assertIn("extraLeftButtons: primaryContext.extraLeftButtons", chat_list)
        self.assertIn("if let shadowRightButtons = self.shadowRightButtons", chat_list)
        header = read("TelegramUI/Components/ChatListHeaderComponent/Sources/ChatListHeaderComponent.swift")
        self.assertIn("allLeftButtons.append(contentsOf: content.extraLeftButtons)", header)
        # The stories header copies the content; it must keep the extra buttons.
        self.assertIn("extraLeftButtons: primaryContent.extraLeftButtons", header)

    def test_settings_screen_is_reachable(self):
        ui = read("SettingsUI/Sources/AyuGramSettingsController.swift")
        self.assertIn("controller?.push(shadowHeaderButtonsController(context: context))", ui)
        router = read("SettingsUI/Sources/ShadowLinkRouter.swift")
        self.assertIn('case "header", "buttons":', router)
        catalog = read("SettingsUI/Sources/ShadowSettingsSearchIndex.swift")
        self.assertIn('entryId: 111, title: "Кнопки шапки"', catalog)


class RoundVideoContracts(unittest.TestCase):
    def test_editor_toggle(self):
        interface = read("LegacyComponents/Sources/TGMediaPickerGalleryInterfaceView.m")
        self.assertIn("@selector(toggleSendAsRound)", interface)
        self.assertIn("_roundButton.selected = isRoundVideo;", interface)
        self.assertIn("if (adjustments.sendAsGif || isRoundVideo)", interface)
        item = read("LegacyComponents/Sources/TGMediaPickerGalleryVideoItemView.m")
        self.assertIn("- (void)toggleSendAsRound", item)
        self.assertIn("TGVideoEditMaximumRoundVideoDuration", item)
        self.assertIn("_playerView.layer.cornerRadius = isRound", item)

    def test_preview_and_converter_use_the_same_square(self):
        adjustments = read("LegacyComponents/Sources/TGVideoEditAdjustments.m")
        self.assertIn("const NSTimeInterval TGVideoEditMaximumRoundVideoDuration = 60.0;", adjustments)
        self.assertIn("roundVideoCropRectForCropRect:_cropRect originalSize:_originalSize", adjustments)
        item = read("LegacyComponents/Sources/TGMediaPickerGalleryVideoItemView.m")
        self.assertIn("[TGVideoEditAdjustments roundVideoCropRectForCropRect:cropRect originalSize:_videoDimensions]", item)

    def test_sent_as_round_video(self):
        pickers = read("LegacyMediaPickerUI/Sources/LegacyMediaPickers.swift")
        self.assertIn("roundAdjustments.isRoundVideo()", pickers)
        self.assertIn("isRoundVideo ? [.instantRoundVideo] : [.supportsStreaming]", pickers)
        self.assertIn("localGroupingKey: isRoundVideo ? nil : item.groupedId", pickers)
        self.assertIn("caption = nil", pickers)


class SettingsSyncContracts(unittest.TestCase):
    def test_sync_reads_stored_values(self):
        settings = read("TelegramCore/Sources/AyuGram/AyuGramSettings.swift")
        stored = settings.split("public func shadowStoredAyuGramSettings(postbox: Postbox)", 1)[1].split("\n}\n", 1)[0]
        self.assertNotIn("shadowDisguiseMasked", stored)
        manager = read("TelegramUI/Sources/ShadowSettingsSyncManager.swift")
        self.assertIn("shadowStoredAyuGramSettings(postbox:", manager)
        self.assertNotIn("currentAyuGramSettings", manager)
        self.assertNotIn("ayuGramSettingsCurrent", manager)

    def test_runtime_state_is_not_synced(self):
        sync = read("TelegramCore/Sources/AyuGram/ShadowSettingsSync.swift")
        self.assertIn("result.ghostLastSeenTimestamp = target.ghostLastSeenTimestamp", sync)

    def test_installed_and_reachable(self):
        shared = read("TelegramUI/Sources/SharedAccountContext.swift")
        self.assertIn("ShadowSettingsSyncManager.install(sharedContext: self)", shared)
        ui = read("SettingsUI/Sources/AyuGramSettingsController.swift")
        self.assertIn("func shadowSettingsSyncController(context: AccountContext)", ui)
        self.assertIn("shadowStoredAyuGramSettingsOnce(postbox: context.account.postbox)", ui)
        router = read("SettingsUI/Sources/ShadowLinkRouter.swift")
        self.assertIn('case "sync":', router)


if __name__ == "__main__":
    unittest.main()

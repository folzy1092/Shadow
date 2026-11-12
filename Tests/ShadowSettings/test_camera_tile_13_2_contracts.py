"""Source contracts: the gallery camera tile and «кружок из галереи» on Telegram 13.2 (Shadow 2.3.1).

13.2 moved the chat attachment gallery to MediaGrid v2, the in-tile camera to the new chat camera and the
gallery to ChatMediaEditorScreen, all on by default; the fork's tile settings and round-video button were
wired to the old paths only.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SUB = ROOT / "submodules"


def read(path):
    return (SUB / path).read_text(encoding="utf-8")


class CompactTileOnMediaGridContracts(unittest.TestCase):
    def test_layer_grid_reserves_the_cutout_rows(self):
        grid = read("TelegramUI/Components/MediaGrid/Sources/MediaGridView.swift")
        self.assertIn("public var cameraSlotRows: Int = 2", grid)
        self.assertIn("return mediaGridCameraSlots(rows: self.cameraSlotRows)", grid)
        self.assertNotIn("private static let cameraSlots", grid)
        self.assertIn("reservedFrame(self.cameraSlotSet)", grid)
        host = read("MediaPickerUI/Sources/MediaPickerMediaGridHost.swift")
        self.assertIn("self.cameraSlotRows = mediaPickerGridCameraSlotRows(cameraHeight: cameraCutout.height", host)
        self.assertIn("gridView.cameraSlotRows = self.cameraSlotRows", host)
        self.assertIn("func mediaPickerGridCameraSlotRows(", read("MediaPickerUI/Sources/MediaPickerGridCellDecorations.swift"))
        self.assertIn("func testCompactCameraTakesOneSlot()", read("TelegramUI/Components/MediaGrid/Tests/MediaGridViewTests.swift"))


class NewCameraToggleContracts(unittest.TestCase):
    def test_setting_is_stored_portable_and_linked(self):
        settings = read("TelegramCore/Sources/AyuGram/AyuGramSettings.swift")
        self.assertEqual(settings.count('"cameraTileNewCamera"'), 2)
        self.assertIn("cameraTileNewCamera: false,", settings)
        self.assertIn('forKey: "cameraTileNewCamera")) ?? 0) != 0', settings)
        self.assertIn('"cameraTileNewCamera"', read("TelegramCore/Sources/AyuGram/ShadowSettingsDocument.swift"))
        self.assertIn('"cameraTileNewCamera": \\.cameraTileNewCamera', read("TelegramCore/Sources/AyuGram/ShadowSettingsTransfer.swift"))
        self.assertIn('slug: "camera-new", entryId: 142, key: "cameraTileNewCamera"', read("TelegramCore/Sources/AyuGram/ShadowSettingLinks.swift"))
        self.assertIn("entryId: 142", read("SettingsUI/Sources/ShadowSettingsSearchIndex.swift"))
        hub = read("SettingsUI/Sources/AyuGramSettingsController.swift")
        self.assertIn("case .cameraTileNewCamera: return 142", hub)
        self.assertIn("entries.append(.cameraTileNewCamera(settings.cameraTileNewCamera))", hub)
        self.assertIn("`shadow://customization/camera-new`", (ROOT / "docs/shadow-links.md").read_text(encoding="utf-8"))

    def test_off_keeps_the_legacy_tile_camera(self):
        picker = read("MediaPickerUI/Sources/MediaPickerScreen.swift")
        self.assertIn("controller.opensChatCameraWithHolder && ayuGramSettingsCurrent.cameraTileNewCamera,", picker)


class RoundVideoInNewGalleryContracts(unittest.TestCase):
    def test_flag_lives_in_the_item_store_not_in_legacy_adjustments(self):
        # The editor clears legacy adjustments when it writes an edited thumbnail, so a VideoMessage
        # preset stored there while editing would be lost silently.
        self.assertIn("public var shadowRoundVideoIds = Set<String>()", read("TelegramUI/Components/ChatMediaSend/Sources/ChatMediaEditorItemStore.swift"))
        writer = read("TelegramUI/Components/ChatMediaEditorScreen/Sources/ChatMediaEditorLegacyGallery.swift")
        self.assertIn("target.clearAdjustments(uniqueId)", writer)

    def test_marked_video_goes_through_the_legacy_converter(self):
        mapping = read("TelegramUI/Components/ChatMediaSend/Sources/MediaPickerChatMediaSendMapping.swift")
        self.assertIn("if shadowRoundVideoIsActive(uniqueId: uniqueId, source: source, editing: editing, store: store) {\n        return .legacyAdjustments", mapping)
        self.assertIn("caption: isRoundVideo ? nil : editing.caption(for: uniqueId),", mapping)
        self.assertIn("excludedFromGrouping: isRoundVideo", mapping)
        picker = read("MediaPickerUI/Sources/MediaPickerScreen.swift")
        apply = "shadowApplyRoundVideoAdjustments(legacyContext: legacyContext, editingContext: interaction.editingState, store: store)"
        self.assertIn(apply, picker)
        self.assertLess(picker.index(apply), picker.index("if let fallback = mediaPickerChatMediaSendFallback("))
        self.assertIn("roundVideoIds.contains(uniqueId)", picker)
        send = read("MediaPickerUI/Sources/ShadowRoundVideoSend.swift")
        self.assertIn("preset: TGMediaVideoConversionPresetVideoMessage", send)
        self.assertIn("current.isRoundVideo()", send)
        legacy = read("LegacyMediaPickerUI/Sources/LegacyMediaPickers.swift")
        self.assertIn("roundAdjustments.roundVideoAdjustments(withDuration: sourceDuration)", legacy)

    def test_editor_button_and_preview(self):
        screen = read("TelegramUI/Components/ChatMediaEditorScreen/Sources/ChatMediaEditorScreen.swift")
        self.assertIn("self.updateMuteButton(layout: layout, safeInsets: safeInsets, transition: transition)\n            self.shadowUpdateRoundVideo(transition: transition)", screen)
        round_ui = read("TelegramUI/Components/ChatMediaEditorScreen/Sources/ChatMediaEditorScreenShadowRound.swift")
        self.assertIn("store.shadowSetRoundVideo(isRound, for: uniqueId)", round_ui)
        self.assertIn("self.previewContainerView.layer.mask = mask", round_ui)
        self.assertIn("self.shadowDismissRoundTooltip()", read("TelegramUI/Components/ChatMediaEditorScreen/Sources/ChatMediaEditorScreenMute.swift"))
        self.assertIn("final class ShadowRoundVideoTests", read("TelegramUI/Components/ChatMediaSend/Tests/ShadowRoundVideoTests.swift"))


if __name__ == "__main__":
    unittest.main()

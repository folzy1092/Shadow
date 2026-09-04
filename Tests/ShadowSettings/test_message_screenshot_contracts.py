"""Integration checks only. Native rendering also needs Xcode/device verification."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class MessageScreenshotContracts(unittest.TestCase):
    def test_controller_uses_isolated_render_and_preserves_selection(self):
        source = (ROOT / 'submodules/TelegramUI/Sources/Chat/ChatControllerMessageScreenshot.swift').read_text()
        self.assertIn('makeChatMessagePreviewItem', source)
        self.assertIn('transaction.getMessage', source)
        self.assertIn('sorted { $0.index < $1.index }', source)
        self.assertNotIn('cancelMessageSelection', source)
        self.assertNotIn('markMessage', source)
        self.assertIn('downloads.cellular.enabled = false', source)
        self.assertIn('downloads.wifi.enabled = false', source)
        self.assertIn('AutoclearTimeoutMessageAttribute', source)
        self.assertIn('messages.count == ids.count', source)
        self.assertIn('popoverPresentationController?.barButtonItem', source)

    def test_renderer_prepares_real_neighbors_for_native_merge(self):
        source = (ROOT / 'submodules/TelegramUI/Sources/Chat/ChatControllerMessageScreenshot.swift').read_text()
        self.assertIn('private var preparedItems: [ChatMessageItemImpl] = []', source)
        self.assertIn('private func prepareItems() -> Bool', source)
        self.assertNotIn('previousItem: nil, nextItem: nil', source)
        self.assertIn('previousItem: previousItem', source)
        self.assertIn('nextItem: nextItem', source)
        self.assertIn('message.effectivelyIncoming(', source)

    def test_options_live_in_customization(self):
        source = (ROOT / 'submodules/SettingsUI/Sources/AyuGramSettingsController.swift').read_text()
        self.assertIn('case .messageScreenshot: return AyuCustomizationSection.appearance.rawValue', source)
        source = (ROOT / 'submodules/SettingsUI/Sources/ShadowMessageScreenshotSettingsController.swift').read_text()
        for key in ('enabled', 'showAvatars', 'showNames', 'showBadges', 'showTime'):
            self.assertIn('path = \\.' + key, source)
        self.assertIn('ayuGramSettings(postbox: context.account.postbox)', source)
        self.assertNotIn('UserDefaults', source)
        self.assertIn('UIColorPickerViewController', source)
        self.assertIn('supportsAlpha = false', source)
        self.assertIn('colorPickerViewControllerDidSelectColor', source)
        self.assertIn('colorPickerViewControllerDidFinish', source)
        self.assertIn('labelStyle: .color(', source)
        self.assertIn('customColorARGB', source)
        self.assertNotIn('case .white', source)
        self.assertNotIn('case .black', source)

    def test_native_render_dependencies_and_visibility(self):
        source = (ROOT / 'submodules/TelegramUI/Sources/Chat/ChatControllerMessageScreenshot.swift').read_text()
        for value in ('import AlertUI', 'import PresentationDataUtils', 'canReadHistory = false', 'node.visibility = .visible', 'node.updateAbsoluteRect', 'recursivelyEnsureDisplaySynchronously(true)', 'defer { self.content.view.transform = previewTransform }'):
            self.assertIn(value, source)
        media = (ROOT / 'submodules/TelegramUI/Components/Chat/ChatMessageMediaBubbleContentNode/Sources/ChatMessageMediaBubbleContentNode.swift').read_text()
        block = media.split('if item.presentationData.shadowScreenshot != nil {', 1)[1].split('var hasReplyMarkup', 1)[0]
        self.assertIn('automaticPlayback = false', block)
        self.assertIn('automaticDownload = .none', block)

    def test_snapshot_is_opt_in_encoded_and_portable(self):
        source = (ROOT / 'submodules/TelegramPresentationData/Sources/ChatPresentationData.swift').read_text()
        self.assertIn('shadowScreenshot: ShadowMessageScreenshotSettings? = nil', source)
        core = (ROOT / 'submodules/TelegramCore/Sources/AyuGram/AyuGramSettings.swift').read_text()
        self.assertIn('decodeIfPresent(ShadowMessageScreenshotSettings.self', core)
        self.assertIn('encode(self.messageScreenshot', core)

        model = (ROOT / 'submodules/TelegramCore/Sources/AyuGram/ShadowMessageScreenshotSettings.swift').read_text()
        self.assertIn('case customColor = 2', model)
        self.assertIn('public var customColorARGB: Int32', model)
        self.assertIn('legacyWhiteARGB', model)
        self.assertIn('legacyBlackARGB', model)

        document = (ROOT / 'submodules/TelegramCore/Sources/AyuGram/ShadowSettingsDocument.swift').read_text()
        transfer = (ROOT / 'submodules/TelegramCore/Sources/AyuGram/ShadowSettingsTransfer.swift').read_text()
        self.assertIn('screenshotCustomColorARGB', document)
        self.assertIn('screenshotCustomColorARGB', transfer)
        self.assertIn('settings.messageScreenshot.customColorARGB', transfer)
        self.assertIn('legacyWhiteARGB', transfer)
        self.assertIn('legacyBlackARGB', transfer)

    def test_reaction_icons_have_files_in_screenshot_preview(self):
        source = (ROOT / 'submodules/TelegramUI/Sources/Chat/ChatControllerMessageScreenshot.swift').read_text()
        self.assertIn('self.context.engine.stickers.availableReactions()', source)
        self.assertIn('availableReactions: self.availableReactions', source)
        self.assertIn('accountPeer: self.accountPeer?._asPeer()', source)
        self.assertNotIn('availableReactions: nil, accountPeer: nil', source)

        footer = (ROOT / 'submodules/TelegramUI/Components/Chat/ChatMessageReactionsFooterContentNode/Sources/ChatMessageReactionsFooterContentNode.swift').read_text()
        self.assertIn('message.associatedMedia[mediaId] as? TelegramMediaFile', footer)
        self.assertIn('centerAnimation = file', footer)

    def test_camera_is_adjacent_to_incognito_and_reacts_to_setting(self):
        source = (ROOT / 'submodules/TelegramUI/Components/Chat/ChatMessageSelectionInputPanelNode/Sources/ChatMessageSelectionInputPanelNode.swift').read_text()
        self.assertIn('self.screenshotButton.icon = "camera"', source)
        self.assertIn('visibleButtons.insert(self.screenshotButton, at: index)', source)
        self.assertIn('$0 === self.incognitoForwardButton', source)
        self.assertIn('screenshotSettingsDisposable.dispose()', source)
        self.assertIn('map { $0.messageScreenshot.enabled }', source)


if __name__ == '__main__':
    unittest.main()

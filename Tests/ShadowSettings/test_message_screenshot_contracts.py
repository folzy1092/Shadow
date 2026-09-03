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

    def test_options_live_in_customization(self):
        source = (ROOT / 'submodules/SettingsUI/Sources/AyuGramSettingsController.swift').read_text()
        self.assertIn('case .messageScreenshot: return AyuCustomizationSection.appearance.rawValue', source)
        source = (ROOT / 'submodules/SettingsUI/Sources/ShadowMessageScreenshotSettingsController.swift').read_text()
        for key in ('enabled', 'showAvatars', 'showNames', 'showBadges', 'showTime'):
            self.assertIn('path = \\.' + key, source)
        self.assertIn('ayuGramSettings(postbox: context.account.postbox)', source)
        self.assertNotIn('UserDefaults', source)

    def test_snapshot_is_opt_in_and_encoded(self):
        source = (ROOT / 'submodules/TelegramPresentationData/Sources/ChatPresentationData.swift').read_text()
        self.assertIn('shadowScreenshot: ShadowMessageScreenshotSettings? = nil', source)
        core = (ROOT / 'submodules/TelegramCore/Sources/AyuGram/AyuGramSettings.swift').read_text()
        self.assertIn('decodeIfPresent(ShadowMessageScreenshotSettings.self', core)
        self.assertIn('encode(self.messageScreenshot', core)

    def test_camera_is_adjacent_to_incognito_and_reacts_to_setting(self):
        source = (ROOT / 'submodules/TelegramUI/Components/Chat/ChatMessageSelectionInputPanelNode/Sources/ChatMessageSelectionInputPanelNode.swift').read_text()
        self.assertIn('self.screenshotButton.icon = "camera"', source)
        self.assertIn('visibleButtons.insert(self.screenshotButton, at: index)', source)
        self.assertIn('$0 === self.incognitoForwardButton', source)
        self.assertIn('screenshotSettingsDisposable.dispose()', source)
        self.assertIn('map { $0.messageScreenshot.enabled }', source)


if __name__ == '__main__':
    unittest.main()

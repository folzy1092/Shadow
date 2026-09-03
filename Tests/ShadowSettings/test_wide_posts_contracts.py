"""Regression wiring/geometry-order checks, not a substitute for iOS rendering."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
BUBBLE = (ROOT / 'submodules/TelegramUI/Components/Chat/ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift').read_text()
HISTORY = (ROOT / 'submodules/TelegramUI/Sources/ChatHistoryListNode.swift').read_text()


class WidePostsContracts(unittest.TestCase):
    def test_only_current_broadcast_history(self):
        self.assertIn('currentPeerId == firstMessage.id.peerId', BUBBLE)
        self.assertIn('case .broadcast = channelPeer.info', BUBBLE)
        self.assertIn('!item.associatedData.isRecentActions, firstMessage.adAttribute == nil', BUBBLE)

    def test_no_global_account_setting(self):
        self.assertNotIn('ayuGramSettingsCurrent.wideChannelPosts', BUBBLE)
        self.assertIn('item.presentationData.wideChannelPosts', BUBBLE)
        self.assertIn('previousData.wideChannelPosts != shadowSettings.wideChannelPosts', HISTORY)
        self.assertIn('wideChannelPosts: shadowSettings.wideChannelPosts', HISTORY)

    def test_expansion_precedes_final_geometry(self):
        start = BUBBLE.index('if expandChannelPost, !hideBackground')
        end = BUBBLE.index('var contentSize = CGSize(width: maxContentWidth', start)
        self.assertIn('maxContentWidth = max(maxContentWidth, maximumNodeWidth)', BUBBLE[start:end])
        self.assertIn('!hasInstantVideo, mosaicRange == nil, case .none = alignment', BUBBLE[start:end])
        self.assertLess(end, BUBBLE.index('actionButtonsFinalize(maxContentWidth)', end))
        self.assertLess(end, BUBBLE.index('let layoutBubbleSize =', end))

    def test_native_limits_and_forward_button_reservation_remain(self):
        self.assertIn('maximumNodeWidth = min(maximumNodeWidth, maxNodeWidth)', BUBBLE)
        self.assertIn('tmpWidth -= 45.0', BUBBLE)
        self.assertNotIn('let wideWidth =', BUBBLE)


if __name__ == '__main__':
    unittest.main()

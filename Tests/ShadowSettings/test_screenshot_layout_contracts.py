"""Integration/source guards, not a substitute for screenshot tests on iOS."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
PREVIEW = ROOT / 'submodules/TelegramUI/Sources/Chat/ChatControllerMessageScreenshot.swift'


class ScreenshotLayoutContracts(unittest.TestCase):
    def test_round_avatar_uses_matching_size_and_placeholder_capable_api(self):
        source = PREVIEW.read_text().split('private func appendAvatar(', 1)[1].split('\n    }', 1)[0]
        self.assertIn('avatar.updateSize(size: size)', source)
        self.assertIn('avatar.clipsToBounds = true', source)
        self.assertIn('avatar.cornerRadius = size.width * 0.5', source)
        self.assertIn('avatar.setPeer(context:', source)
        self.assertIn('clipStyle: .round, synchronousLoad: true, displayDimensions: size', source)
        self.assertIn('avatar.setCustomLetters(["?"])', source)
        self.assertIn('self.width - 8.0 - size.width', source)
        self.assertIn('incoming', source)
        self.assertLess(source.index('avatar.setPeer(context:'), source.index('self.content.addSubnode(avatar)'))
        self.assertIn('avatar.recursivelyEnsureDisplaySynchronously(true)', source)

    def test_captured_account_resolves_missing_own_author(self):
        source = PREVIEW.read_text()
        self.assertIn('transaction.getPeer(self.context.account.peerId)', source)
        self.assertIn('private let accountPeer: EnginePeer?', source)
        self.assertIn('if !message.flags.contains(.Incoming)', source)
        self.assertIn('return self.accountPeer', source)
        self.assertIn('original.withUpdatedAuthor($0._asPeer())', source)
        self.assertNotIn('withUpdatedFlags', source)

    def test_grouping_keeps_per_message_time_and_avatar_on_group_end(self):
        source = PREVIEW.read_text()
        self.assertIn('rowOptions.showNames = self.options.showNames && startsGroup', source)
        self.assertIn('let endsGroup = self.endsGroup(at: index)', source)
        self.assertIn('self.options.showAvatars && endsGroup', source)
        self.assertIn('self.present(menu, animated: true)', source)
        self.assertIn('previous.threadId', source)
        self.assertIn('startsGroup ? 10.0 : 2.0', source)
        self.assertIn('if !self.options.showTime { self.hideTime(in: node) }', source)
        self.assertNotIn('rowOptions.showTime =', source)

    def test_native_bubbles_preserve_real_direction_and_export_stays_portal_free(self):
        source = PREVIEW.read_text()
        self.assertIn('columnLeft - contentFrame.minX', source)
        self.assertIn('columnRight - contentFrame.maxX', source)
        self.assertIn('message.effectivelyIncoming(', source)
        self.assertIn('desktopBubbleTheme', source)
        self.assertIn('withUpdated(incoming: colors, outgoing: colors)', source)
        bubble = (ROOT / 'submodules/TelegramUI/Components/Chat/ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift').read_text()
        self.assertIn('item.presentationData.shadowScreenshot == nil ? presentationContext.backgroundNode : nil', bubble)
        self.assertIn('backgroundNode: bubbleBackgroundNode', bubble)
        mask = bubble.split('private var backgroundMaskMode: Bool {', 1)[1].split('\n    }', 1)[0]
        self.assertIn('self.item?.presentationData.shadowScreenshot != nil', mask)
        self.assertIn('return false', mask)

    def test_grouping_executable_is_in_foundation_runner(self):
        runner = (ROOT / 'build-system/ci/test_shadow_foundation.py').read_text()
        self.assertIn('ShadowMessageScreenshotGrouping.swift', runner)
        self.assertIn('ScreenshotGroupingTests.swift', runner)

    def test_export_tail_and_media_corners_follow_real_direction(self):
        bubble = (ROOT / 'submodules/TelegramUI/Components/Chat/ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift').read_text()
        self.assertEqual(bubble.count('let bubbleIncoming = incoming'), 2)
        self.assertNotIn('incoming || item.presentationData.shadowScreenshot != nil', bubble)
        self.assertIn('mergedTop.merged ? (bubbleIncoming ? .Left : .Right)', bubble)
        self.assertIn('mergedBottom.merged ? (bubbleIncoming ? .Left : .Right)', bubble)
        self.assertIn('.None(bubbleIncoming ? .Incoming : .Outgoing)', bubble)
        self.assertIn('} else if !bubbleIncoming {\n            backgroundType = .outgoing(mergeType)', bubble)
        self.assertIn('backgroundFrame.origin.x + (bubbleIncoming ? layoutConstants.bubble.contentInsets.left', bubble)


if __name__ == '__main__':
    unittest.main()

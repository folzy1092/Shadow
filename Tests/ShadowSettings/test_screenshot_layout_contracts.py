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
        self.assertLess(source.index('avatar.setPeer(context:'), source.index('self.content.addSubnode(avatar)'))
        self.assertIn('avatar.recursivelyEnsureDisplaySynchronously(true)', source)

    def test_captured_account_resolves_missing_own_author(self):
        source = PREVIEW.read_text()
        self.assertIn('transaction.getPeer(self.context.account.peerId)', source)
        self.assertIn('private let accountPeer: EnginePeer?', source)
        self.assertIn('if !message.flags.contains(.Incoming)', source)
        self.assertIn('return self.accountPeer', source)
        self.assertIn('message.withUpdatedAuthor($0._asPeer())', source)
        self.assertNotIn('withUpdatedFlags', source)

    def test_grouping_keeps_per_message_time(self):
        source = PREVIEW.read_text()
        self.assertIn('rowOptions.showNames = self.options.showNames && startsGroup', source)
        self.assertIn('self.options.showAvatars && startsGroup', source)
        self.assertIn('previous.threadId', source)
        self.assertIn('startsGroup ? 10.0 : 2.0', source)
        self.assertIn('if !self.options.showTime { self.hideTime(in: node) }', source)
        self.assertNotIn('rowOptions.showTime =', source)

    def test_native_bubbles_are_left_aligned_and_portal_free_only_in_export(self):
        source = PREVIEW.read_text()
        self.assertIn('avatarWidth + 8.0 - contentFrame.minX', source)
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


if __name__ == '__main__':
    unittest.main()

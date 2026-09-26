"""Source guard for channel-post views while Ghost Mode is active."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
TRACKER = ROOT / 'submodules/TelegramCore/Sources/State/AccountViewTracker.swift'


class GhostPostViewsContracts(unittest.TestCase):
    def test_view_counts_are_fetched_without_increment_in_ghost_mode(self):
        source = TRACKER.read_text()
        self.assertIn(
            'currentAyuGramSettings(transaction: transaction).ghostMode ? .boolFalse : .boolTrue',
            source,
        )
        self.assertIn(
            'Api.functions.messages.getMessagesViews(peer: inputPeer, id: messageIds.map { $0.id }, increment: increment)',
            source,
        )
        self.assertNotIn('getMessagesViews(peer: inputPeer, id: messageIds.map { $0.id }, increment: .boolTrue)', source)


if __name__ == '__main__':
    unittest.main()

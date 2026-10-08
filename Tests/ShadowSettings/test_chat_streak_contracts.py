"""Source contracts for «Общаемся N дней подряд» (1.8.0)."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SUB = ROOT / "submodules"


def read(path):
    return (SUB / path).read_text(encoding="utf-8")


class ChatStreakContracts(unittest.TestCase):
    def test_setting(self):
        settings = read("TelegramCore/Sources/AyuGram/AyuGramSettings.swift")
        self.assertIn("public var showChatStreak: Bool = true", settings)
        self.assertIn('forKey: "showChatStreak")) ?? 1) != 0', settings)
        self.assertIn("settings.showChatStreak = false", settings)
        self.assertIn('"showChatStreak"', read("TelegramCore/Sources/AyuGram/ShadowSettingsDocument.swift"))
        self.assertIn('"showChatStreak": \\.showChatStreak', read("TelegramCore/Sources/AyuGram/ShadowSettingsTransfer.swift"))
        self.assertIn('slug: "chat-streak", entryId: 121, key: "showChatStreak"', read("TelegramCore/Sources/AyuGram/ShadowSettingLinks.swift"))
        screen = read("SettingsUI/Sources/AyuGramSettingsController.swift")
        self.assertIn("case .showChatStreak: return 121", screen)
        self.assertIn("case .showChatStreak: return (22, 1)", screen)
        self.assertIn('title: "Дни подряд в профиле"', screen)
        self.assertIn("destination: .customization, entryId: 121,", read("SettingsUI/Sources/ShadowSettingsSearchIndex.swift"))
        self.assertIn("`shadow://customization/chat-streak`", (ROOT / "docs/shadow-links.md").read_text(encoding="utf-8"))

    def test_profile(self):
        items = read("TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoProfileItems.swift")
        self.assertIn("if let streak = shadowChatStreakText(context: context, user: user) {", items)
        self.assertIn("user.botInfo == nil", items)
        self.assertIn("ShadowChatLockStore.shared.requiresUnlock(accountPeerId: accountPeerId, peerId: peerId)", items)
        data = read("TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoData.swift")
        self.assertIn("forName: ShadowChatStreakStore.didChangeNotification", data)

    def test_counting(self):
        collect = read("TelegramCore/Sources/AyuGram/ShadowChatStatsCollect.swift")
        # Calls and service messages do not count, reactions never do.
        self.assertIn("item.kind != .call else {", collect)
        self.assertIn("static let streakMaxRounds = 40", collect)
        script = (ROOT / "build-system/ci/test_shadow_foundation.py").read_text(encoding="utf-8")
        self.assertIn("Tests/ShadowSettings/ChatStreakTests.swift", script)


if __name__ == "__main__":
    unittest.main()

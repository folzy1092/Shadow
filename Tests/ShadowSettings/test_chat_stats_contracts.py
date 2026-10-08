"""Source contracts for «Итоги чатов» (1.7.0)."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
SUB = ROOT / "submodules"


def read(path):
    return (SUB / path).read_text(encoding="utf-8")


class ChatStatsContracts(unittest.TestCase):
    def test_page_reads_only_existing_fields(self):
        stats = read("TelegramCore/Sources/AyuGram/ShadowChatStats.swift")
        page = read("TelegramCore/Sources/AyuGram/ShadowChatStatsPage.swift")
        report = stats[stats.index("public struct Report"):stats.index("public var me: Person?")]
        person = stats[stats.index("public struct Person"):stats.index("public init(id: Int64, name: String)")]
        report_fields = set(re.findall(r"public var (\w+):", report))
        person_fields = set(re.findall(r"public var (\w+)", person))
        script = page[page.index("<script>"):page.index("</script>")]
        for field in set(re.findall(r"\bR\.(\w+)", script)):
            self.assertIn(field, report_fields, f"R.{field}")
        for name in ("p", "me", "other", "w", "s"):
            for field in set(re.findall(rf"\b{name}\.(\w+)", script)) - {"id", "name", "push", "sort", "map", "filter", "slice", "length", "key", "count", "label", "values", "color", "day", "join"}:
                self.assertIn(field, person_fields, f"{name}.{field}")

    def test_wiring(self):
        hub = read("SettingsUI/Sources/AyuGramSettingsController.swift")
        self.assertIn('row("Итоги чатов", "chart.bar.fill"', hub)
        self.assertIn("case .chatStats: return shadowChatStatsListController(context: context)", hub)
        search = read("SettingsUI/Sources/ShadowSettingsSearchIndex.swift")
        self.assertIn('case .chatStats: return "Итоги чатов"', search)
        profile = read("TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreenPerformButtonAction.swift")
        self.assertIn('text: "Итоги чата"', profile)
        self.assertIn("shadowPresentChatStatsPeriod(context: self.context, peerId: shadowExportPeerId", profile)
        self.assertIn("if case let .channel(channel) = chatPeer, case .broadcast = channel.info {", profile)

    def test_history_loading_is_paced_and_bounded(self):
        collect = read("TelegramCore/Sources/AyuGram/ShadowChatStatsCollect.swift")
        self.assertIn("static let requestPause: Double = 0.35", collect)
        self.assertIn("count: 100)", collect)
        self.assertIn("if oldest < since {", collect)
        self.assertIn("if message.timestamp < since {\n                        return false", collect)
        # The scan really stops when the closure returns false.
        postbox = read("Postbox/Sources/Postbox.swift")
        self.assertIn("break scan", postbox)

    def test_screen_actions(self):
        ui = read("SettingsUI/Sources/ShadowChatStatsUI.swift")
        for action in ('case "shareImage":', 'case "shareFile":', 'case "recalculate":', 'case "openChat":'):
            self.assertIn(action, ui)
        self.assertIn("ShadowChatStats.anonymized(report)", ui)
        self.assertIn('title: "Анонимно"', ui)
        self.assertIn("configuration.snapshotWidth = NSNumber(value: 1080.0)", ui)
        page = read("TelegramCore/Sources/AyuGram/ShadowChatStatsPage.swift")
        for action in ("shareImage", "shareFile", "recalculate", "openChat"):
            self.assertIn(action, page)
        self.assertIn("window.webkit.messageHandlers.shadow.postMessage", page)

    def test_foundation_suite(self):
        script = (ROOT / "build-system/ci/test_shadow_foundation.py").read_text(encoding="utf-8")
        self.assertIn("Tests/ShadowSettings/ChatStatsTests.swift", script)


if __name__ == "__main__":
    unittest.main()

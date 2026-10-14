"""Source contracts: the pinned message stays visible next to a business bot (1.12.0)."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SUB = ROOT / "submodules"


def read(path):
    return (SUB / path).read_text(encoding="utf-8")


class BusinessBotPinnedContracts(unittest.TestCase):
    def test_settings_fields(self):
        settings = read("TelegramCore/Sources/AyuGram/AyuGramSettings.swift")
        self.assertIn("public var businessBotPinned: Bool = true", settings)
        self.assertIn('forKey: "businessBotPinned")) ?? 1) != 0', settings)
        self.assertIn('ShadowBusinessBotPanel.Layout.normalized((try container.decodeIfPresent(Int32.self, forKey: "businessBotPinnedLayout")) ?? 0).rawValue', settings)
        for key in ("businessBotPinned", "businessBotPinnedLayout", "businessBotPinnedFirst", "businessBotPinnedCompact"):
            self.assertIn(f'forKey: "{key}")', settings)
        # Disguise shows stock Telegram: the bot instead of the pin.
        self.assertIn("settings.businessBotPinned = false", settings)

    def test_export_links_and_search(self):
        document = read("TelegramCore/Sources/AyuGram/ShadowSettingsDocument.swift")
        self.assertIn('key == "businessBotPinnedLayout" && (0...3).contains(number)', document)
        transfer = read("TelegramCore/Sources/AyuGram/ShadowSettingsTransfer.swift")
        for key in ("businessBotPinned", "businessBotPinnedFirst", "businessBotPinnedCompact"):
            self.assertIn(f'"{key}": \\.{key}', transfer)
            self.assertIn(f'"{key}"', document)
        self.assertIn('values["businessBotPinnedLayout"]', transfer)
        self.assertIn('"businessBotPinnedLayout": \\.businessBotPinnedLayout', read("TelegramCore/Sources/AyuGram/ShadowSettingLinksApply.swift"))
        links = read("TelegramCore/Sources/AyuGram/ShadowSettingLinks.swift")
        for slug, entry, key in (("business-bot-pinned", 125, "businessBotPinned"), ("business-bot-layout", 126, "businessBotPinnedLayout"),
                                 ("business-bot-pinned-first", 127, "businessBotPinnedFirst"), ("business-bot-compact", 128, "businessBotPinnedCompact")):
            self.assertIn(f'slug: "{slug}", entryId: {entry}, key: "{key}"', links)
            self.assertIn(f"`shadow://customization/{slug}`", (ROOT / "docs/shadow-links.md").read_text(encoding="utf-8"))
        search = read("SettingsUI/Sources/ShadowSettingsSearchIndex.swift")
        for entry in (125, 126, 127, 128):
            self.assertIn(f"destination: .customization, entryId: {entry},", search)

    def test_screen(self):
        screen = read("SettingsUI/Sources/AyuGramSettingsController.swift")
        for case, entry in (("businessBotPinned", 125), ("businessBotPinnedLayout", 126), ("businessBotPinnedFirst", 127), ("businessBotPinnedCompact", 128)):
            self.assertIn(f"case .{case}: return {entry}", screen)
        self.assertIn("case .chats: return [.chats, .businessBot, .bottomBar, .calls]", screen)
        self.assertIn("if settings.businessBotPinned {", screen)

    def test_title_panel_keeps_both(self):
        panels = read("TelegramUI/Sources/ChatInterfaceTitlePanelNodes.swift")
        self.assertIn("ShadowBusinessBotPanel.arrangement(enabled: shadowSettings.businessBotPinned", panels)
        self.assertIn("hasPinned: selectedContext == .pinnedMessage", panels)
        self.assertIn("currentAyuGramSettings(accountId: context.account.id)", panels)
        node = read("TelegramUI/Sources/ShadowBusinessBotPinnedTitlePanelNode.swift")
        # The stock panels are reused, so every action of both stays.
        self.assertIn("ChatManagingBotTitlePanelNode(context: context)", node)
        self.assertIn("ChatPinnedMessageTitlePanelNode(context: context,", node)
        self.assertIn("self.pinnedPanel.interfaceInteraction = self.interfaceInteraction", node)
        self.assertIn("self.botPanel.interfaceInteraction = self.interfaceInteraction", node)
        bot = read("TelegramUI/Sources/ChatManagingBotTitlePanelNode.swift")
        # The icon style keeps Стоп/Старт in its menu.
        self.assertIn("self.openSettingsMenu(sourceView: sourceView, includePauseToggle: true)", bot)
        self.assertIn("if includePauseToggle && (managingBot.canReply || managingBot.isPaused)", bot)

    def test_foundation_suite_runs_the_model(self):
        runner = (ROOT / "build-system/ci/test_shadow_foundation.py").read_text(encoding="utf-8")
        self.assertIn("'Tests/ShadowSettings/BusinessBotPanelTests.swift'", runner)


if __name__ == "__main__":
    unittest.main()

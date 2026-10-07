"""Source contracts: per-chat voice speed and «Ответить с тайм-кодом» (1.5.0)."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SUB = ROOT / "submodules"


def read(path):
    return (SUB / path).read_text(encoding="utf-8")


class ChatVoiceSpeedContracts(unittest.TestCase):
    def test_setting_is_stored_exported_and_linked(self):
        settings = read("TelegramCore/Sources/AyuGram/AyuGramSettings.swift")
        self.assertIn("public var chatVoiceSpeed: Bool = false", settings)
        self.assertIn('forKey: "chatVoiceSpeed"', settings)
        self.assertIn('"chatVoiceSpeed"', read("TelegramCore/Sources/AyuGram/ShadowSettingsDocument.swift"))
        self.assertIn('"chatVoiceSpeed": \\.chatVoiceSpeed', read("TelegramCore/Sources/AyuGram/ShadowSettingsTransfer.swift"))
        links = read("TelegramCore/Sources/AyuGram/ShadowSettingLinks.swift")
        self.assertIn('slug: "chat-voice-speed", entryId: 119, key: "chatVoiceSpeed"', links)
        self.assertIn('slug: "chat-voice-speeds", entryId: 120, key: nil', links)
        docs = (ROOT / "docs" / "shadow-links.md").read_text(encoding="utf-8")
        self.assertIn("shadow://customization/chat-voice-speed`", docs)
        self.assertIn("shadow://customization/chat-voice-speeds`", docs)

    def test_screen_rows_and_list(self):
        screen = read("SettingsUI/Sources/AyuGramSettingsController.swift")
        self.assertIn("case .chatVoiceSpeed: return 119", screen)
        self.assertIn("case .chatVoiceSpeedList: return 120", screen)
        self.assertIn("shadowChatVoiceSpeedCount(context: context)", screen)
        self.assertIn("controller?.push(shadowChatVoiceSpeedController(context: context))", screen)
        search = read("SettingsUI/Sources/ShadowSettingsSearchIndex.swift")
        self.assertIn("entryId: 119", search)
        self.assertIn("entryId: 120", search)
        controller = read("SettingsUI/Sources/ShadowChatVoiceSpeedController.swift")
        self.assertIn("ShadowChatVoiceSpeed.shared.remove(chat:", controller)
        self.assertIn("ShadowChatVoiceSpeed.shared.removeAll(accountPeerId: accountPeerId)", controller)
        self.assertIn("ShadowChatVoiceSpeed.didChangeNotification", controller)

    def test_player_starts_at_the_chat_speed(self):
        manager = read("TelegramUI/Sources/MediaManager.swift")
        self.assertIn("initialPlaybackRate: initialVoicePlaybackRate", manager)
        self.assertIn("currentAyuGramSettings(accountId: context.account.id).chatVoiceSpeed", manager)
        self.assertIn("ShadowChatVoiceSpeed.shared.currentChat = speedChat", manager)

    def test_bar_button_keeps_the_common_speed(self):
        panel = read("TelegramUI/Components/MediaPlaybackHeaderPanelComponent/Sources/MediaPlaybackHeaderPanelComponent.swift")
        self.assertIn("ShadowChatVoiceSpeed.shared.set(chat: shadowSpeedChat, rate: rate.rawValue)", panel)
        # The common speed is not written while the chat speed is set.
        self.assertLess(panel.index("if shadowSpeedChat != nil {\n                            return rate"), panel.index("settings.withUpdatedVoicePlaybackRate(rate)"))

    def test_foundation_suite_runs_the_store(self):
        runner = (ROOT / "build-system" / "ci" / "test_shadow_foundation.py").read_text(encoding="utf-8")
        self.assertIn("Tests/ShadowSettings/ChatVoiceSpeedTests.swift", runner)


class TimecodeReplyMenuContracts(unittest.TestCase):
    def test_menu_item(self):
        menus = read("TelegramUI/Sources/ChatInterfaceStateContextMenus.swift")
        self.assertIn("shadowReplyTimecodePosition(context: context, message: messages[0]) != nil", menus)
        self.assertIn("actions.append(.custom(ShadowTimecodeReplyContextItem(", menus)
        self.assertIn("interfaceInteraction.setupReplyMessage(timecodeMessage.id, nil,", menus)
        self.assertIn("ShadowReplyTimecode.applying(timecode, to: \"\")", menus)
        item = read("TelegramUI/Sources/Chat/ShadowTimecodeReplyContextItem.swift")
        self.assertIn('"Ответить с тайм-кодом"', item)
        self.assertIn("SwiftSignalKit.Timer(timeout: 0.5, repeat: true", item)
        send = read("TelegramUI/Sources/Chat/ShadowReplyTimecodeSend.swift")
        self.assertIn("func shadowReplyTimecodePosition(context: AccountContext, message: Message)", send)


if __name__ == "__main__":
    unittest.main()

"""Source contracts: the timecode in replies to voice messages (Кастомизация → Медиа)."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SUB = ROOT / "submodules"


def read(path):
    return (SUB / path).read_text(encoding="utf-8")


class ReplyTimecodeContracts(unittest.TestCase):
    def test_settings_are_stored_exported_and_linked(self):
        settings = read("TelegramCore/Sources/AyuGram/AyuGramSettings.swift")
        for key in ("replyTimecode", "replyTimecodeMode"):
            self.assertIn(f'forKey: "{key}"', settings)
        self.assertIn("public var replyTimecode: Bool = false", settings)
        document = read("TelegramCore/Sources/AyuGram/ShadowSettingsDocument.swift")
        self.assertIn('"replyTimecode"', document)
        self.assertIn('key == "replyTimecodeMode" && (0...1).contains(number)', document)
        transfer = read("TelegramCore/Sources/AyuGram/ShadowSettingsTransfer.swift")
        self.assertIn('values["replyTimecodeMode"]', transfer)
        self.assertIn('"replyTimecode": \.replyTimecode', transfer)
        self.assertIn('"replyTimecodeMode": \.replyTimecodeMode', read("TelegramCore/Sources/AyuGram/ShadowSettingLinksApply.swift"))
        links = read("TelegramCore/Sources/AyuGram/ShadowSettingLinks.swift")
        self.assertIn('slug: "reply-timecode", entryId: 117, key: "replyTimecode"', links)
        self.assertIn('slug: "reply-timecode-mode", entryId: 118, key: "replyTimecodeMode"', links)
        self.assertIn("shadow://customization/reply-timecode", (ROOT / "docs" / "shadow-links.md").read_text(encoding="utf-8"))

    def test_screen_rows(self):
        screen = read("SettingsUI/Sources/AyuGramSettingsController.swift")
        self.assertIn("case .replyTimecode: return 117", screen)
        self.assertIn("case .replyTimecodeMode: return 118", screen)
        self.assertIn("if settings.replyTimecode {\n        entries.append(.replyTimecodeMode(settings.replyTimecodeMode))", screen)
        search = read("SettingsUI/Sources/ShadowSettingsSearchIndex.swift")
        self.assertIn("entryId: 117", search)
        self.assertIn("entryId: 118", search)

    def test_player_positions_are_tracked(self):
        manager = read("TelegramUI/Sources/MediaManager.swift")
        self.assertIn("ShadowReplyTimecode.positions.record(key: key, sample: sample)", manager)
        self.assertIn("ShadowReplyTimecode.positions.freeze(key: previousKey, now: now)", manager)
        self.assertIn("self.shadowReplyTimecodeDisposable.dispose()", manager)

    def test_send_adds_the_timecode(self):
        node = read("TelegramUI/Sources/ChatControllerNode.swift")
        self.assertIn("shadowReplyTimecode: ShadowReplyTimecode.Resolved? = nil", node)
        self.assertIn("shadowReplyTimecodeCandidate(context: self.context, state: effectivePresentationInterfaceState, chatLocation: self.chatLocation)", node)
        self.assertIn("shadowReplyTimecode: resolved, completion: completion", node)
        self.assertIn("prefixed.append(inputText)", node)
        # The timecode goes before the lastSendTimestamp guard, so the alert's resend is not swallowed.
        self.assertLess(node.index("shadowReplyTimecodeAlertController(context:"), node.index("if self.lastSendTimestamp + 0.15 > timestamp"))
        send = read("TelegramUI/Sources/Chat/ShadowReplyTimecodeSend.swift")
        self.assertIn("media.isVoice || media.isInstantVideo", send)
        self.assertIn("Запомнить для этого чата на 30 мин", send)
        self.assertIn("ShadowReplyTimecode.memory.remember(chat: candidate.chatKey", send)
        self.assertIn('"//submodules/TelegramUI/Components/AlertComponent/AlertCheckComponent"', (SUB / "TelegramUI" / "BUILD").read_text(encoding="utf-8"))

    def test_foundation_suite_runs_the_model(self):
        runner = (ROOT / "build-system" / "ci" / "test_shadow_foundation.py").read_text(encoding="utf-8")
        self.assertIn("Tests/ShadowSettings/ReplyTimecodeTests.swift", runner)


if __name__ == "__main__":
    unittest.main()

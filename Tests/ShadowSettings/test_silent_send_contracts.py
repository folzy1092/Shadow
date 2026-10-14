"""Source contracts: «Тихая отправка» by default, always or on a schedule (1.13.0)."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SUB = ROOT / "submodules"


def read(path):
    return (SUB / path).read_text(encoding="utf-8")


class SilentSendContracts(unittest.TestCase):
    def test_settings(self):
        settings = read("TelegramCore/Sources/AyuGram/AyuGramSettings.swift")
        self.assertIn("public var silentSend: Bool = false", settings)
        for key in ("silentSend", "silentSendMode", "silentSendFrom", "silentSendTo"):
            self.assertIn(f'forKey: "{key}")', settings)
        self.assertIn("settings.silentSend = false", settings)
        document = read("TelegramCore/Sources/AyuGram/ShadowSettingsDocument.swift")
        self.assertIn('key == "silentSendMode" && (0...1).contains(number)', document)
        self.assertIn('(key == "silentSendFrom" || key == "silentSendTo") && (0...1439).contains(number)', document)
        transfer = read("TelegramCore/Sources/AyuGram/ShadowSettingsTransfer.swift")
        self.assertIn('"silentSend": \\.silentSend', transfer)
        for key in ("silentSendMode", "silentSendFrom", "silentSendTo"):
            self.assertIn(f'values["{key}"]', transfer)
        self.assertIn('"silentSendMode": \\.silentSendMode', read("TelegramCore/Sources/AyuGram/ShadowSettingLinksApply.swift"))

    def test_send_path_mutes(self):
        enqueue = read("TelegramCore/Sources/PendingMessages/EnqueueMessage.swift")
        self.assertIn("AyuDelayedSend.transform(messages: shadowSilentSendTransform(messages: messages,", enqueue)
        self.assertIn("attributes.append(NotificationInfoMessageAttribute(flags: .muted))", enqueue)
        self.assertIn("guard peerId != accountPeerId, ShadowSilentSend.isActive(", enqueue)

    def test_screen_and_links(self):
        screen = read("SettingsUI/Sources/AyuGramSettingsController.swift")
        for case, entry in (("silentSend", 14), ("silentSendMode", 15), ("silentSendFrom", 16), ("silentSendTo", 17)):
            self.assertIn(f"case .{case}: return {entry}", screen)
        self.assertIn("if settings.silentSendMode == ShadowSilentSend.modeSchedule {", screen)
        self.assertIn("ShadowTimePickerController(title:", screen)
        links = read("TelegramCore/Sources/AyuGram/ShadowSettingLinks.swift")
        self.assertIn('slug: "silent-send", entryId: 14, key: "silentSend"', links)
        self.assertIn('slug: "silent-send-mode", entryId: 15, key: "silentSendMode"', links)
        docs = (ROOT / "docs/shadow-links.md").read_text(encoding="utf-8")
        self.assertIn("`shadow://ghost/silent-send`", docs)
        runner = (ROOT / "build-system/ci/test_shadow_foundation.py").read_text(encoding="utf-8")
        self.assertIn("'Tests/ShadowSettings/SilentSendTests.swift'", runner)


if __name__ == "__main__":
    unittest.main()

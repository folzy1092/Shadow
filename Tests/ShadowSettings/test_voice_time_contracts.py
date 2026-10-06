"""Source contracts: the voice message time format (Кастомизация → Время на голосовых)."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SUB = ROOT / "submodules"


def read(path):
    return (SUB / path).read_text(encoding="utf-8")


SETTINGS = read("TelegramCore/Sources/AyuGram/AyuGramSettings.swift")


class VoiceTimeContracts(unittest.TestCase):
    def test_settings_are_stored_exported_and_synced(self):
        for key, default in (("voiceTimeFormat", None), ("voiceTimeRoundVideos", "1"), ("voiceTimeInPlayer", "0")):
            self.assertIn(f'forKey: "{key}"', SETTINGS)
        self.assertIn("ShadowVoiceTime.normalized((try container.decodeIfPresent(Int32.self, forKey: \"voiceTimeFormat\")) ?? 0)", SETTINGS)
        document = read("TelegramCore/Sources/AyuGram/ShadowSettingsDocument.swift")
        self.assertIn('"voiceTimeRoundVideos", "voiceTimeInPlayer"', document)
        self.assertIn('key == "voiceTimeFormat" && (0...5).contains(number)', document)
        transfer = read("TelegramCore/Sources/AyuGram/ShadowSettingsTransfer.swift")
        self.assertIn('values["voiceTimeFormat"]', transfer)
        self.assertIn('"voiceTimeInPlayer": \\.voiceTimeInPlayer', transfer)
        # Sync copies the whole AyuGramSettings except runtime state.
        sync = read("TelegramCore/Sources/AyuGram/ShadowSettingsSync.swift")
        self.assertNotIn("voiceTime", sync)

    def test_every_new_setting_has_a_link_and_search(self):
        links = read("TelegramCore/Sources/AyuGram/ShadowSettingLinks.swift")
        for slug, entry, key in (("voice-time", 112, "voiceTimeFormat"), ("voice-time-round", 113, "voiceTimeRoundVideos"), ("voice-time-player", 114, "voiceTimeInPlayer")):
            self.assertIn(f'slug: "{slug}", entryId: {entry}, key: "{key}"', links)
        search = read("SettingsUI/Sources/ShadowSettingsSearchIndex.swift")
        for entry in (112, 113, 114):
            self.assertIn(f"destination: .customization, entryId: {entry},", search)
        apply = read("TelegramCore/Sources/AyuGram/ShadowSettingLinksApply.swift")
        self.assertIn('"voiceTimeFormat": \\.voiceTimeFormat', apply)

    def test_bubble_round_video_and_player_use_the_format(self):
        file_node = read("TelegramUI/Components/Chat/ChatMessageInteractiveFileNode/Sources/ChatMessageInteractiveFileNode.swift")
        self.assertIn("ShadowVoiceTime.text(format: shadowFormat, duration: effectiveDuration", file_node)
        self.assertIn("ShadowVoiceTime.isWide(shadowFormat)", file_node)
        self.assertIn("if file.isInstantVideo && !settings.voiceTimeRoundVideos", file_node)
        round_node = read("TelegramUI/Components/Chat/ChatMessageInteractiveInstantVideoNode/Sources/ChatMessageInteractiveInstantVideoNode.swift")
        self.assertIn("shadowVoiceSettings.voiceTimeRoundVideos && shadowVoiceFormat != ShadowVoiceTime.defaultFormat", round_node)
        duration = read("TelegramUI/Components/Chat/ChatInstantVideoMessageDurationNode/Sources/ChatInstantVideoMessageDurationNode.swift")
        self.assertIn("public var shadowFormatter: ((Double, Double?) -> String?)?", duration)
        for path in ("TelegramBaseController/Sources/MediaNavigationAccessoryHeaderNode.swift",
                     "TelegramUI/Components/MediaPlaybackHeaderPanelComponent/Sources/MediaNavigationAccessoryHeaderNode.swift"):
            header = read(path)
            self.assertIn("settings.voiceTimeInPlayer", header, path)
            self.assertIn("shadowTimeText: self.shadowTimeText", header, path)
            self.assertIn("self.shadowStatusDisposable.dispose()", header, path)

    def test_customization_rows(self):
        hub = read("SettingsUI/Sources/AyuGramSettingsController.swift")
        for case in ("case voiceTimeFormat(Int32)", "case voiceTimeRoundVideos(Bool)", "case voiceTimeInPlayer(Bool)"):
            self.assertIn(case, hub)
        self.assertIn("arguments.selectVoiceTimeFormat = {", hub)


if __name__ == "__main__":
    unittest.main()

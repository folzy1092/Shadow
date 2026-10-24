"""Source contracts for spy exclusions (1.14.1): «Исключить ботов» and chats by id."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SUB = ROOT / "submodules"
CORE = "TelegramCore/Sources/AyuGram/"


def read(path):
    return (SUB / path).read_text(encoding="utf-8")


class SpyExclusionsContracts(unittest.TestCase):
    def test_settings_fields_and_defaults(self):
        settings = read(CORE + "AyuGramSettings.swift")
        self.assertIn("public var spyExcludeBots: Bool = true", settings)
        self.assertIn("public var spyExcludedPeerIds: [Int64] = []", settings)
        self.assertIn('forKey: "spyExcludeBots")) ?? 1) != 0', settings)
        self.assertIn('decodeIfPresent([Int64].self, forKey: "spyExcludedPeerIds")) ?? []', settings)
        self.assertIn('forKey: "spyExcludeBots")\n', settings)
        self.assertIn('try container.encode(self.spyExcludedPeerIds, forKey: "spyExcludedPeerIds")', settings)
        check = settings[settings.index("public func isSpyExcluded(message: Message)"):]
        check = check[:check.index("\n    }\n")]
        self.assertIn("self.isSpyExcluded(peerId: message.id.peerId)", check)
        self.assertIn("self.spyExcludeBots, let author = message.author as? TelegramUser, author.botInfo != nil", check)

    def test_every_spy_hook_honours_exclusions(self):
        # Edit history: bot and excluded-chat edits never reach the archive.
        edits = read(CORE + "AyuEditHistory.swift")
        self.assertIn("guard settings.saveEditHistory, !settings.isSpyExcluded(message: previousMessage) else", edits)
        # Kept deletions.
        anti_delete = read(CORE + "AyuGramAntiDelete.swift")
        self.assertIn("if settings.isSpyExcluded(message: message) {", anti_delete)
        # Auto-saved incoming media.
        media = read(CORE + "AyuSavedMedia.swift")
        hook = media[media.index("let settings = currentAyuGramSettings(mediaBox: mediaBox)"):]
        self.assertLess(hook.index("guard !settings.isSpyExcluded(peerId: messageId.peerId) else"), hook.index("settings.saveAllIncomingMedia"))

    def test_bot_api_id_parser(self):
        parser = read(CORE + "ShadowBotApiPeerId.swift")
        self.assertIn("private static let channelOffset: Int64 = 1_000_000_000_000", parser)
        # PeerId.Id asserts on raw ids wider than 56 bits: such input must be rejected, not crash.
        self.assertIn("private static let maxRawId: Int64 = 0x00ffffffffffffff", parser)
        self.assertIn("guard raw > 0, raw <= maxRawId else", parser)
        self.assertIn("value != 0, value != Int64.min", parser)
        self.assertIn("if value <= -channelOffset {", parser)
        self.assertIn("raw: -value - channelOffset", parser)
        # One shared conversion: the profile id row and the chat badges use it too.
        self.assertIn("ShadowBotApiPeerId.botApiId(peerId)", read("TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoProfileItems.swift"))
        git_config = read(CORE + "GitConfig.swift")
        self.assertIn("ShadowBotApiPeerId.botApiId(peerId)", git_config)
        self.assertNotIn("func gitConfigBotApiId", git_config)

    def test_portable_settings(self):
        document = read(CORE + "ShadowSettingsDocument.swift")
        transfer = read(CORE + "ShadowSettingsTransfer.swift")
        self.assertIn('"spyExcludeBots"', document)
        self.assertIn('"spyExcludedPeerIds"', document)
        self.assertIn('"spyExcludeBots": \\.spyExcludeBots', transfer)
        self.assertIn('("spyExcludedPeerIds", ShadowSettingsTransfer.json(settings.spyExcludedPeerIds))', transfer)
        self.assertIn("updated.spyExcludedPeerIds = ShadowSettingsTransfer.uniqueIds(ids)", transfer)
        backup = read("SettingsUI/Sources/ShadowSettingsBackupController.swift")
        self.assertIn('key.hasPrefix("spy")', backup)

    def test_spy_screen_rows(self):
        screen = read("SettingsUI/Sources/AyuGramSettingsController.swift")
        for case, entry in (("exclusionsHeader", 32), ("spyExcludeBots", 33), ("spyExcludedChats", 34), ("exclusionsFooter", 35)):
            self.assertIn(f"case .{case}: return {entry}", screen)
        self.assertIn('text: "ИСКЛЮЧЕНИЯ"', screen)
        self.assertIn('title: "Исключённые чаты"', screen)
        self.assertIn("pushControllerImpl?(shadowSpyExclusionsController(context: context))", screen)
        self.assertIn("s.spyExcludeBots = value", screen)
        # The new section sits between edits and restricted; order is section first.
        sections = screen[screen.index("private enum AyuSpySection"):]
        sections = sections[:sections.index("}")]
        self.assertLess(sections.index("case edits"), sections.index("case exclusions"))
        self.assertLess(sections.index("case exclusions"), sections.index("case restricted"))
        less = screen[screen.index("static func <(lhs: AyuSpyEntry"):]
        less = less[:less.index("func item(")]
        self.assertIn("if lhs.section != rhs.section", less)
        # The auto-clean toggles keep media from cleanup, they do not exclude anything.
        self.assertIn('title: "Не очищать каналы"', screen)
        self.assertIn('title: "Не очищать ботов"', screen)
        self.assertNotIn('title: "Исключить каналы"', screen)

    def test_exclusions_screen(self):
        screen = read("SettingsUI/Sources/ShadowSpyExclusionsController.swift")
        self.assertIn("ShadowBotApiPeerId.peerId(parsing: value)", screen)
        self.assertIn('placeholder: "-100123456789"', screen)
        self.assertIn("makeContactMultiselectionController", screen)
        # The picker returns the whole selection: merge it so ids added by hand survive.
        self.assertIn("shadowMergedSpyExclusions(current: ids, selected: selected)", screen)
        self.assertIn("ShadowBotApiPeerId.botApiId(peerId)", screen)
        self.assertIn("ids.filter { $0 != id }", screen)

    def test_links_docs_and_search(self):
        links = read(CORE + "ShadowSettingLinks.swift")
        docs = (ROOT / "docs/shadow-links.md").read_text(encoding="utf-8")
        search = read("SettingsUI/Sources/ShadowSettingsSearchIndex.swift")
        self.assertIn('slug: "exclude-bots", entryId: 33, key: "spyExcludeBots"', links)
        self.assertIn('slug: "excluded-chats", entryId: 34, key: nil', links)
        self.assertEqual(links.count('since: "1.14.1"'), 2)
        self.assertIn('slug: "clean-skip-channels", entryId: 21, key: "mediaAutoCleanKeepChannels", title: "Не очищать каналы"', links)
        self.assertIn('slug: "clean-skip-bots", entryId: 22, key: "mediaAutoCleanKeepBots", title: "Не очищать ботов"', links)
        for slug in ("exclude-bots", "excluded-chats"):
            self.assertIn(f"`shadow://spy/{slug}`", docs)
        self.assertIn("| `shadow://spy/clean-skip-bots` | Не очищать ботов |", docs)
        self.assertIn("destination: .spy, entryId: 33,", search)
        self.assertIn("destination: .spy, entryId: 34,", search)


if __name__ == "__main__":
    unittest.main()

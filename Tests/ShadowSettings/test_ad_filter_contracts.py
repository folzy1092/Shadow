"""Source contracts for the ad filter (1.6.0) and the empty chat list preview."""
from pathlib import Path
import json
import unittest

ROOT = Path(__file__).resolve().parents[2]
SUB = ROOT / "submodules"


def read(path):
    return (SUB / path).read_text(encoding="utf-8")


class AdFilterContracts(unittest.TestCase):
    def test_settings_fields_and_defaults(self):
        settings = read("TelegramCore/Sources/AyuGram/AyuGramSettings.swift")
        for line in (
            "public var adFilterChannels: Bool = true",
            "public var adFilterGroups: Bool = false",
            "public var adFilterForwarded: Bool = false",
            "public var adHideCompletely: Bool = true",
        ):
            self.assertIn(line, settings)
        for key, default in (("adFilterChannels", 1), ("adFilterGroups", 0), ("adFilterForwarded", 0), ("adHideCompletely", 1)):
            self.assertIn(f'forKey: "{key}")) ?? {default}) != 0', settings)
            self.assertIn(f'forKey: "{key}")\n', settings)
        # The Full disguise looks like stock Telegram: no ad hiding.
        vanilla = settings[settings.index("public static var vanillaSettings"):]
        vanilla = vanilla[:vanilla.index("return settings")]
        self.assertIn("settings.adFilterChannels = false", vanilla)

    def test_portable_and_linked(self):
        document = read("TelegramCore/Sources/AyuGram/ShadowSettingsDocument.swift")
        transfer = read("TelegramCore/Sources/AyuGram/ShadowSettingsTransfer.swift")
        links = read("TelegramCore/Sources/AyuGram/ShadowSettingLinks.swift")
        docs = (ROOT / "docs/shadow-links.md").read_text(encoding="utf-8")
        for key, slug, entry in (("adFilterChannels", "ads-channels", 40001), ("adFilterGroups", "ads-groups", 40002), ("adFilterForwarded", "ads-forwarded", 40003), ("adHideCompletely", "ads-hide-completely", 40004)):
            self.assertIn(f'"{key}"', document)
            self.assertIn(f'"{key}": \\.{key}', transfer)
            self.assertIn(f'slug: "{slug}", entryId: {entry}, key: "{key}"', links)
            self.assertIn(f"`shadow://filters/{slug}`", docs)

    def test_screen_rows(self):
        screen = read("SettingsUI/Sources/ShadowMessageFiltersController.swift")
        self.assertIn('text: "РЕКЛАМА"', screen)
        for title in ('"В каналах"', '"В группах"', '"В пересланных"', '"Скрывать полностью"'):
            self.assertIn(title, screen)
        # Section first, so the ad rows (ids 40000+) sit on top.
        self.assertIn("return lhs.section < rhs.section", screen)
        search = read("SettingsUI/Sources/ShadowSettingsSearchIndex.swift")
        for entry in (40001, 40002, 40003, 40004):
            self.assertIn(f"destination: .filters, entryId: {entry},", search)

    def test_one_check_for_chat_and_chat_list(self):
        hide = read("TelegramCore/Sources/AyuGram/ShadowLocalHide.swift")
        self.assertIn("ShadowAdMarkersStore.shared.matcher.isAd(texts: shadowAdSearchTexts(message))", hide)
        self.assertIn("message.flags.contains(.Incoming)", hide)
        self.assertIn('return "Скрыта реклама"', hide)
        self.assertIn("return !settings.adHideCompletely", hide)
        for url_kind in ("case let .TextUrl(url)", "case let .url(url)", "content.url"):
            self.assertIn(url_kind, hide)
        history = read("TelegramUI/Sources/ChatHistoryEntriesForView.swift")
        self.assertIn("shadowLocalHideReason(message, settings: shadowSettings, accountPeerId: accountPeerId)", history)
        chat_list = read("ChatListUI/Sources/Node/ChatListItem.swift")
        self.assertIn("shadowLocalHideReason(lastMessage, settings: shadowSettings, accountPeerId: item.context.account.peerId) != nil", chat_list)
        self.assertIn("var shadowPreviewHidden = false", chat_list)
        self.assertIn("} else if shadowPreviewHidden {", chat_list)
        self.assertIn("if !ignoreForwardedIcon && !shadowPreviewHidden {", chat_list)

    def test_remote_markers(self):
        ad = read("TelegramCore/Sources/AyuGram/ShadowAdFilter.swift")
        self.assertIn("https://raw.githubusercontent.com/folzy1092/tgfork/main/shadow-ad-markers.json", ad)
        # No referral links among the markers (Folzy, 2026-10-08).
        builtin = ad[ad.index("public static let builtIn"):ad.index("private struct File")]
        self.assertNotIn("start=", builtin)
        self.assertNotIn("ref=", builtin)
        account = read("TelegramCore/Sources/Account/Account.swift")
        self.assertIn("ShadowAdMarkersStore.shared.startIfNeeded()", account)
        script = (ROOT / "build-system/ci/test_shadow_foundation.py").read_text(encoding="utf-8")
        self.assertIn("Tests/ShadowSettings/AdFilterTests.swift", script)

    def test_ci_parallel_builds(self):
        workflow = (ROOT / ".github/workflows/build.yml").read_text(encoding="utf-8")
        self.assertIn("group: shadow-build-${{ github.ref }}-${{ github.sha }}", workflow)
        self.assertEqual(workflow.count('"--latest=${LATEST}"'), 2)


if __name__ == "__main__":
    unittest.main()

"""Source contracts for shadow:// and tg://shadow/ quick links."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
SUB = ROOT / "submodules"


def read(path):
    return (SUB / path).read_text(encoding="utf-8")


class LinksContracts(unittest.TestCase):
    def test_scheme_is_registered(self):
        build = (ROOT / "Telegram/BUILD").read_text(encoding="utf-8")
        self.assertIn("<string>shadow</string>", build)

    def test_both_forms_reach_the_router(self):
        open_url = read("TelegramUI/Sources/OpenUrl.swift")
        self.assertIn("if let shadowLink = ShadowLinks.parse(url) {", open_url)
        self.assertIn("shadowOpenLink(context: context, link: shadowLink, navigationController: navigationController)", open_url)
        # Before tg:// parsing, so tg://shadow/ never falls through to an unknown deep link.
        self.assertLess(open_url.index("ShadowLinks.parse(url)"), open_url.index("guard let canonicalUrl = canonicalExternalUrl(from: url)"))
        chat = read("TelegramUI/Sources/ChatController.swift")
        self.assertIn("if ShadowLinks.isShadowLink(url) {", chat)

    def test_links_are_highlighted_in_messages(self):
        bubble = read("TelegramUI/Components/Chat/ChatMessageTextBubbleContentNode/Sources/ChatMessageTextBubbleContentNode.swift")
        self.assertIn("entities = ShadowLinks.addingLinkEntities(text: rawText, to: entities)", bubble)

    def test_every_documented_command_is_routed(self):
        router = read("SettingsUI/Sources/ShadowLinkRouter.swift")
        doc = (ROOT / "docs/shadow-links.md").read_text(encoding="utf-8")
        commands = set(re.findall(r"`shadow://([a-z]+)", doc))
        self.assertTrue(commands)
        for command in commands - {"settings"}:
            self.assertIn(f'"{command}"', router, command)
        self.assertIn("ShadowDisguise.shared.hidesSettings", router)

    def test_foundation_suite_compiles_links(self):
        script = (ROOT / "build-system/ci/test_shadow_foundation.py").read_text(encoding="utf-8")
        self.assertIn("Tests/ShadowSettings/LinksTests.swift", script)


if __name__ == "__main__":
    unittest.main()

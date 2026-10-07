"""Source contracts: a link this Shadow does not know says which version it needs."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SUB = ROOT / "submodules"


def read(path):
    return (SUB / path).read_text(encoding="utf-8")


class UnsupportedLinkContracts(unittest.TestCase):
    def test_router_reports_unknown_settings_and_links(self):
        router = read("SettingsUI/Sources/ShadowLinkRouter.swift")
        self.assertIn("if !link.arguments.isEmpty, ShadowSettingLinks.isScreen(link.command) {", router)
        self.assertIn("shadowShowUnsupportedLink(context: context, link: link, isSetting: true, push: push)", router)
        self.assertIn("shadowShowUnsupportedLink(context: context, link: link, isSetting: false, push: push)", router)
        self.assertIn('let linkVersion = link.query["v"]', router)
        self.assertIn("ShadowSettingLinks.unsupportedText(isSetting: isSetting, linkVersion: linkVersion, current: ShadowVersion.fork)", router)
        self.assertIn("push(ayuGramSettingsController(context: context, autoCheckUpdates: true))", router)
        # The unknown setting check comes after the known setting is opened.
        self.assertLess(router.index("ShadowSettingLinks.find(screen: link.command, slug: slug)"), router.index("ShadowSettingLinks.isScreen(link.command)"))

    def test_copied_links_carry_the_version(self):
        ui = read("SettingsUI/Sources/ShadowSettingLinkUI.swift")
        self.assertNotIn("copy(setting.path,", ui)
        self.assertIn('copy(setting.link(.open), "Путь к настройке скопирован")', ui)
        links = read("TelegramCore/Sources/AyuGram/ShadowSettingLinks.swift")
        self.assertIn('return result + (result.contains("?") ? "&" : "?") + "v=\\(since)"', links)


if __name__ == "__main__":
    unittest.main()

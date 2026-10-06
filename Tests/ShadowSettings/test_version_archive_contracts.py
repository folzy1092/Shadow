"""Source contracts: "Архив версий" (announced builds since the device whitelist)."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
SUB = ROOT / "submodules"


def read(path):
    return (SUB / path).read_text(encoding="utf-8")


class VersionArchiveContracts(unittest.TestCase):
    def test_floor_is_the_whitelist_build(self):
        update = read("TelegramCore/Sources/AyuGram/ShadowUpdateCheck.swift")
        self.assertIn("public static let minimumBuild = 34725", update)
        self.assertIn(".filter { $0.build >= minimumBuild }", update)

    def test_changelog_entries_carry_version_and_ipa(self):
        changelog = json.loads((ROOT / "shadow-changelog.json").read_text(encoding="utf-8"))
        shown = [entry for entry in changelog["entries"] if entry["build"] >= 34725]
        self.assertTrue(shown)
        for entry in shown:
            self.assertRegex(entry.get("version", ""), r"^\d+\.\d+\.\d+(-\d+\.\d+\.\d+)?$", entry["build"])
            self.assertTrue(entry.get("ipa_url", "").startswith("https://github.com/folzy1092/"), entry["build"])
            self.assertTrue(entry["ipa_url"].endswith(f"build-{entry['build']}/Shadow.ipa"), entry["build"])

    def test_screen_is_in_the_hub_and_links(self):
        hub = read("SettingsUI/Sources/AyuGramSettingsController.swift")
        self.assertIn('title: "Архив версий"', hub)
        self.assertIn(".emergency, .versionArchive, .infoFooter]", hub)
        router = read("SettingsUI/Sources/ShadowLinkRouter.swift")
        self.assertIn('case "versions", "archive":', router)
        screen = read("SettingsUI/Sources/ShadowVersionArchiveController.swift")
        self.assertIn("ShadowVersionArchive.rows(entries: entries, installedBuild: ShadowUpdateCheck.installedBuild)", screen)
        self.assertIn("ShadowVersionArchive.ipaURL(entry)", screen)

    def test_announcing_keeps_the_archive_filled(self):
        tool = (ROOT / "tools/shadow-announce.py").read_text(encoding="utf-8")
        self.assertIn('"ipa_url": IPA.format(build=args.build)', tool)
        self.assertIn('"version": args.version', tool)
        worker = (ROOT / "tools/shadow-bot/worker.js").read_text(encoding="utf-8")
        self.assertIn('"shadow-changelog.json", changelog', worker)
        self.assertIn("version, ipa_url: ipaURL", worker)


if __name__ == "__main__":
    unittest.main()

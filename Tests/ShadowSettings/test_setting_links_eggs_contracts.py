"""Source contracts: settings toggle links, header button steps, easter eggs, banner sync."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
SUB = ROOT / "submodules"


def read(path):
    return (SUB / path).read_text(encoding="utf-8")


REGISTRY = read("TelegramCore/Sources/AyuGram/ShadowSettingLinks.swift")
ROWS = re.findall(r'ShadowSettingLink\(screen: "(\w+)", slug: "([\w-]+)", entryId: ([\d_]+), key: (?:"(\w+)"|nil)', REGISTRY)

SCREEN_FILES = {
    "customization": ("SettingsUI/Sources/AyuGramSettingsController.swift", "AyuCustomizationEntry"),
    "spy": ("SettingsUI/Sources/AyuGramSettingsController.swift", "AyuSpyEntry"),
    "ghost": ("SettingsUI/Sources/AyuGramSettingsController.swift", "AyuGhostEntry"),
    "profile": ("SettingsUI/Sources/AyuGramSettingsController.swift", "AyuMiscEntry"),
    "misc": ("SettingsUI/Sources/ShadowPushDiagnosticsController.swift", "ShadowMiscEntry"),
    "filters": ("SettingsUI/Sources/ShadowMessageFiltersController.swift", "ShadowMessageFiltersEntry"),
    "screenshot": ("SettingsUI/Sources/ShadowMessageScreenshotSettingsController.swift", "ScreenshotSettingEntry"),
    "locks": ("SettingsUI/Sources/ShadowChatLocksController.swift", "ShadowChatLocksEntry"),
    "space": ("SettingsUI/Sources/ShadowSecondSpaceController.swift", "ShadowSecondSpaceEntry"),
    "feed": ("SettingsUI/Sources/ShadowFeedSettingsController.swift", "ShadowFeedSettingsEntry"),
}


def stable_ids(path, enum):
    source = read(path)
    body = source.split(f"enum {enum}", 1)[1]
    section = body.split("var stableId", 1)[1].split("\n    }\n", 1)[0]
    ids = set()
    for value in re.findall(r"return (-?[\d_]+)", section):
        ids.add(int(value.replace("_", "")))
    return ids


class SettingLinksContracts(unittest.TestCase):
    def test_registry_is_complete(self):
        self.assertGreaterEqual(len(ROWS), 70)

    def test_every_key_is_a_real_setting(self):
        transfer = read("TelegramCore/Sources/AyuGram/ShadowSettingsTransfer.swift") + read("TelegramCore/Sources/AyuGram/ShadowSettingLinksApply.swift")
        keys = set(re.findall(r'"(\w+)": \\\.', transfer))
        for screen, slug, _, key in ROWS:
            if key:
                self.assertIn(key, keys, f"{screen}/{slug}")

    def test_every_entry_id_exists_on_its_screen(self):
        for screen, slug, entry, _ in ROWS:
            path, enum = SCREEN_FILES[screen]
            self.assertIn(int(entry.replace("_", "")), stable_ids(path, enum), f"{screen}/{slug}")

    def test_every_screen_opens_and_has_the_menu(self):
        ui = read("SettingsUI/Sources/ShadowSettingLinkUI.swift")
        for screen in SCREEN_FILES:
            self.assertIn(f'case "{screen}":', ui, screen)
            path, _ = SCREEN_FILES[screen]
            self.assertIn(f'screen: "{screen}", rows: linkRows', read(path), screen)

    def test_router_confirms_and_protects(self):
        router = read("SettingsUI/Sources/ShadowLinkRouter.swift")
        self.assertIn("ShadowSettingLinks.find(screen: link.command, slug: slug)", router)
        ui = read("SettingsUI/Sources/ShadowSettingLinkUI.swift")
        self.assertIn('title: "Изменить настройку?"', ui)
        self.assertIn("guard setting.isSwitchable, let key = setting.key else", ui)
        for slug in ("hide-preview", "intruder-photo", "exclusive"):
            self.assertRegex(REGISTRY, rf'slug: "{slug}", entryId: [\d_]+, key: nil, [^\n]*isProtected: true')

    def test_menu_items(self):
        ui = read("SettingsUI/Sources/ShadowSettingLinkUI.swift")
        for title in ("Скопировать ссылку-переключатель", "Скопировать путь к настройке", "Скопировать с текущим значением"):
            self.assertIn(title, ui)

    def test_focus_scrolls_and_pulses_once(self):
        navigation = read("SettingsUI/Sources/ShadowSettingsSearchNavigation.swift")
        self.assertIn("controller.shadowScrollToItem(index: index", navigation)
        self.assertIn("theme.overallDarkAppearance ? UIColor(white: 1.0", navigation)
        item_list = read("ItemListUI/Sources/ItemListController.swift")
        self.assertIn("public func shadowScrollToItem(index: Int, completion:", item_list)


class HeaderStepsContracts(unittest.TestCase):
    def test_toggles_change_together_without_asking(self):
        chat_list = read("ChatListUI/Sources/ChatListController.swift")
        self.assertIn("ShadowSettingsTransfer.applying(links: applied, to: current)", chat_list)
        self.assertIn("let applied = switchable + choices.map", chat_list)
        self.assertIn("fileprivate func shadowPerformHeaderSteps(", chat_list)
        transfer = read("TelegramCore/Sources/AyuGram/ShadowSettingLinksApply.swift")
        self.assertIn("ShadowSettingLinks.groupTarget(currentValues: toggled)", transfer)

    def test_shadow_settings_icon(self):
        chat_list = read("ChatListUI/Sources/ChatListController.swift")
        self.assertIn('return ("Item List/Icons/Shadow", false)', chat_list)


class EasterEggContracts(unittest.TestCase):
    def test_unknown_command_is_an_egg(self):
        router = read("SettingsUI/Sources/ShadowLinkRouter.swift")
        self.assertIn("context.sharedContext.shadowOpenEasterEgg(context: context, name: link.command", router)

    def test_player_cannot_be_closed_while_playing(self):
        eggs = read("TelegramUI/Sources/ShadowEasterEggs.swift")
        self.assertIn("guard let self, !self.isActuallyPlaying else", eggs)
        self.assertIn(".AVPlayerItemDidPlayToEndTime", eggs)

    def test_player_never_hangs_on_a_black_screen(self):
        eggs = read("TelegramUI/Sources/ShadowEasterEggs.swift")
        # AV1 videos: pick an H.264/HEVC alternative AVPlayer can play.
        self.assertIn("let file = playableFile(mainFile)", eggs)
        self.assertIn("file.alternativeRepresentations.filter { isPlayableCodec(videoCodec($0)) }", eggs)
        # A failed item or a video that never becomes ready shows the reason
        # on screen (nothing else logs it), then closes on a tap or after 10 s.
        self.assertIn("case .failed:\n                    self.fail(", eggs)
        self.assertIn('self.fail("Видео не запустилось за 10 с.")', eggs)
        self.assertIn("self.restartWatchdog(after: 10.0)", eggs)
        self.assertIn("self.failed || !self.isActuallyPlaying", eggs)
        # A hard link or a copy, not a symlink, gives AVPlayer its .mp4 name.
        self.assertIn("FileManager.default.linkItem(atPath: path, toPath: linkPath)", eggs)
        self.assertNotIn("createSymbolicLink", eggs)
        self.assertIn("duration + 3.0", eggs)
        self.assertIn('"tg://ayu/\\(name)"', eggs)

    def test_channels_come_from_the_whitelist(self):
        access = read("TelegramCore/Sources/AyuGram/ShadowDeviceAccess.swift")
        self.assertIn('object["easter_egg_channels"]', access)
        self.assertIn('"ayugram_easter"', access)
        worker = (ROOT / "tools/shadow-bot/worker.js").read_text(encoding="utf-8")
        self.assertIn('body.action === "save_easter_eggs"', worker)


class BannerSyncContracts(unittest.TestCase):
    def test_banners_follow_sync(self):
        media = read("TelegramCore/Sources/AyuGram/AyuSavedMedia.swift")
        self.assertEqual(media.count("postBannersChanged(basePath: basePath)"), 4)
        manager = read("TelegramUI/Sources/ShadowSettingsSyncManager.swift")
        self.assertIn("AyuSavedMedia.copyBanners(fromBasePath: basePath, toBasePath: target)", manager)
        self.assertIn("ShadowSettingsSync.syncBanners", manager)


if __name__ == "__main__":
    unittest.main()

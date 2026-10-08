"""Source contracts: ghost offer before stories, hidden greeting sticker,
deletion time in the message menu (Shadow 1.4.0)."""
from pathlib import Path
import unittest

SUB = Path(__file__).resolve().parents[2] / "submodules"


def read(path):
    return (SUB / path).read_text(encoding="utf-8")


class StoryGhostOfferContracts(unittest.TestCase):
    def test_offer_runs_only_with_ghost_off(self):
        stories = read("TelegramUI/Components/Stories/StoryContainerScreen/Sources/OpenStories.swift")
        self.assertIn("if ayuSettings.offerGhostBeforeStories, !ayuSettings.ghostMode, peerId != context.account.peerId {", stories)
        # Two stacked buttons: «Включить призрака» on top, «Смотреть так» below.
        self.assertIn('title: "Включить призрака"', stories)
        self.assertIn('title: "Смотреть так"', stories)
        self.assertLess(stories.index('title: "Включить призрака"'), stories.index('title: "Смотреть так"'))
        self.assertIn("actionLayout: .vertical", stories)
        self.assertIn("ShadowStoryGhostSession.begin(context: context", stories)
        # Checked before the older "hide this view?" prompt.
        self.assertLess(stories.index("offerGhostBeforeStories"), stories.index("effectiveAskBeforeStoryView, !ayuSettings.effectiveHideStoryViews"))

    def test_toggle_is_on_the_ghost_screen(self):
        hub = read("SettingsUI/Sources/AyuGramSettingsController.swift")
        self.assertIn(".offerGhostBeforeStories(settings.offerGhostBeforeStories),", hub)
        self.assertIn("case .offerGhostBeforeStories: return 5.5", hub)


class StoryGhostSessionContracts(unittest.TestCase):
    """Ghost from the offer lasts only while the stories are open."""

    def test_session_turns_ghost_on_and_saves_snapshot_first(self):
        session = read("TelegramUI/Components/Stories/StoryContainerScreen/Sources/ShadowStoryGhostSession.swift")
        self.assertIn('static let defaultsKey = "shadow.storyGhostSession.v1"', session)
        self.assertIn("settings.ghostMode = true", session)
        self.assertIn("settings.hideStoryViews = true", session)
        # The snapshot is written before the settings change.
        self.assertLess(session.index("ShadowStoryGhostSession.save(snapshot!)"), session.index("settings.ghostMode = true"))

    def test_session_ends_with_the_screen(self):
        screen = read("TelegramUI/Components/Stories/StoryContainerScreen/Sources/StoryContainerScreen.swift")
        self.assertIn("var shadowGhostSession: ShadowStoryGhostSession?", screen)
        self.assertEqual(screen.count("self.shadowGhostSession?.end()"), 2)
        stories = read("TelegramUI/Components/Stories/StoryContainerScreen/Sources/OpenStories.swift")
        self.assertIn("storyContainerScreen.shadowGhostSession = ghostSession", stories)
        # Stories that never opened end the session at once.
        self.assertIn("if !didHandOverGhostSession {", stories)

    def test_killed_app_restores_on_launch(self):
        shared = read("TelegramUI/Sources/SharedAccountContext.swift")
        self.assertIn("ShadowStoryGhostSession.recoverAfterLaunch(sharedContext: self)", shared)


class GreetingStickerContracts(unittest.TestCase):
    def test_greeting_card_can_be_hidden(self):
        empty = read("TelegramUI/Components/Chat/ChatEmptyNode/Sources/ChatEmptyNode.swift")
        self.assertIn("} else if currentAyuGramSettings(accountId: self.context.account.id).hideGreetingSticker {", empty)
        hub = read("SettingsUI/Sources/AyuGramSettingsController.swift")
        self.assertIn("entries.append(.hideGreetingSticker(settings.hideGreetingSticker))", hub)


class DeletedTimeContracts(unittest.TestCase):
    def test_menu_shows_deletion_time(self):
        menu = read("TelegramUI/Sources/ChatInterfaceStateContextMenus.swift")
        self.assertIn("as? DeletedMessageAttribute, deleted.date > 0", menu)
        self.assertIn("deletedTime: deleted.date, action: nil", menu)
        self.assertIn('"удалено сегодня в \\(value)"', menu)
        self.assertIn('UIImage(bundleImageName: "Chat/Context Menu/Delete")', menu)


if __name__ == "__main__":
    unittest.main()

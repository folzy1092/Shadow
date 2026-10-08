"""Source contracts for «Лента» (beta, 1.9.0)."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
SUB = ROOT / "submodules"


def read(path):
    return (SUB / path).read_text(encoding="utf-8")


class FeedContracts(unittest.TestCase):
    def test_settings(self):
        settings = read("TelegramCore/Sources/AyuGram/AyuGramSettings.swift")
        for line in ("public var feedEnabled: Bool = false", "public var feedAutoplay: Bool = true", "public var feedShowFolders: Bool = false",
                     "public var feedIncludeMuted: Bool = true", "public var feedIncludeArchived: Bool = false", "public var feedMarkRead: Bool = true",
                     "public var feedPosition: Int32 = 1", "settings.feedEnabled = false"):
            self.assertIn(line, settings)
        document = read("TelegramCore/Sources/AyuGram/ShadowSettingsDocument.swift")
        self.assertIn('key == "feedPosition" && (0...2).contains(number)', document)

    def test_tab(self):
        root = read("TelegramUI/Sources/TelegramRootController.swift")
        self.assertIn("shadowInsertFeed(feedController, into: &controllers, position: feedSettings.feedPosition)", root)
        self.assertIn("private func shadowObserveFeedSettings()", root)
        self.assertIn("self.shadowObserveFeedSettings()", root)
        self.assertIn("controllers.firstIndex(where: { $0 === chatListController })", root)
        controller = read("TelegramUI/Sources/ShadowFeedController.swift")
        self.assertIn('self.tabBarItem.title = "Лента"', controller)
        self.assertIn("webView.loadFileURL(index, allowingReadAccessTo: self.folder)", controller)
        self.assertIn("ChatControllerImpl.openMessageReplies(", controller)
        self.assertIn("keepStack: .always", controller)

    def test_page_and_bridge_agree(self):
        page = read("TelegramCore/Sources/AyuGram/ShadowFeedPage.swift")
        controller = read("TelegramUI/Sources/ShadowFeedController.swift")
        sent = set(re.findall(r"post\(\{ action: '(\w+)'", page))
        handled = set(re.findall(r'case "(\w+)":', controller))
        self.assertTrue(sent)
        self.assertEqual(sent - handled, set())
        for call in ("Feed.init(", "Feed.setPosts(", "Feed.appendPosts(", "Feed.prependPosts(", "Feed.mediaReady(", "Feed.updatePost(", "Feed.setChips(", "Feed.setConfig("):
            self.assertIn(call, controller)
            self.assertIn(call.split(".")[1].rstrip("("), page)
        # Instagram-like autoplay: a second in the middle of the screen, muted.
        self.assertIn("}, 1000);", page)
        self.assertIn("v.muted = true", page)

    def test_only_local_posts_without_ads(self):
        collect = read("TelegramCore/Sources/AyuGram/ShadowFeedCollect.swift")
        self.assertIn("shadowLocalHideReason(message, settings: settings, accountPeerId: accountPeerId) != nil", collect)
        self.assertNotIn("fetchMessageHistoryHole", collect)
        self.assertIn("ShadowChatLockStore.shared.requiresUnlock", collect)
        self.assertIn("applyMaxReadIndexInteractively(index:", collect)

    def test_foundation_suite(self):
        script = (ROOT / "build-system/ci/test_shadow_foundation.py").read_text(encoding="utf-8")
        self.assertIn("Tests/ShadowSettings/FeedTests.swift", script)


if __name__ == "__main__":
    unittest.main()

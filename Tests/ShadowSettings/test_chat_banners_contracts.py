"""Source contracts for «Фоны чатов» (1.10.0)."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SUB = ROOT / "submodules"


def read(path):
    return (SUB / path).read_text(encoding="utf-8")


class ChatBannersContracts(unittest.TestCase):
    def test_setting(self):
        settings = read("TelegramCore/Sources/AyuGram/AyuGramSettings.swift")
        self.assertIn("public var chatBannersEnabled: Bool = false", settings)
        self.assertIn('forKey: "chatBannersEnabled")) ?? 0) != 0', settings)
        self.assertIn('forKey: "chatBannersEnabled")', settings)
        self.assertIn("settings.chatBannersEnabled = false", settings)
        self.assertIn('"chatBannersEnabled"', read("TelegramCore/Sources/AyuGram/ShadowSettingsDocument.swift"))
        self.assertIn('"chatBannersEnabled": \\.chatBannersEnabled', read("TelegramCore/Sources/AyuGram/ShadowSettingsTransfer.swift"))
        links = read("TelegramCore/Sources/AyuGram/ShadowSettingLinks.swift")
        self.assertIn('slug: "chat-banners", entryId: 122, key: "chatBannersEnabled"', links)
        self.assertIn('slug: "chat-banners-photos", entryId: 123, key: nil', links)
        screen = read("SettingsUI/Sources/AyuGramSettingsController.swift")
        self.assertIn("case .chatBanners: return 122", screen)
        self.assertIn("case .chatBannersList: return 123", screen)
        self.assertIn("controller?.push(shadowChatBannersController(context: context))", screen)
        search = read("SettingsUI/Sources/ShadowSettingsSearchIndex.swift")
        self.assertIn("destination: .customization, entryId: 122,", search)
        self.assertIn("destination: .customization, entryId: 123,", search)
        docs = (ROOT / "docs/shadow-links.md").read_text(encoding="utf-8")
        self.assertIn("`shadow://customization/chat-banners`", docs)
        self.assertIn("`shadow://customization/chat-banners-photos`", docs)

    def test_chat_list(self):
        node = read("ChatListUI/Sources/Node/ChatListNode.swift")
        # Both mapping paths give rows their own presentation data.
        self.assertEqual(node.count("let shadowBanners = ShadowChatBannerBatch(context: context, location: location)"), 2)
        self.assertEqual(node.count("presentationData: shadowBanners.presentationData(presentationData, peerId: peer.peerId),"), 2)
        self.assertIn("forName: ShadowChatBannerStore.didChangeNotification", node)
        rendering = read("ChatListUI/Sources/Node/ShadowChatBannerRendering.swift")
        # Only the chat list itself (folders, archive) — not forums or saved chats.
        self.assertIn("if case .chatList = location {", rendering)
        self.assertIn("currentAyuGramSettings(accountId: context.account.id).chatBannersEnabled", rendering)
        item = read("ChatListUI/Sources/Node/ChatListItem.swift")
        self.assertIn("self.insertSubnode(bannerNode, aboveSubnode: self.backgroundNode)", item)
        self.assertIn("strongSelf.shadowUpdateChatBanner(item: item", item)
        data = read("ChatListUI/Sources/Node/ChatListPresentationData.swift")
        self.assertIn("public let shadowChatBanner: ShadowChatBannerAppearance?", data)

    def test_storage_is_local(self):
        store = read("TelegramCore/Sources/AyuGram/ShadowChatBannerStore.swift")
        self.assertIn("AyuSavedMedia.ensureDirectory(basePath: basePath)", store)
        self.assertNotIn("URLSession", store)


if __name__ == "__main__":
    unittest.main()

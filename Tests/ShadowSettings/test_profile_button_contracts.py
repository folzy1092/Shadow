"""Source contracts: profile and gift header buttons, shadow://me|user|gift."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SUB = ROOT / "submodules"


def read(path):
    return (SUB / path).read_text(encoding="utf-8")


class ProfileButtonContracts(unittest.TestCase):
    def test_actions_are_offered(self):
        buttons = read("TelegramCore/Sources/AyuGram/ShadowHeaderButtons.swift")
        self.assertIn("case openProfile", buttons)
        self.assertIn("case sendGift", buttons)
        self.assertIn(".setting, .openProfile, .sendGift,", buttons)

    def test_router_opens_profiles_and_gifts(self):
        router = read("SettingsUI/Sources/ShadowLinkRouter.swift")
        self.assertIn('case "me", "user":', router)
        self.assertIn("mode: .myProfile", router)
        self.assertIn('case "gift", "gifts":', router)
        self.assertIn("makePremiumGiftController(context: context, source: .settings(birthdays)", router)

    def test_header_uses_the_avatar(self):
        chat_list = read("ChatListUI/Sources/ChatListController.swift")
        self.assertIn("first.action == .openProfile", chat_list)
        self.assertIn("ShadowHeaderAvatars.shared.iconName(context: context, link: first.link)", chat_list)
        self.assertIn("ShadowHeaderAvatars.shared.version.get()", chat_list)
        self.assertIn('self.shadowOpenHeaderUrl("shadow://gift")', chat_list)
        button = read("TelegramUI/Components/ChatListHeaderComponent/Sources/NavigationButtonComponent.swift")
        self.assertIn('imageName.hasPrefix("img:")', button)
        self.assertIn("public enum NavigationButtonCustomImages", button)

    def test_picker_offers_me_chats_and_typing(self):
        picker = read("SettingsUI/Sources/ShadowHeaderButtonsController.swift")
        for title in ("Мой профиль", "Выбрать из чатов…", "Ввести @username или ID…"):
            self.assertIn(title, picker)
        self.assertIn("case .openProfile:\n                    pickProfile(completion)", picker)


if __name__ == "__main__":
    unittest.main()

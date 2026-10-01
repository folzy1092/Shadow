"""Source contracts for the chat lock (spec 2026-10-01, section 5)."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SUB = ROOT / "submodules"


def read(path):
    return (SUB / path).read_text()


class ChatLockContracts(unittest.TestCase):
    def test_store_hashes_password_and_delays_reset(self):
        store = read("TelegramCore/Sources/AyuGram/ShadowChatLock.swift")
        self.assertIn("CCKeyDerivationPBKDF", store)
        self.assertIn("kCCPRFHmacAlgSHA256", store)
        self.assertIn("resetDelay: TimeInterval = 60.0 * 60.0", store)
        self.assertNotIn('forKey: "password")', store)
        self.assertIn("chat-lock", (ROOT / "build-system/ci/test_shadow_foundation.py").read_text())

    def test_chat_screen_is_covered_on_every_entry(self):
        controller = read("TelegramUI/Sources/ChatController.swift")
        self.assertIn("self.shadowChatLockUpdate(autoAuthenticate: false)", controller)
        self.assertIn("self.shadowChatLockUpdate(autoAuthenticate: true)", controller)
        self.assertIn("var shadowChatLockObserver: ShadowChatLockObserverHolder?", controller)
        ui = read("TelegramUI/Sources/ShadowChatLockUI.swift")
        self.assertIn("UIApplication.didEnterBackgroundNotification", ui)
        self.assertIn("relockAll()", ui)
        self.assertIn("case .standard(.previewing) = self.mode", ui)
        self.assertIn("shadowSetChatLockContentHidden(true)", ui)
        node = read("TelegramUI/Sources/ChatControllerNode.swift")
        self.assertIn("func shadowSetChatLockContentHidden(_ hidden: Bool)", node)

    def test_unlocking_requires_authentication(self):
        ui = read("TelegramUI/Sources/ShadowChatLockUI.swift")
        unlock = ui.split("static func unlockChatPermanently", 1)[1].split("\n    }\n", 1)[0]
        self.assertIn("self.authenticate(", unlock)
        self.assertLess(unlock.index("if success"), unlock.index("setLocked(false"))

    def test_chat_list_spoiler_and_menu(self):
        item = read("ChatListUI/Sources/Node/ChatListItem.swift")
        self.assertEqual(item.count("ShadowChatLockStore.shared.isLocked"), 2)
        self.assertIn("spoilers = length > 0 ? [NSRange(location: 0, length: length)] : nil", item)
        menus = read("ChatListUI/Sources/ChatContextMenus.swift")
        self.assertIn("private func shadowStockChatContextMenuItems(", menus)
        self.assertIn('"Заблокировать чат"', menus)
        node = read("ChatListUI/Sources/Node/ChatListNode.swift")
        self.assertIn("ShadowChatLockStore.didChangeNotification", node)

    def test_shared_context_bridge(self):
        protocol = read("AccountContext/Sources/AccountContext.swift")
        impl = read("TelegramUI/Sources/SharedAccountContext.swift")
        for name in ("shadowChatLockAuthenticate", "shadowChatLockCreatePassword", "shadowChatLockLockChat", "shadowChatLockUnlockChat"):
            self.assertIn(f"func {name}(", protocol)
            self.assertIn(f"public func {name}(", impl)


if __name__ == "__main__":
    unittest.main()

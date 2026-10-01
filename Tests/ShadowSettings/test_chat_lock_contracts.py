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

    def test_locked_history_is_hidden_not_just_covered(self):
        # The cover alone was created before the first layout (zero frame) and
        # left the history readable and scrollable, including in previews.
        node = read("TelegramUI/Sources/ChatControllerNode.swift")
        hide = node.split("func shadowSetChatLockContentHidden(_ hidden: Bool)", 1)[1].split("\n    }\n", 1)[0]
        self.assertIn("self.historyNodeContainer.isHidden = hidden || restricted", hide)
        self.assertIn("self.historyNodeContainer.isHidden = self.shadowChatLockHidesHistory", node)
        self.assertNotIn("self.historyNodeContainer.isHidden = false", node)
        controller = read("TelegramUI/Sources/ChatController.swift")
        self.assertIn("self.validLayout = layout\n        self.shadowChatLockLayout()", controller)

    def test_locked_chat_opens_only_after_authentication(self):
        shared = read("TelegramUI/Sources/SharedAccountContext.swift")
        nav = shared.split("public func navigateToChatController(_ params: NavigateToChatControllerParams) {", 1)[1].split("\n    }\n", 1)[0]
        self.assertIn("ShadowChatLockStore.shared.requiresUnlock(", nav)
        self.assertLess(nav.index("ShadowChatLockUI.authenticate("), nav.index("navigateToChatControllerImpl(params)"))
        self.assertIn("guard success else {\n                    return\n                }", nav)

    def test_leaving_a_chat_relocks_it(self):
        controller = read("TelegramUI/Sources/ChatController.swift")
        hook = controller.split("override public func viewDidDisappear(_ animated: Bool) {", 1)[1].split("\n    }\n", 1)[0]
        self.assertIn("ShadowChatLockStore.shared.relock(", hook)
        self.assertIn("if !stillInStack", hook)

    def test_intruder_photo(self):
        entry = read("PasscodeUI/Sources/PasscodeEntryController.swift")
        self.assertIn("ShadowIntruderCamera.captureIfEnabled(reason: .passcode)", entry)
        ui = read("TelegramUI/Sources/ShadowChatLockUI.swift")
        self.assertIn("ShadowIntruderCamera.captureIfEnabled(reason: .chatLock)", ui)
        camera = read("PasscodeUI/Sources/ShadowIntruderCamera.swift")
        # Never prompts for camera access on the lock screen.
        self.assertNotIn("requestAccess", camera)
        self.assertIn("authorizationStatus(for: .video) == .authorized", camera)
        delivery = read("TelegramUI/Sources/ShadowIntruderDelivery.swift")
        self.assertIn("peerId: context.account.peerId", delivery)
        self.assertIn("UIImageWriteToSavedPhotosAlbum", delivery)
        app = read("TelegramUI/Sources/ApplicationContext.swift")
        self.assertIn("ShadowIntruderDelivery.deliverPending(context: self.context)", app)

    def test_unlocking_requires_authentication(self):
        ui = read("TelegramUI/Sources/ShadowChatLockUI.swift")
        unlock = ui.split("static func unlockChatPermanently", 1)[1].split("\n    }\n", 1)[0]
        self.assertIn("self.authenticate(", unlock)
        self.assertLess(unlock.index("if success"), unlock.index("setLocked(false"))

    def test_chat_list_spoiler_and_menu(self):
        item = read("ChatListUI/Sources/Node/ChatListItem.swift")
        self.assertIn("private func shadowChatListItemIsLocked(item: ChatListItem, peerId: EnginePeer.Id) -> Bool", item)
        self.assertIn("shadowIsLocked = shadowChatListItemIsLocked(item: item, peerId: itemPeer.peerId)", item)
        self.assertIn("spoilers = length > 0 ? [NSRange(location: 0, length: length)] : nil", item)
        menus = read("ChatListUI/Sources/ChatContextMenus.swift")
        self.assertIn("private func shadowStockChatContextMenuItems(", menus)
        self.assertIn('"Защитить чат"', menus)
        self.assertIn("items.insert(lockItem, at: pinIndex + 1)", menus)
        controller = read("ChatListUI/Sources/ChatListController.swift")
        self.assertIn('id: "shadowLock"', controller)
        self.assertIn("func shadowToggleLockForSelectedChats(", controller)
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

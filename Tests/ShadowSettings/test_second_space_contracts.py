"""Source contracts for the second space (spec 2026-10-01, section 6)."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SUB = ROOT / "submodules"


def read(path):
    return (SUB / path).read_text()


class SecondSpaceContracts(unittest.TestCase):
    def test_store_hashes_code_and_keeps_space_in_memory(self):
        store = read("TelegramCore/Sources/AyuGram/ShadowSpaces.swift")
        self.assertIn("ShadowChatLockStore.derive(password: code", store)
        self.assertIn("private var activeSpaceValue: Space = .main", store)
        self.assertNotIn("forKey: Key.activeSpace", store)
        self.assertIn("'spaces'", (ROOT / "build-system/ci/test_shadow_foundation.py").read_text())

    def test_passcode_screen_picks_the_space(self):
        entry = read("PasscodeUI/Sources/PasscodeEntryController.swift")
        check = entry.split("self.controllerNode.checkPasscode = {", 1)[1].split("self.controllerNode.requestBiometrics", 1)[0]
        # Only the app lock screen (no `completed` handler) accepts the second code.
        self.assertIn("if strongSelf.completed == nil && strongSelf.applicationBindings.isMainApp {", check)
        self.assertIn("ShadowSpaceStore.shared.setActiveSpace(.second)", check)
        self.assertLess(check.index("setActiveSpace(.second)"), check.index("if succeed {\n                if let completed"))
        biometrics = entry.split("public func requestBiometrics(", 1)[1]
        self.assertIn("ShadowSpaceStore.shared.setActiveSpace(.main)", biometrics)
        applock = read("AppLock/Sources/AppLock.swift")
        self.assertIn("ShadowSpaceStore.shared.setActiveSpace(.main)", applock)

    def test_chat_list_and_search_filter(self):
        entries = read("ChatListUI/Sources/Node/ChatListNodeEntries.swift")
        self.assertIn("if case .chatList = entry.index, let peerId, shadowIsHidden(peerId) {", entries)
        self.assertIn("group.items.filter { !shadowIsHidden($0.peer.peerId) }", entries)
        self.assertIn("!shadowIsHidden(item.item.renderedPeer.peerId)", entries)
        node = read("ChatListUI/Sources/Node/ChatListNode.swift")
        self.assertIn("forName: ShadowSpaceStore.didChangeNotification", node)
        search = read("ChatListUI/Sources/ChatListSearchListPaneNode.swift")
        self.assertIn("case let .localPeerId(peerId), let .globalPeerId(peerId):", search)
        self.assertIn("case let .messageId(messageId, _):", search)
        self.assertEqual(search.count("ShadowSpaceStore.shared.isHidden("), 3)
        recent = read("ChatListSearchRecentPeersNode/Sources/ChatListSearchRecentPeersNode.swift")
        self.assertIn("ShadowSpaceStore.shared.isHidden(accountPeerId: accountPeerId.toInt64()", recent)

    def test_folder_badges_skip_hidden_chats(self):
        tabs = read("ChatListUI/Sources/TabBarChatListFilterController.swift")
        self.assertIn("for peerId in shadowIncludePeers {", tabs)
        self.assertIn("for peerId in shadowExcludePeers {", tabs)
        self.assertIn("var additionalPeerIds = shadowHidden", tabs)

    def test_second_only_chats_are_muted(self):
        sync = read("TelegramCore/Sources/AyuGram/ShadowSpacesSync.swift")
        self.assertIn("muteInterval: Int32.max)", sync)
        self.assertIn("store.saveMuteState(", sync)
        self.assertIn("store.takeSavedMuteState(", sync)
        self.assertIn("store.removeCode()", sync)

    def test_entry_points(self):
        menus = read("ChatListUI/Sources/ChatContextMenus.swift")
        self.assertIn("items.insert(spaceItem, at: pinIndex + 2)", menus)
        self.assertIn("func shadowSetSpaceVisibility(", menus)
        self.assertIn("visibility == .secondOnly && !ShadowSpaceStore.shared.hasCode", menus)
        controller = read("ChatListUI/Sources/ChatListController.swift")
        self.assertIn('id: "shadowSpace"', controller)
        self.assertIn('content: .icon(imageName: "sf:eye.slash")', controller)
        self.assertIn("func shadowChooseSpaceForSelectedChats(", controller)
        hub = read("SettingsUI/Sources/AyuGramSettingsController.swift")
        self.assertIn("pushControllerImpl?(shadowSecondSpaceController(context: context))", hub)
        screen = read("SettingsUI/Sources/ShadowSecondSpaceController.swift")
        self.assertIn("ShadowSpaceStore.validationError(code: first, format: format, mainCode: mainCode)", screen)
        self.assertIn("shadowRemoveSecondSpace(account: context.account)", screen)
        self.assertIn("store.setSecondSpaceExclusive(value)", screen)
        store = read("TelegramCore/Sources/AyuGram/ShadowSpaces.swift")
        self.assertIn("if self.activeSpaceValue == .second && self.secondSpaceExclusiveValue {", store)
        controller_src = read("ChatListUI/Sources/ChatListController.swift")
        # Edit-mode buttons read the selection when pressed (the header keeps the first closure).
        self.assertEqual(controller_src.count("parent.shadowCurrentSelectedPeerIds()"), 2)
        self.assertIn("ShadowCodeFieldLimiter.install(on: field, length: length, okAction: okAction)", screen)
        self.assertIn(".prefix(self.length)", screen)
        # In the main space the list never reveals second-space chats.
        self.assertIn(".filter { $0.value.isVisible(in: space) || space == .second }", screen)


if __name__ == "__main__":
    unittest.main()

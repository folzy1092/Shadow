"""Source contracts: the paperclip menu, activity imitation and pranks (1.13.7)."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SUB = ROOT / "submodules"


def read(path):
    return (SUB / path).read_text(encoding="utf-8")


class PaperclipContracts(unittest.TestCase):
    def test_settings_fields(self):
        settings = read("TelegramCore/Sources/AyuGram/AyuGramSettings.swift")
        # Off by default: the attachment button works as in Telegram.
        self.assertIn("public var paperclipMenu: Bool = false", settings)
        self.assertIn('forKey: "paperclipMenu")) ?? 0) != 0', settings)
        self.assertIn("settings.paperclipMenu = false", settings)
        for key in ("paperclipMenu", "paperclipActions", "paperclipPrankImitation", "paperclipPrankSeconds"):
            self.assertIn(f'forKey: "{key}")', settings)
        self.assertIn("ShadowPaperclip.normalizedActions(", settings)
        self.assertIn("ShadowPaperclip.normalizedPrankSeconds(", settings)

    def test_export_links_and_search(self):
        document = read("TelegramCore/Sources/AyuGram/ShadowSettingsDocument.swift")
        self.assertIn('"paperclipMenu", "paperclipPrankImitation"', document)
        self.assertIn('key == "paperclipActions" && text.count <= 600', document)
        self.assertIn('key == "paperclipPrankSeconds" && (1...60).contains(number)', document)
        transfer = read("TelegramCore/Sources/AyuGram/ShadowSettingsTransfer.swift")
        self.assertIn('"paperclipMenu": \\.paperclipMenu', transfer)
        self.assertIn('"paperclipPrankImitation": \\.paperclipPrankImitation', transfer)
        self.assertIn('values["paperclipActions"] = .text(settings.paperclipActions)', transfer)
        self.assertIn('values["paperclipPrankSeconds"] = .integer(Int64(settings.paperclipPrankSeconds))', transfer)
        links = read("TelegramCore/Sources/AyuGram/ShadowSettingLinks.swift")
        for slug, entry in (("paperclip-menu", 133), ("paperclip-actions", 134), ("paperclip-prank-recording", 135), ("paperclip-prank-seconds", 136)):
            self.assertIn(f'slug: "{slug}", entryId: {entry},', links)
            self.assertIn(f"`shadow://customization/{slug}`", (ROOT / "docs/shadow-links.md").read_text(encoding="utf-8"))
        search = read("SettingsUI/Sources/ShadowSettingsSearchIndex.swift")
        for entry in (133, 134, 135, 136):
            self.assertIn(f"destination: .customization, entryId: {entry},", search)
        screen = read("SettingsUI/Sources/AyuGramSettingsController.swift")
        for case, entry in (("paperclipMenu", 133), ("paperclipActions", 134), ("paperclipPrankImitation", 135), ("paperclipPrankSeconds", 136)):
            self.assertIn(f"case .{case}: return {entry}", screen)
        self.assertIn("controller?.push(shadowPaperclipActionsController(context: context))", screen)

    def test_hold_opens_the_menu(self):
        panel = read("TelegramUI/Components/Chat/ChatTextInputPanelNode/Sources/ChatTextInputPanelNode.swift")
        self.assertIn("self.attachmentButton.addGestureRecognizer(shadowPaperclipLongPress)", panel)
        self.assertIn("return ayuGramSettingsCurrent.paperclipMenu", panel)
        # A recorded draft turns the button into «delete»: no menu there.
        self.assertIn("interfaceState.mediaDraftState != nil", panel)
        interaction = read("ChatPresentationInterfaceState/Sources/ChatPanelInterfaceInteraction.swift")
        self.assertIn("public var shadowPaperclipLongPress: ((UIView) -> Void)?", interaction)
        load = read("TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift")
        self.assertIn("self?.shadowPresentPaperclipMenu(sourceView: sourceView)", load)

    def test_imitation_and_pranks(self):
        engine = read("TelegramCore/Sources/AyuGram/ShadowActivityImitation.swift")
        # Straight to the network: Ghost Mode's typing suppression does not apply.
        self.assertIn("Api.functions.messages.setTyping(", engine)
        self.assertIn("action ?? .sendMessageCancelAction", engine)
        self.assertIn("setEncryptedTyping", engine)
        self.assertNotIn("updateLocalInputActivity", engine)
        menu = read("TelegramUI/Sources/Chat/ShadowPaperclipMenu.swift")
        self.assertIn("ForwardOptionsMessageAttribute(hideNames: true, hideCaptions: false)", menu)
        self.assertIn("settings.paperclipPrankImitation", menu)
        self.assertIn("ShadowPaperclip.normalizedPrankSeconds(settings.paperclipPrankSeconds)", menu)
        self.assertIn("ShadowActivityImitation.shared.stopAll(accountPeerId: accountPeerId)", menu)
        self.assertIn("actions.filter { $0 == .imitation(.typing) }", menu)

    def test_admin_catalog(self):
        access = read("TelegramCore/Sources/AyuGram/ShadowDeviceAccess.swift")
        self.assertIn('ShadowPaperclip.parsePranks(object["paperclip_pranks"])', access)
        self.assertIn('object["paperclip_pranks"] = ShadowPaperclip.encodePranks(whitelist.paperclipPranks)', access)
        self.assertIn('"action": "save_pranks"', access)
        admin = read("SettingsUI/Sources/ShadowDeviceAccessController.swift")
        self.assertIn('"ПРИКОЛЫ СКРЕПКИ"', admin)
        self.assertIn("ShadowDeviceAccess.savePaperclipPranks(adminURL:", admin)
        # Editing the egg channels must not drop the pranks (and back).
        self.assertIn("remote.withEasterEggChannels(channels)", admin)
        self.assertIn("remote.withPaperclipPranks(pranks)", admin)
        worker = (ROOT / "tools/shadow-bot/worker.js").read_text(encoding="utf-8")
        self.assertIn('body.action === "save_pranks"', worker)
        self.assertIn("next.paperclip_pranks = pranks.slice(0, 50)", worker)

    def test_foundation_suite_runs_the_model(self):
        runner = (ROOT / "build-system/ci/test_shadow_foundation.py").read_text(encoding="utf-8")
        self.assertIn("'Tests/ShadowSettings/ActivityImitationTests.swift'", runner)
        self.assertIn("'submodules/TelegramCore/Sources/AyuGram/ShadowPaperclip.swift'", runner)


class PaperclipPranks114Contracts(unittest.TestCase):
    """1.14.0: «отправляет…» after «записывает…», own pranks, pranks as replies."""

    def test_send_seconds_setting(self):
        settings = read("TelegramCore/Sources/AyuGram/AyuGramSettings.swift")
        self.assertIn("public var paperclipPrankSendSeconds: Int32 = ShadowPaperclip.defaultPrankSendSeconds", settings)
        self.assertIn('forKey: "paperclipPrankSendSeconds")', settings)
        document = read("TelegramCore/Sources/AyuGram/ShadowSettingsDocument.swift")
        self.assertIn('key == "paperclipPrankSendSeconds" && (0...60).contains(number)', document)
        transfer = read("TelegramCore/Sources/AyuGram/ShadowSettingsTransfer.swift")
        self.assertIn('values["paperclipPrankSendSeconds"] = .integer(Int64(settings.paperclipPrankSendSeconds))', transfer)
        self.assertIn('case "paperclipPrankSendSeconds":', transfer)
        links = read("TelegramCore/Sources/AyuGram/ShadowSettingLinks.swift")
        self.assertIn('slug: "paperclip-prank-sending", entryId: 137, key: nil, title: "Секунд отправки", parentEntryId: 135, since: "1.14.0"', links)
        self.assertIn("`shadow://customization/paperclip-prank-sending`", (ROOT / "docs/shadow-links.md").read_text(encoding="utf-8"))
        self.assertIn("destination: .customization, entryId: 137,", read("SettingsUI/Sources/ShadowSettingsSearchIndex.swift"))
        screen = read("SettingsUI/Sources/AyuGramSettingsController.swift")
        self.assertIn("case .paperclipPrankSendSeconds: return 137", screen)
        self.assertIn("entries.append(.paperclipPrankSendSeconds(settings.paperclipPrankSendSeconds))", screen)

    def test_second_phase(self):
        menu = read("TelegramUI/Sources/Chat/ShadowPaperclipMenu.swift")
        self.assertIn("ShadowPaperclip.sendingMode(for: media)", menu)
        self.assertIn("ShadowPaperclip.normalizedPrankSendSeconds(settings.paperclipPrankSendSeconds)", menu)
        self.assertIn("mode: sendingMode)", menu)

    def test_own_pranks(self):
        menu = read("TelegramUI/Sources/Chat/ShadowPaperclipMenu.swift")
        self.assertIn("ShadowPaperclip.mergedPranks(user: ShadowPaperclipUserPrankStore.pranks, catalog:", menu)
        store = read("TelegramCore/Sources/AyuGram/ShadowPaperclipUserPrankStore.swift")
        self.assertIn('"shadow.paperclip.userPranks.v1"', store)
        self.assertIn("ShadowPaperclip.addingUserPrank(Self.pranks, title: title, link: link)", store)
        actions = read("SettingsUI/Sources/ShadowPaperclipActionsController.swift")
        self.assertIn('"МОИ ПРИКОЛЫ"', actions)
        self.assertIn('"Добавить прикол по ссылке"', actions)
        self.assertIn("ShadowPaperclipUserPrankStore.add(title: title, link: link)", actions)
        self.assertIn("ShadowPaperclipUserPrankStore.remove(id: prank.id)", actions)

    def test_prank_as_reply(self):
        menu = read("TelegramUI/Sources/Chat/ShadowPaperclipMenu.swift")
        self.assertIn("self.presentationInterfaceState.interfaceState.replyMessageSubject?.subjectModel", menu)
        self.assertIn("$0.withUpdatedReplyMessageSubject(nil)", menu)
        self.assertIn("shadowPrankCopy(message, threadId: threadId, replySubject: replySubject)", menu)
        self.assertIn(".message(message: MessageReference(message), media: $0)", menu)
        self.assertIn("replyToMessageId: replySubject", menu)
        # Without a reply the tested forward path stays.
        self.assertIn("ForwardOptionsMessageAttribute(hideNames: true, hideCaptions: false)", menu)


if __name__ == "__main__":
    unittest.main()

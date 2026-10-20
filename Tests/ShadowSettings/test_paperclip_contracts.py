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


if __name__ == "__main__":
    unittest.main()

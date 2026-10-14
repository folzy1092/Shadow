"""Source contracts: «Стикер из сообщения» (Quotly-like) on the screenshot renderer (1.13.0)."""
from pathlib import Path
import unittest

SUB = Path(__file__).resolve().parents[2] / "submodules"


def read(path):
    return (SUB / path).read_text(encoding="utf-8")


class MessageStickerContracts(unittest.TestCase):
    def test_menu_and_render(self):
        menus = read("TelegramUI/Sources/ChatInterfaceStateContextMenus.swift")
        self.assertIn('ContextMenuActionItem(text: "Стикер из сообщения"', menus)
        self.assertIn("presentShadowMessageSticker(ids: stickerMessageIds)", menus)
        render = read("TelegramUI/Sources/Chat/ChatControllerMessageScreenshot.swift")
        self.assertIn("self.presentShadowMessageRender(ids: Set(ids), mode: .sticker)", render)
        self.assertIn("guard mode == .sticker || settings.messageScreenshot.enabled", render)
        self.assertIn("self?.enqueueStickerImage(image, isMemoji: false)", render)
        self.assertIn("format.opaque = false", render)
        self.assertIn("shadowCroppedToVisibleContent(image, padding: 6.0)", render)
        # The sticker look is not saved into the screenshot settings.
        self.assertIn("static func stickerOptions(_ base: ShadowMessageScreenshotSettings)", render)


if __name__ == "__main__":
    unittest.main()

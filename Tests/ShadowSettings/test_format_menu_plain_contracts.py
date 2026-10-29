"""Source contracts for «Обычный» in the Format menu (2.0.0): always there, first, never disabled."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
PANEL = ROOT / "submodules/TelegramUI/Components/Chat/ChatTextInputPanelNode/Sources"


class FormatMenuPlainContracts(unittest.TestCase):
    def test_both_menus_start_with_plain(self):
        panel = (PANEL / "ChatTextInputPanelNode.swift").read_text(encoding="utf-8")
        # Legacy menu and the native editor's menu each get the item before Quote.
        self.assertEqual(panel.count("title: ShadowFormatMenu.plainTitle"), 2)
        legacy = panel[panel.index("public func chatInputTextNodeMenu"):panel.index("private func buildRichTextContextMenuElements")]
        self.assertLess(legacy.index("ShadowFormatMenu.plainTitle"), legacy.index("TextFormat_Quote"))
        self.assertIn("self?.shadowClearSelectionFormatting()", legacy)
        rich = panel[panel.index("private func buildRichTextContextMenuElements"):]
        self.assertLess(rich.index("ShadowFormatMenu.plainTitle"), rich.index("TextFormat_Quote"))
        self.assertIn("richTextInputNode?.performFormatAction(.clearFormatting)", rich)

    def test_never_disabled_and_not_a_setting(self):
        panel = (PANEL / "ChatTextInputPanelNode.swift").read_text(encoding="utf-8")
        for line in panel.splitlines():
            if "ShadowFormatMenu.plainTitle" in line:
                self.assertNotIn("attributes", line)
        index = panel.index("title: ShadowFormatMenu.plainTitle")
        self.assertNotIn("ayuGramSettings", panel[index - 200:index + 300])
        toolbar = (PANEL / "ShadowInputToolbar.swift").read_text(encoding="utf-8")
        self.assertIn('static let plainTitle = "Обычный"', toolbar)
        self.assertIn("chatTextInputClearFormattingAttributes", toolbar)


if __name__ == "__main__":
    unittest.main()

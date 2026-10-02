"""Source contracts for AyuGram-style message filters."""
from pathlib import Path
import unittest

SUB = Path(__file__).resolve().parents[2] / "submodules"


def read(path):
    return (SUB / path).read_text(encoding="utf-8")


class MessageFiltersContracts(unittest.TestCase):
    def test_edit_dialog_matches_desktop(self):
        edit = read("SettingsUI/Sources/ShadowMessageFilterEditController.swift")
        for title in ("Выражение", "Включить фильтр", "Без учёта регистра", "Обратный фильтр", "Сохранить"):
            self.assertIn(title, edit)
        self.assertIn("ShadowMessageFilter.isValid(expression:", edit)

    def test_list_has_placeholder_toggle(self):
        screen = read("SettingsUI/Sources/ShadowMessageFiltersController.swift")
        self.assertIn("Скрыто локальным фильтром", screen)
        self.assertIn("messageFilterShowPlaceholder", screen)
        self.assertIn("Добавить фильтр", screen)

    def test_history_hides_completely_when_placeholder_off(self):
        history = read("TelegramUI/Sources/ChatHistoryEntriesForView.swift")
        self.assertIn("shadowSettings.messageFilterShowPlaceholder", history)
        self.assertIn("if !shadowSettings.messageFilters.isEmpty || !shadowSettings.shadowBannedPeerIds.isEmpty {", history)

    def test_foundation_suite_compiles_filters(self):
        script = (SUB.parent / "build-system/ci/test_shadow_foundation.py").read_text(encoding="utf-8")
        self.assertIn("Tests/ShadowSettings/MessageFiltersTests.swift", script)

    def test_quick_add_entry_points(self):
        selection = read("TextSelectionNode/Sources/TextSelectionNode.swift")
        self.assertIn("public var shadowAddToFilter: ((String) -> Void)?", selection)
        self.assertIn('title: "В фильтры"', selection)
        bubble = read("TelegramUI/Components/Chat/ChatMessageTextBubbleContentNode/Sources/ChatMessageTextBubbleContentNode.swift")
        self.assertIn("shadowAddMessageFilter", bubble)
        mention = read("TelegramUI/Sources/Chat/ChatControllerOpenUsernameContextMenu.swift")
        self.assertIn('text: "В фильтры"', mention)
        self.assertIn("ShadowMessageFilter.escaped(", mention)
        chat = read("TelegramUI/Sources/ChatController.swift")
        self.assertIn("controllerInteraction.shadowAddMessageFilter = {", chat)


if __name__ == "__main__":
    unittest.main()

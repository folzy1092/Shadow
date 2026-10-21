from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
MENUS = ROOT / "submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift"


class VoiceReadDateContracts(unittest.TestCase):
    # Telegram hides "Прочитано …" on an outgoing voice message or round until
    # it is played, although the chat shows two checks. In a private chat the
    # server's read date does not depend on playing, so Shadow shows it.

    def test_private_chats_show_the_read_date_of_unplayed_voice(self):
        source = MENUS.read_text(encoding="utf-8")
        check = source.split("private func canViewReadStats(", 1)[1].split("var maxParticipantCount", 1)[0]
        self.assertIn("if (file.isVoice || file.isInstantVideo) && !(peer is TelegramUser) {", check)

    def test_the_item_says_it_was_not_played(self):
        source = MENUS.read_text(encoding="utf-8")
        self.assertIn('return isRound ? "\\nне просмотрено" : "\\nне прослушано"', source)
        self.assertIn("attribute as? ConsumableContentMessageAttribute, attribute.consumed", source)
        self.assertIn("self.textNode.maximumNumberOfLines = unplayedSuffix.isEmpty ? 1 : 2", source)
        self.assertIn("dateText + unplayedSuffix", source)


if __name__ == "__main__":
    unittest.main()

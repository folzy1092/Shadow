"""Read receipts show the time with seconds."""
from pathlib import Path
import unittest

SUB = Path(__file__).resolve().parents[2] / "submodules"


def read(path):
    return (SUB / path).read_text(encoding="utf-8")


class ReadTimeSecondsContracts(unittest.TestCase):
    def test_formatter_supports_seconds(self):
        presence = read("TelegramStringFormatting/Sources/PresenceStrings.swift")
        self.assertIn("allowYesterday: Bool = true, showSeconds: Bool = false, format: HumanReadableStringFormat? = nil", presence)
        self.assertIn("seconds: showSeconds ? timeinfo.tm_sec : nil", presence)
        date = read("TelegramStringFormatting/Sources/DateFormat.swift")
        self.assertIn("withSeconds: Bool = false", date)

    def test_private_chat_and_group_readers_use_seconds(self):
        menus = read("TelegramUI/Sources/ChatInterfaceStateContextMenus.swift")
        self.assertIn("timestamp: timestamp, alwaysShowTime: true, allowYesterday: true, showSeconds: true", menus)
        readers = read("Components/ReactionListContextMenuContent/Sources/ReactionListContextMenuContent.swift")
        self.assertIn("showSeconds: true", readers)


if __name__ == "__main__":
    unittest.main()

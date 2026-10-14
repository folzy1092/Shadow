"""Source contracts: «Перевод чатов на устройстве» (1.13.0)."""
from pathlib import Path
import unittest

SUB = Path(__file__).resolve().parents[2] / "submodules"


def read(path):
    return (SUB / path).read_text(encoding="utf-8")


class LocalTranslationContracts(unittest.TestCase):
    def test_gates_open(self):
        translate = read("TranslateUI/Sources/Translate.swift")
        self.assertIn("public func shadowLocalChatTranslation(context: AccountContext) -> Bool {", translate)
        self.assertIn("if shadowLocalChatTranslation(context: context) {\n        return true\n    }", translate)
        chat = read("TranslateUI/Sources/ChatTranslation.swift")
        self.assertIn("if shadowLocalChatTranslation(context: context) {\n            enableLocalIfPossible = true", chat)
        content = read("TelegramUI/Sources/ChatControllerContentData.swift")
        self.assertIn("|| shadowLocalChatTranslation(context: context)) && !isHidden", content)

    def test_setting(self):
        settings = read("TelegramCore/Sources/AyuGram/AyuGramSettings.swift")
        self.assertIn("public var localChatTranslation: Bool = true", settings)
        self.assertIn("settings.localChatTranslation = false", settings)
        self.assertIn('slug: "local-translation", entryId: 132, key: "localChatTranslation"', read("TelegramCore/Sources/AyuGram/ShadowSettingLinks.swift"))
        self.assertIn("case .localChatTranslation: return 132", read("SettingsUI/Sources/AyuGramSettingsController.swift"))


if __name__ == "__main__":
    unittest.main()

"""Source contracts: no raw-value Codable enum reaches Postbox's Codable adapter.

The synthesized Codable of `enum X: String/Int32, Codable` uses
singleValueContainer(), which AdaptedPostboxEncoder/Decoder trap on
(preconditionFailure). Build 34755 crashed reading a chat draft/edit state:
ChatInterfaceState -> ChatEditMessageState -> ChatTextInputState ->
ChatInputContent -> ChatInputBlock -> ChatInputMedia -> ChatInputMediaDisplayMode.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
SUB = ROOT / "submodules"

ENUM = re.compile(
    r"^\s*(?:public |internal |fileprivate |private )?enum (\w+)\s*:\s*"
    r"(?:String|Int|Int8|Int16|Int32|Int64|UInt8|UInt16|UInt32|UInt64)\s*,([^{]*)\{",
    re.M,
)


def enum_body(source, match):
    depth, index = 1, match.end()
    while depth and index < len(source):
        depth += {"{": 1, "}": -1}.get(source[index], 0)
        index += 1
    return source[match.end():index]


def raw_codable_enums_without_codec(path):
    source = path.read_text(encoding="utf-8")
    result = []
    for match in ENUM.finditer(source):
        if "Codable" not in match.group(2) and "Decodable" not in match.group(2):
            continue
        if "init(from decoder" not in enum_body(source, match):
            result.append(match.group(1))
    return result


class PostboxRawEnumContracts(unittest.TestCase):
    def test_display_mode_has_keyed_codec(self):
        model = (SUB / "TelegramCore/Sources/ChatInputContent/ChatInputContentModel.swift").read_text(encoding="utf-8")
        body = model.split("public enum ChatInputMediaDisplayMode", 1)[1].split("\n}\n", 1)[0]
        self.assertIn("init(from decoder: Decoder)", body)
        self.assertIn("decoder.container(keyedBy: CodingKeys.self)", body)
        self.assertIn("encoder.container(keyedBy: CodingKeys.self)", body)
        self.assertNotIn("singleValueContainer", body)
        media = model.split("extension ChatInputMedia: Codable", 1)[1]
        self.assertIn("(try? container.decodeIfPresent(ChatInputMediaDisplayMode.self, forKey: .displayMode)) ?? .mosaic", media)

    def test_chat_input_content_enums_are_postbox_safe(self):
        # Discriminator enums here are written as `.rawValue` and read as Int32;
        # every enum the model stores through `encode(self.x)` needs its own codec.
        model_path = SUB / "TelegramCore/Sources/ChatInputContent/ChatInputContentModel.swift"
        model = model_path.read_text(encoding="utf-8")
        for name in raw_codable_enums_without_codec(model_path):
            if name == "Kind":
                continue
            self.assertNotRegex(model, rf"\b{name}\.self\b", name)

    def test_fork_settings_enums_are_stored_as_raw_values(self):
        for path in sorted((SUB / "TelegramCore/Sources/AyuGram").glob("*.swift")):
            source = path.read_text(encoding="utf-8")
            for name in raw_codable_enums_without_codec(path):
                self.assertNotRegex(source, rf"decode(?:IfPresent)?\({name}\.self", f"{path.name}: {name}")


if __name__ == "__main__":
    unittest.main()

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
FILE_NODE = ROOT / "submodules/TelegramUI/Components/Chat/ChatMessageInteractiveFileNode/Sources/ChatMessageInteractiveFileNode.swift"
VOICE_TIME = ROOT / "submodules/TelegramCore/Sources/AyuGram/ShadowVoiceTime.swift"


def read(path):
    return path.read_text(encoding="utf-8")


class HugeVoiceDurationContracts(unittest.TestCase):
    # A voice message that claims ~115 000 hours crashed the chat while it was
    # laid out: Swift traps on Int32 overflow and on Int32(_:) of a value it
    # cannot hold (huge, infinite, NaN).

    def test_voice_time_never_overflows(self):
        source = read(VOICE_TIME)
        self.assertIn("public static func seconds(_ value: Double) -> Int32", source)
        self.assertIn("Int64(elapsed) * 100 / Int64(total)", source)
        self.assertNotIn("elapsed * 100", source.replace("`elapsed * 100`", ""))
        self.assertNotIn("Int32(max(0.0,", source)

    def test_voice_bubble_converts_lengths_safely(self):
        source = read(FILE_NODE)
        self.assertNotIn("audioDuration = Int32(duration)", source)
        self.assertNotIn("stringForDuration(Int32(", source)
        self.assertNotIn("flatMap { Int32($0) }", source)
        self.assertGreaterEqual(source.count("ShadowVoiceTime.seconds("), 5)

    def test_fork_timecodes_and_stats_convert_safely(self):
        for relative in [
            "submodules/TelegramCore/Sources/AyuGram/ShadowReplyTimecode.swift",
            "submodules/TelegramUI/Sources/Chat/ShadowReplyTimecodeSend.swift",
            "submodules/TelegramCore/Sources/AyuGram/ShadowChatStatsCollect.swift",
        ]:
            source = read(ROOT / relative)
            self.assertIn("ShadowVoiceTime.seconds(", source, relative)
        self.assertNotIn("Int32(file.duration", read(ROOT / "submodules/TelegramCore/Sources/AyuGram/ShadowChatStatsCollect.swift"))


if __name__ == "__main__":
    unittest.main()

"""Source guards; executable codec regression coverage lives in the Swift test."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class PostboxScreenshotContracts(unittest.TestCase):
    def test_settings_encode_raw_value_with_keyed_container(self):
        source = (ROOT / 'submodules/TelegramCore/Sources/AyuGram/ShadowMessageScreenshotSettings.swift').read_text()
        encode = source.split('public func encode(to encoder: Encoder) throws {', 1)[1].split('\n    }', 1)[0]
        self.assertIn('container(keyedBy: CodingKeys.self)', encode)
        self.assertIn('encode(self.background.rawValue, forKey: .background)', encode)
        self.assertNotIn('encode(self.background,', encode)
        for key in ('enabled', 'showAvatars', 'showNames', 'showBadges', 'showTime'):
            self.assertIn(f'encode(self.{key}, forKey: .{key})', encode)

    def test_real_codec_harness_is_wired_before_app_build(self):
        workflow = (ROOT / '.github/workflows/build.yml').read_text()
        self.assertLess(workflow.index('python3 build-system/ci/test_shadow_postbox.py'), workflow.index('- name: Build the App'))
        runner = (ROOT / 'build-system/ci/test_shadow_postbox.py').read_text()
        self.assertIn('submodules/Postbox/Sources/Coding.swift', runner)
        self.assertIn('submodules/Postbox/Sources/Utils', runner)
        self.assertIn('--legacy-enum-probe', runner)
        test = (ROOT / 'Tests/ShadowSettings/PostboxScreenshotEncodingTests.swift').read_text()
        self.assertIn('PostboxEncoder()', test)
        self.assertIn('AdaptedPostboxDecoder().decode', test)
        self.assertIn('encodedEntry(envelope)', test)


if __name__ == '__main__':
    unittest.main()

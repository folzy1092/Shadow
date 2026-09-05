import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('prepare_esign_ipa', ROOT / 'build-system/ci/prepare_esign_ipa.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ESignIPATests(unittest.TestCase):
    config = {'bundle_id': 'app.example.personal', 'team_id': 'TESTTEAM01', 'aps_environment': 'production'}

    def fixture(self, path, extension=False):
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr('Payload/Telegram.app/Info.plist', plistlib.dumps({
                'CFBundleIdentifier': 'original.app',
                'CFBundleExecutable': 'Telegram',
                'BGTaskSchedulerPermittedIdentifiers': ['original.app.refresh', 'original.app.upload.*', 'unrelated.task'],
            }, fmt=plistlib.FMT_BINARY))
            executable = zipfile.ZipInfo('Payload/Telegram.app/Telegram')
            executable.create_system = 3
            executable.external_attr = 0o100755 << 16
            archive.writestr(executable, b'unchanged executable')
            if extension:
                archive.writestr('Payload/Telegram.app/PlugIns/NSE.appex/Info.plist', b'extension')

    def test_identity_tasks_and_executable_are_preserved(self):
        with tempfile.TemporaryDirectory() as folder:
            source, output = Path(folder) / 'in.ipa', Path(folder) / 'out.ipa'
            self.fixture(source)
            before = source.read_bytes()
            module.prepare(source, output, self.config)
            self.assertEqual(source.read_bytes(), before)
            with zipfile.ZipFile(output) as archive:
                info = plistlib.loads(archive.read('Payload/Telegram.app/Info.plist'))
                self.assertEqual(info['CFBundleIdentifier'], 'app.example.personal')
                self.assertEqual(info['BGTaskSchedulerPermittedIdentifiers'], ['app.example.personal.refresh', 'app.example.personal.upload.*', 'unrelated.task'])
                self.assertTrue(info['ShadowRequiresESign'])
                self.assertNotIn('aps-environment', info)  # never pretend Info.plist grants APNs
                self.assertEqual(archive.read('Payload/Telegram.app/Telegram'), b'unchanged executable')
                self.assertEqual(archive.getinfo('Payload/Telegram.app/Telegram').external_attr >> 16, 0o100755)

    def test_rejects_extensions_and_does_not_create_output(self):
        with tempfile.TemporaryDirectory() as folder:
            source, output = Path(folder) / 'in.ipa', Path(folder) / 'out.ipa'
            self.fixture(source, extension=True)
            with self.assertRaises(ValueError):
                module.prepare(source, output, self.config)
            self.assertFalse(output.exists())

    def test_never_overwrites_source(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / 'in.ipa'
            self.fixture(source)
            with self.assertRaises(ValueError):
                module.prepare(source, source, self.config)

    def test_presets_roundtrip_and_private_values_are_not_stored(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'profiles.json'
            self.assertIn('Folzy', module.load_presets(path))
            profile = dict(self.config, password='must-not-save', udid='must-not-save')
            module.save_presets(path, {'Друг': profile})
            self.assertEqual(module.load_presets(path), {'Друг': self.config})
            self.assertNotIn('must-not-save', path.read_text())

    def test_invalid_presets_do_not_overwrite_existing_file(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'profiles.json'
            module.save_presets(path, {'Друг': self.config})
            previous = path.read_bytes()
            with self.assertRaises(ValueError):
                module.save_presets(path, {'': self.config})
            self.assertEqual(path.read_bytes(), previous)
            path.write_text(json.dumps({'version': 99, 'profiles': {}}))
            with self.assertRaises(ValueError):
                module.load_presets(path)

    def test_import_profile_uses_entitlements_not_profile_name(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'profile.mobileprovision'
            path.write_bytes(b'CMS fixture prefix' + plistlib.dumps({'Name': 'irrelevant', 'Entitlements': {
                'application-identifier': 'OLDPREFIX1.app.example.personal',
                'com.apple.developer.team-identifier': 'TESTTEAM01',
                'aps-environment': 'production',
            }}) + b'CMS fixture suffix')
            self.assertEqual(module.config_from_mobileprovision(path), self.config)

    def test_existing_output_is_preserved(self):
        with tempfile.TemporaryDirectory() as folder:
            source, output = Path(folder) / 'in.ipa', Path(folder) / 'out.ipa'
            self.fixture(source)
            output.write_bytes(b'keep')
            with self.assertRaises(FileExistsError):
                module.prepare(source, output, self.config)
            self.assertEqual(output.read_bytes(), b'keep')


if __name__ == '__main__':
    unittest.main()

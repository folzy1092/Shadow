import importlib.util
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "build-system" / "ci" / "allow_expired_fake_profiles.py"
spec = importlib.util.spec_from_file_location("allow_expired_fake_profiles", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class AllowExpiredFakeProfiles(unittest.TestCase):
    def test_the_vendored_plisttool_has_the_check(self):
        # The submodule may be absent in a shallow checkout; when present, the
        # pattern must still match, or CI would stop at the patch step.
        plisttool = ROOT / "build-system/bazel-rules/rules_apple/tools/plisttool/plisttool.py"
        if not plisttool.exists():
            self.skipTest("rules_apple submodule not checked out")
        text = plisttool.read_text(encoding="utf-8")
        self.assertTrue(module.CHECK in text or module.PATCHED in text)

    def test_patch_disables_only_the_expiry_check(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "plisttool.py"
            path.write_text("x = 1\n" + module.CHECK + "      raise PlistToolError()\n", encoding="utf-8")
            self.assertEqual(module.patch(path), "patched")
            text = path.read_text(encoding="utf-8")
            self.assertIn(module.PATCHED, text)
            self.assertNotIn(module.CHECK, text)
            self.assertEqual(module.patch(path), "already patched")

    def test_ci_runs_it_before_the_build(self):
        workflow = (ROOT / ".github/workflows/build.yml").read_text(encoding="utf-8")
        self.assertIn("python3 build-system/ci/allow_expired_fake_profiles.py", workflow)
        self.assertLess(workflow.index("allow_expired_fake_profiles.py"), workflow.index("build-system/Make/Make.py"))


if __name__ == "__main__":
    unittest.main()

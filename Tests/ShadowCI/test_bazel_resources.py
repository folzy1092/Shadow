import importlib.util
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    "configure_bazel", ROOT / "build-system/ci/configure_bazel.py"
)
configure = importlib.util.module_from_spec(spec)
spec.loader.exec_module(configure)


class BazelResourceTests(unittest.TestCase):
    def test_runner_sizes_leave_memory_for_compiler_and_os(self):
        for memory_mb in (4096, 7168, 8192, 14336, 16384, 32768):
            with self.subTest(memory_mb=memory_mb):
                heap, actions, jobs = configure.resource_options(memory_mb, 3)
                self.assertGreaterEqual(heap, 1536)
                self.assertLessEqual(heap, 4096)
                self.assertGreaterEqual(actions, 1024)
                self.assertEqual(heap + actions + 1024, memory_mb)
                self.assertEqual(jobs, 2)

    def test_single_cpu(self):
        self.assertEqual(configure.resource_options(7168, 1)[2], 1)

    def test_invalid_capacity_is_rejected(self):
        for memory, cpus in ((0, 3), (3072, 3), (7168, 0)):
            with self.subTest(memory=memory, cpus=cpus):
                with self.assertRaises(ValueError):
                    configure.resource_options(memory, cpus)

    def test_mac_worker_override_is_appended_in_same_scope(self):
        original = "build:macos --strategy=SwiftCompile=worker\n"
        rc = configure.configured_rc(original, 7168, 3)
        self.assertTrue(rc.startswith(original))
        self.assertIn("startup --host_jvm_args=-Xmx2304m\n", rc)
        self.assertIn("build:macos --local_resources=memory=3840\n", rc)
        strategies = [line for line in rc.splitlines()
                      if line.startswith("build:macos --strategy=SwiftCompile=")]
        self.assertEqual(strategies[-1], "build:macos --strategy=SwiftCompile=standalone")

    def test_configuration_is_idempotent(self):
        original = "build --announce_rc\n"
        rc = configure.configured_rc(original, 7168, 3)
        self.assertEqual(configure.configured_rc(rc, 7168, 3), rc)

    def test_configuration_can_change_runner_size(self):
        rc = configure.configured_rc("", 7168, 3)
        rc = configure.configured_rc(rc, 16384, 6)
        self.assertEqual(rc.count(configure.BEGIN), 1)
        self.assertIn("-Xmx4096m", rc)
        self.assertNotIn("-Xmx2304m", rc)

    def test_unrelated_rc_options_survive(self):
        original = (ROOT / ".bazelrc").read_text(encoding="utf-8")
        rc = configure.configured_rc(original, 7168, 3)
        self.assertTrue(rc.startswith(original.rstrip()))
        self.assertIn("build --//Telegram:disableExtensions", rc)

    def test_malformed_block_is_rejected(self):
        for rc in (configure.BEGIN, configure.END,
                   configure.END + "\n" + configure.BEGIN):
            with self.subTest(rc=rc):
                with self.assertRaises(ValueError):
                    configure.configured_rc(rc, 7168, 3)

    def test_workflow_keeps_main_trigger_and_separate_cache_save(self):
        workflow = (ROOT / ".github/workflows/build.yml").read_text(encoding="utf-8")
        self.assertIn("branches: [ master, main ]", workflow)
        self.assertIn("actions/cache/restore@v4", workflow)
        self.assertIn("actions/cache/save@v4", workflow)
        self.assertIn("steps.build.outcome == 'failure'", workflow)
        self.assertIn("!cancelled()", workflow)
        self.assertLess(workflow.index("configure_bazel.py --workspace"),
                        workflow.index("name: Build the App"))


if __name__ == "__main__":
    unittest.main()

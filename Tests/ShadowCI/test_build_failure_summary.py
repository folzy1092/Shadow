import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("build_failure_summary", ROOT / "build-system/ci/build_failure_summary.py")
summary = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(summary)


class BuildFailureSummaryTests(unittest.TestCase):
    def test_prefers_compiler_errors_and_strips_timestamps(self):
        log = "\n".join([
            "2026-10-01T06:37:01.0653370Z ERROR: /x/BUILD:3:14: Compiling Swift module //submodules/TelegramCore:TelegramCore failed",
            "2026-10-01T06:37:01.1302620Z submodules/TelegramCore/Sources/A.swift:656:52: error: value of type 'any Peer' has no member 'flatMap'",
            "2026-10-01T06:37:01.1302620Z submodules/TelegramCore/Sources/A.swift:656:52: error: value of type 'any Peer' has no member 'flatMap'",
            "  656 |   } else if let inputChannel = maybePeer.flatMap(apiInputChannel) {",
            "ERROR: Build did NOT complete successfully",
        ])
        self.assertEqual(
            summary.summarize(log),
            "submodules/TelegramCore/Sources/A.swift:656:52: error: value of type 'any Peer' has no member 'flatMap'",
        )

    def test_falls_back_to_bazel_errors(self):
        log = "ERROR: /x/BUILD:1:1: no such target\nERROR: Build did NOT complete successfully\n"
        self.assertEqual(summary.summarize(log), "ERROR: /x/BUILD:1:1: no such target")

    def test_limits_output(self):
        log = "\n".join(f"a.swift:{i}:1: error: {'x' * 400}" for i in range(1, 20))
        lines = summary.summarize(log).splitlines()
        self.assertEqual(len(lines), summary.MAX_LINES)
        self.assertTrue(all(len(line) <= summary.MAX_LINE_LENGTH for line in lines))

    def test_clean_log_is_empty(self):
        self.assertEqual(summary.summarize("INFO: Build completed successfully\n"), "")

    def test_workflow_reports_cancelled_and_errors(self):
        workflow = (ROOT / ".github/workflows/build.yml").read_text(encoding="utf-8")
        self.assertIn("set -o pipefail", workflow)
        self.assertIn('tee "$GITHUB_WORKSPACE/build.log"', workflow)
        self.assertEqual(workflow.count('"$JOB_STATUS" = "cancelled"'), 2)
        self.assertEqual(workflow.count("build_failure_summary.py"), 2)


if __name__ == "__main__":
    unittest.main()

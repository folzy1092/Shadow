"""The "Shadow build progress" check run that the app's update check reads."""
import importlib.util
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    "build_progress", ROOT / "build-system/ci/build_progress.py"
)
progress = importlib.util.module_from_spec(spec)
spec.loader.exec_module(progress)


class BuildProgressTests(unittest.TestCase):
    def test_latest_bazel_counter_wins(self):
        log = (
            "INFO: Analyzed target //Telegram:Telegram\n"
            "[12 / 5,876] Compiling Swift module //submodules/Display:Display\n"
            "[4,872 / 5,876] Compiling Swift module //submodules/TelegramUI:TelegramUI; 412s\n"
        )
        self.assertEqual(progress.latest_progress(log), (4872, 5876))
        self.assertIsNone(progress.latest_progress("no counter here"))
        self.assertIsNone(progress.latest_progress("[3 / 0] nonsense"))

    def test_title_and_summary_match_the_app_parser(self):
        self.assertEqual(progress.title(None), "Build the App")
        self.assertEqual(progress.title((4872, 5876)), "Build the App [4,872 / 5,876]")
        self.assertEqual(progress.summary("34757"), "build=34757")
        self.assertEqual(progress.CHECK_NAME, "Shadow build progress")
        swift = (ROOT / "submodules/TelegramCore/Sources/AyuGram/ShadowBuildStatus.swift").read_text()
        self.assertIn('progressCheckName = "Shadow build progress"', swift)
        self.assertIn('step == "Build the App"', swift)
        self.assertIn('"build="', swift)

    def test_failed_build_puts_the_errors_in_the_check_run(self):
        import tempfile
        with tempfile.NamedTemporaryFile("w", suffix=".log", delete=False) as f:
            f.write("[5,858 / 5,879] Compiling\n"
                    "2026-10-06T15:00:00.0000000Z submodules/TelegramUI/Sources/X.swift:191:26: error: 'Timer' is ambiguous for type lookup in this context\n")
            path = f.name
        text = progress.failure_text(path)
        self.assertIn("X.swift:191:26: error: 'Timer' is ambiguous", text)
        self.assertEqual(progress.failure_text("/nonexistent.log")[:12], "(no summary:")

    def test_workflow_reports_progress_without_failing_the_build(self):
        workflow = (ROOT / ".github/workflows/build.yml").read_text()
        self.assertIn("checks: write", workflow)
        self.assertIn("- name: Build the App", workflow)
        self.assertIn("GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}", workflow)
        self.assertIn("build_progress.py create", workflow)
        self.assertIn("build_progress.py watch", workflow)
        self.assertIn("trap finish_progress EXIT", workflow)
        create = workflow.index("build_progress.py create")
        self.assertLess(create, workflow.index("build-system/Make/Make.py \\\n            --bazelUserRoot"))
        self.assertIn("|| true)", workflow[create:create + 200])
        rc = (ROOT / "build-system/ci/configure_bazel.py").read_text()
        self.assertIn("--show_progress_rate_limit=", rc)

    def test_app_shows_status_on_update_check(self):
        screen = (ROOT / "submodules/SettingsUI/Sources/ShadowUpdateController.swift").read_text(encoding="utf-8")
        self.assertIn("case buildStatus(String)", screen)
        check = screen[screen.index("let check: () -> Void = {"):]
        check = check[:check.index("let startSelfUpdate")]
        self.assertIn("ShadowBuildStatus.fetch", check)


if __name__ == "__main__":
    unittest.main()

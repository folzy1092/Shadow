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
        hub = (ROOT / "submodules/SettingsUI/Sources/AyuGramSettingsController.swift").read_text()
        self.assertIn("case buildStatus(String)", hub)
        check = hub[hub.index("arguments.checkUpdates = {"):]
        check = check[:check.index("arguments.dismissUpdateBanner")]
        self.assertIn("ShadowBuildStatus.fetch", check)


if __name__ == "__main__":
    unittest.main()

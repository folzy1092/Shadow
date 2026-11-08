import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "shadow-announce.py"


class AnnounceChannels(unittest.TestCase):
    def run_script(self, root: Path, *extra: str) -> None:
        notes = root / "notes.txt"
        notes.write_text("НОВОЕ: Ответ на удалённые | Сохранение\nИСПРАВЛЕНО: Строка «удалено …» видна целиком\n", encoding="utf-8")
        subprocess.run(
            [sys.executable, "-I", str(SCRIPT), "--build", "37010", "--version", "13.2-2.3.0", "--title", "Shadow 2.3.0", "--notes", str(notes), *extra, str(root)],
            check=True, capture_output=True,
        )

    def make_repo(self, root: Path) -> None:
        (root / "shadow-update.json").write_text(json.dumps({"enabled": True, "build": 36106, "version": "13.1.2-2.2.5", "stable": {"build": 36106}}), encoding="utf-8")
        (root / "shadow-changelog.json").write_text(json.dumps({"entries": [{"build": 36106}]}), encoding="utf-8")

    def test_beta_touches_only_the_beta_object(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.make_repo(root)
            self.run_script(root, "--channel", "beta")
            update = json.loads((root / "shadow-update.json").read_text(encoding="utf-8"))
            self.assertEqual(update["beta"]["build"], 37010)
            self.assertEqual(update["beta"]["version"], "13.2-2.3.0")
            # Stable users and old builds keep the stable build.
            self.assertEqual(update["build"], 36106)
            self.assertEqual(update["stable"]["build"], 36106)
            changelog = json.loads((root / "shadow-changelog.json").read_text(encoding="utf-8"))
            self.assertEqual([entry["build"] for entry in changelog["entries"]], [36106])

    def test_stable_is_the_default(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.make_repo(root)
            self.run_script(root)
            update = json.loads((root / "shadow-update.json").read_text(encoding="utf-8"))
            self.assertEqual(update["build"], 37010)
            self.assertEqual(update["stable"]["build"], 37010)
            self.assertNotIn("beta", update)
            changelog = json.loads((root / "shadow-changelog.json").read_text(encoding="utf-8"))
            self.assertEqual(changelog["entries"][0]["build"], 37010)


if __name__ == "__main__":
    unittest.main()

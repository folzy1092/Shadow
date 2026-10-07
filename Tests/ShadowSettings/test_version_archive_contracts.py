"""Source contracts: "Архив версий" (announced builds since the device whitelist)."""
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
SUB = ROOT / "submodules"

# Runs functions of tools/shadow-bot/worker.js in node: [[name, ...args], …]
# on stdin, their results as a JSON list on stdout.
NODE_HARNESS = r"""
const fs = require("fs");
const vm = require("vm");
const source = fs.readFileSync(process.argv[1], "utf8").replace(/^export default /m, "var worker = ");
const context = vm.createContext({});
vm.runInContext(source, context);
const calls = JSON.parse(fs.readFileSync(0, "utf8"));
process.stdout.write(JSON.stringify(calls.map(([name, ...args]) => context[name](...args))));
"""


def read(path):
    return (SUB / path).read_text(encoding="utf-8")


def announce_script():
    spec = importlib.util.spec_from_file_location("shadow_announce", ROOT / "tools/shadow-announce.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class VersionArchiveContracts(unittest.TestCase):
    def test_floor_is_the_whitelist_build(self):
        update = read("TelegramCore/Sources/AyuGram/ShadowUpdateCheck.swift")
        self.assertIn("public static let minimumBuild = 34725", update)
        self.assertIn(".filter { $0.build >= minimumBuild }", update)

    def test_changelog_entries_carry_version_and_ipa(self):
        changelog = json.loads((ROOT / "shadow-changelog.json").read_text(encoding="utf-8"))
        shown = [entry for entry in changelog["entries"] if entry["build"] >= 34725]
        self.assertTrue(shown)
        for entry in shown:
            self.assertRegex(entry.get("version", ""), r"^\d+\.\d+\.\d+(-\d+\.\d+\.\d+)?$", entry["build"])
            self.assertTrue(entry.get("ipa_url", "").startswith("https://github.com/folzy1092/"), entry["build"])
            self.assertTrue(entry["ipa_url"].endswith(f"build-{entry['build']}/Shadow.ipa"), entry["build"])

    def test_screen_is_in_the_hub_and_links(self):
        screen = read("SettingsUI/Sources/ShadowUpdateController.swift")
        self.assertIn('title: "Архив версий"', screen)
        self.assertIn("entries.append(.archive)", screen)
        self.assertIn("pushControllerImpl?(shadowVersionArchiveController(context: context))", screen)
        router = read("SettingsUI/Sources/ShadowLinkRouter.swift")
        self.assertIn('case "versions", "archive":', router)
        screen = read("SettingsUI/Sources/ShadowVersionArchiveController.swift")
        self.assertIn("ShadowVersionArchive.rows(entries: entries, installedBuild: ShadowUpdateCheck.installedBuild)", screen)
        self.assertIn("ShadowVersionArchive.ipaURL(entry)", screen)

    def test_announcing_keeps_the_archive_filled(self):
        tool = (ROOT / "tools/shadow-announce.py").read_text(encoding="utf-8")
        self.assertIn('"ipa_url": IPA.format(build=args.build)', tool)
        self.assertIn('"version": args.version', tool)
        # Typed notes for the update screen.
        self.assertIn('entry["new"] = new', tool)
        self.assertIn('entry["fixed"] = fixed', tool)
        changelog = json.loads((ROOT / "shadow-changelog.json").read_text(encoding="utf-8"))
        latest = changelog["entries"][0]
        if latest["build"] >= 34777:
            self.assertTrue(latest.get("new") or latest.get("fixed"), latest["build"])
        worker = (ROOT / "tools/shadow-bot/worker.js").read_text(encoding="utf-8")
        self.assertIn('"shadow-changelog.json", changelog', worker)
        self.assertIn("version, ipa_url: ipaURL", worker)
        # The admin's "Объявить сборку" writes new / fixed too, line by line
        # (clean() of the whole text turned the line breaks into spaces), and
        # updates a build that is already there instead of skipping it.
        self.assertIn("const parsed = parseNotes(body.notes);", worker)
        self.assertNotIn("clean(body.notes", worker)
        self.assertIn("if (parsed.new.length > 0) entry.new = parsed.new;", worker)
        self.assertIn("if (parsed.fixed.length > 0) entry.fixed = parsed.fixed;", worker)
        self.assertIn("changelog.entries = mergeChangelog(changelog.entries, entry);", worker)
        self.assertIn('parsed.items.map((item) => "• " + item).join("\\n")', worker)
        admin = read("SettingsUI/Sources/ShadowDeviceAccessController.swift")
        self.assertIn('ItemListMultilineInputItem(presentationData: presentationData, text: value, placeholder: "НОВОЕ: текст | раздел"', admin)
        self.assertIn("«НОВОЕ: текст | раздел» или «ИСПРАВЛЕНО: текст»", admin)

    def test_worker_parses_notes_like_the_script(self):
        node = shutil.which("node")
        if node is None:
            self.skipTest("node is not installed")
        parse_notes = announce_script().parse_notes

        def expected(text):
            new, fixed, items = parse_notes(text)
            return {"new": new, "fixed": fixed, "items": items}

        notes = [
            "НОВОЕ: Во время обновления видно, что происходит с установкой | Shadow → Обновление Shadow\n"
            "ИСПРАВЛЕНО: Автообновление зависало на «Подтвердите установку в окне iOS»\n",
            # Untyped lines are new, labels in any case, CRLF; empty items go.
            "Компактная плитка камеры | Медиа и камера\r\n\r\n  новое: Долгое нажатие на настройку  \r\n"
            "ИСПРАВЛЕНО:   \r\nНОВОЕ: | Призрак\r\nисправлено: Строка «Собирается сборка» пропадала",
            # The old "• …" lines.
            "• Новое меню Shadow (Shadow)\n• Исправлено: вылет при сохранении черновика\n",
            # A "•" inside a typed line is text.
            "НОВОЕ: Пункт | Shadow • Обновление\nИСПРАВЛЕНО: вылет • при отправке\nНОВОЕ: а • б | в",
            "",
        ]
        # The old one-line notes ("• a • b") split at "•".
        one_line = "• Новое меню Shadow • Скрыть приветственный стикер • Исправлено: вылет"
        changelog = json.loads((ROOT / "shadow-changelog.json").read_text(encoding="utf-8"))
        typed = next(entry for entry in changelog["entries"] if entry.get("new") or entry.get("fixed"))
        typed_notes = "\n".join(
            [f"НОВОЕ: {item['text']} | {item['where']}" if item.get("where") else f"НОВОЕ: {item['text']}" for item in typed.get("new", [])]
            + [f"ИСПРАВЛЕНО: {item}" for item in typed.get("fixed", [])]
        )
        old = {"build": 34777, "date": "2026-10-06", "version": "12.9.2-1.4.0", "items": ["x"], "new": [{"text": "x"}], "fixed": ["y"]}
        other = {"build": 34765, "date": "2026-10-05", "items": ["z"]}
        again = {"build": 34777, "date": "2026-10-07", "version": "12.9.2-1.4.0", "ipa_url": "u", "items": ["Версия Shadow 1.4.0", "a"], "new": [{"text": "a"}]}
        fresh = {"build": 34781, "date": "2026-10-07", "items": ["b"]}
        # An emoji on the cut: half of it would break the app's JSON parsing.
        cut = "НОВОЕ: " + "д" * 492 + "🎉 конец"
        calls = [["parseNotes", text] for text in notes] + [
            ["parseNotes", one_line],
            ["parseNotes", cut],
            ["changelogEntry", {"build": typed["build"], "date": typed["date"], "version": typed["version"], "ipaURL": typed["ipa_url"], "title": "", "parsed": expected(typed_notes)}],
            ["changelogEntry", {"build": 5, "date": "d", "version": "", "ipaURL": "u", "title": "Заголовок", "parsed": expected("")}],
            ["mergeChangelog", [old, other], again],
            ["mergeChangelog", [old, other], fresh],
        ]
        run = subprocess.run([node, "-e", NODE_HARNESS, str(ROOT / "tools/shadow-bot/worker.js")], input=json.dumps(calls), capture_output=True, text=True, encoding="utf-8", timeout=60)
        self.assertEqual(run.returncode, 0, run.stderr)
        results = json.loads(run.stdout)
        for text, result in zip(notes, results):
            self.assertEqual(result, expected(text), text)
        self.assertEqual(results[len(notes)], expected(one_line.replace(" •", "\n•")))
        cut_result = results[len(notes) + 1]
        json.dumps(cut_result, ensure_ascii=False).encode("utf-8")
        self.assertEqual(cut_result["items"], ["д" * 492])
        entry, untitled, updated, added = results[len(notes) + 2:]
        # The entry the script wrote for the same notes.
        self.assertEqual({key: entry[key] for key in ("new", "fixed") if key in entry}, {key: typed[key] for key in ("new", "fixed") if key in typed})
        self.assertEqual(entry["items"], typed["items"])
        self.assertEqual(entry["ipa_url"], typed["ipa_url"])
        self.assertEqual(untitled, {"build": 5, "date": "d", "ipa_url": "u", "items": ["Заголовок"]})
        # Announced again: one entry, new notes, the first date, no stale fixed.
        self.assertEqual(updated, [{"build": 34777, "date": "2026-10-06", "version": "12.9.2-1.4.0", "ipa_url": "u", "items": ["Версия Shadow 1.4.0", "a"], "new": [{"text": "a"}]}, other])
        self.assertEqual(added, [fresh, old, other])


if __name__ == "__main__":
    unittest.main()

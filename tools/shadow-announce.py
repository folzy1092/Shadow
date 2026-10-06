#!/usr/bin/env python3
"""Announce a stable Shadow build: shadow-update.json + shadow-changelog.json.

    python3 tools/shadow-announce.py --build 34762 --version 12.9.2-1.2.0 \
        --title "Shadow 1.2.0: …" --notes notes.txt [--date 2026-10-06] \
        /path/to/tgfork /path/to/shadow

`notes.txt` holds one change per line, typed for the update screen
(SHADOW_AGENT_MAP §5d «Список изменений»):

    НОВОЕ: Предлагать призрак перед историями | Призрак
    ИСПРАВЛЕНО: Пасхалки больше не зависают на чёрном экране

The part after `|` is where to find a new feature. An untyped line counts as
new. `items` keeps the plain strings for older builds ("Исправлено: …" for
fixes). Both repos get the same files; commit
tgfork normally and Shadow with [skip ci]. The changelog entry carries
`version` and `ipa_url`, which "Архив версий" in the app shows (the IPA comes
from the tgfork release mirror, like shadow-update.json).
"""

import argparse
import datetime
import json
from pathlib import Path

IPA = "https://github.com/folzy1092/tgfork/releases/download/build-{build}/Shadow.ipa"
PAGE = "https://github.com/folzy1092/tgfork/releases/tag/build-{build}"


def parse_notes(text: str):
    """(new [{"text", "where"}], fixed [str], items [str]) out of notes.txt."""
    new, fixed, items = [], [], []
    for line in text.splitlines():
        line = line.strip().lstrip("•").strip()
        if not line:
            continue
        upper = line.upper()
        if upper.startswith("ИСПРАВЛЕНО:"):
            value = line.split(":", 1)[1].strip()
            if value:
                fixed.append(value)
                items.append("Исправлено: " + value[:1].lower() + value[1:])
            continue
        if upper.startswith("НОВОЕ:"):
            line = line.split(":", 1)[1].strip()
        value, _, where = line.partition("|")
        value, where = value.strip(), where.strip()
        if not value:
            continue
        new.append({"text": value, "where": where} if where else {"text": value})
        items.append(f"{value} ({where})" if where else value)
    return new, fixed, items


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--build", type=int, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--title", required=True)
    parser.add_argument("--notes", type=Path, required=True)
    parser.add_argument("--date", default=datetime.date.today().isoformat())
    parser.add_argument("roots", nargs="+", type=Path)
    args = parser.parse_args()

    new, fixed, items = parse_notes(args.notes.read_text(encoding="utf-8"))
    fork = args.version.split("-", 1)[1] if "-" in args.version else args.version
    fields = {
        "build": args.build,
        "version": args.version,
        "title": args.title,
        "notes": "\n".join("• " + item for item in items),
        "url": PAGE.format(build=args.build),
        "ipa_url": IPA.format(build=args.build),
    }
    for root in args.roots:
        path = root / "shadow-update.json"
        update = json.loads(path.read_text(encoding="utf-8"))
        update.update(fields)
        update.setdefault("stable", {}).update(fields)
        path.write_text(json.dumps(update, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

        path = root / "shadow-changelog.json"
        changelog = json.loads(path.read_text(encoding="utf-8"))
        entries = [entry for entry in changelog["entries"] if entry.get("build") != args.build]
        entry = {
            "build": args.build,
            "date": args.date,
            "version": args.version,
            "ipa_url": IPA.format(build=args.build),
            "items": [f"Версия Shadow {fork}"] + items,
        }
        if new:
            entry["new"] = new
        if fixed:
            entry["fixed"] = fixed
        entries.insert(0, entry)
        changelog["entries"] = entries
        path.write_text(json.dumps(changelog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print("announced", args.build, "in", root)


if __name__ == "__main__":
    main()

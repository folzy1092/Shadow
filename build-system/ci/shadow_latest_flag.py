#!/usr/bin/env python3
"""Print "true" or "false" for `gh release create --latest=...`.

CI builds of different commits run in parallel, so an older build can finish
after a newer one. releases/latest is what the in-app update check reads; it
must stay on the highest build number. Prints "false" when the repository
already has a release tagged build-N with N greater than this build, "true"
otherwise (also when the release list cannot be read: that is the old
behaviour, every build became latest).

Usage: shadow_latest_flag.py <owner/repo> <build number>
"""
import json
import re
import subprocess
import sys

TAG = re.compile(r"^build-(\d+)$")


def newest_build(tags):
    numbers = [int(m.group(1)) for m in (TAG.match(t) for t in tags) if m]
    return max(numbers) if numbers else None


def latest_flag(tags, build):
    newest = newest_build(tags)
    return "false" if newest is not None and newest > build else "true"


def release_tags(repo):
    out = subprocess.run(
        ["gh", "release", "list", "--repo", repo, "--limit", "30", "--json", "tagName"],
        capture_output=True, text=True, timeout=60, check=True,
    ).stdout
    return [item.get("tagName", "") for item in json.loads(out)]


def main(argv):
    if len(argv) != 3:
        print("true")
        return
    try:
        tags = release_tags(argv[1])
    except Exception as error:  # noqa: BLE001 - CI must not fail on this
        print(f"shadow_latest_flag: {error}", file=sys.stderr)
        print("true")
        return
    print(latest_flag(tags, int(argv[2])))


if __name__ == "__main__":
    main(sys.argv)

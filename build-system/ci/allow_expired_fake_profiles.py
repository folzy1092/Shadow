#!/usr/bin/env python3
"""Let rules_apple sign with the expired fake provisioning profiles.

CI signs the IPA with build-system/fake-codesigning, Telegram's verification
profiles. They expired on 2026-10-30 (upstream ships the same files), and
rules_apple's plisttool refuses an expired profile in ProcessEntitlementsFiles:

    provisioning profile ExpirationDate ("2026-10-30T17:06:30") is in the past.

Builds kept passing while that action came from the Bazel cache; once the
cache was evicted every build failed. The fake signature is never what runs on
a device: Shadow is re-signed when it is installed (ESign, the in-app updater),
so the expiry check is turned off in the checked-out rules_apple submodule.
Every other profile check (bundle id, entitlements, team) stays.

    python3 build-system/ci/allow_expired_fake_profiles.py [path/to/plisttool.py]
"""

import sys
from pathlib import Path

DEFAULT = Path(__file__).resolve().parents[1] / "bazel-rules" / "rules_apple" / "tools" / "plisttool" / "plisttool.py"
CHECK = "    if expire and expire < datetime.datetime.now():\n"
PATCHED = "    if False and expire and expire < datetime.datetime.now():  # Shadow: fake profiles are expired (allow_expired_fake_profiles.py)\n"


def patch(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    if PATCHED in text:
        return "already patched"
    if text.count(CHECK) != 1:
        raise SystemExit(f"allow_expired_fake_profiles: the expiry check in {path} changed; update this script")
    path.write_text(text.replace(CHECK, PATCHED), encoding="utf-8")
    return "patched"


if __name__ == "__main__":
    target = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT
    print("allow_expired_fake_profiles:", patch(target), target)

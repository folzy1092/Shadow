#!/usr/bin/env python3
"""Publish the CI build progress as the "Shadow build progress" check run.

The app's "Проверить обновления" reads it from the public GitHub API
(ShadowBuildStatus.swift): the title carries Bazel's latest "[done / total]"
counter, the summary carries "build=<build number>".

  create  --sha SHA --build N                 prints the check run id
  watch   --id ID --build N --log PATH        updates the title every 30 s
  finish  --id ID --build N --log PATH --status EXIT_CODE

Needs GH_TOKEN (the workflow's GITHUB_TOKEN with checks: write) and
GITHUB_REPOSITORY. Every failure is swallowed by the workflow: progress
reporting must never fail a build.
"""

import argparse
import datetime
import json
import os
import re
import sys
import time
import urllib.request

CHECK_NAME = "Shadow build progress"
STEP_TITLE = "Build the App"
PROGRESS = re.compile(r"\[\s*([0-9,]+)\s*/\s*([0-9,]+)\s*\]")
TAIL_BYTES = 256 * 1024


def latest_progress(text: str):
    """The last Bazel "[done / total]" counter in the text, as ints."""
    last = None
    for match in PROGRESS.finditer(text):
        done = int(match.group(1).replace(",", ""))
        total = int(match.group(2).replace(",", ""))
        if total > 0 and done <= total:
            last = (done, total)
    return last


def read_tail(path: str) -> str:
    try:
        with open(path, "rb") as f:
            f.seek(0, os.SEEK_END)
            size = f.tell()
            f.seek(max(0, size - TAIL_BYTES))
            return f.read().decode("utf-8", errors="replace")
    except OSError:
        return ""


def title(progress) -> str:
    if progress is None:
        return STEP_TITLE
    done, total = progress
    return f"{STEP_TITLE} [{done:,} / {total:,}]"


def summary(build: str) -> str:
    return f"build={build}"


def api(method: str, path: str, body: dict):
    request = urllib.request.Request(
        f"https://api.github.com/repos/{os.environ['GITHUB_REPOSITORY']}/{path}",
        data=json.dumps(body).encode("utf-8"),
        method=method,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {os.environ['GH_TOKEN']}",
            "Content-Type": "application/json",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.loads(response.read().decode("utf-8") or "{}")


def now() -> str:
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def create(args) -> None:
    result = api("POST", "check-runs", {
        "name": CHECK_NAME,
        "head_sha": args.sha,
        "status": "in_progress",
        "started_at": now(),
        "output": {"title": title(None), "summary": summary(args.build)},
    })
    print(result["id"])


def update(args, progress) -> None:
    api("PATCH", f"check-runs/{args.id}", {
        "output": {"title": title(progress), "summary": summary(args.build)},
    })


def watch(args) -> None:
    sent = None
    while True:
        time.sleep(30)
        progress = latest_progress(read_tail(args.log))
        if progress is not None and progress != sent:
            try:
                update(args, progress)
                sent = progress
            except Exception as error:  # keep watching
                print(f"progress update failed: {error}", file=sys.stderr)


def failure_text(log_path: str) -> str:
    """The first compiler errors (build_failure_summary.py), for the check run:
    the job log itself is not readable without a token, the check run is."""
    try:
        import importlib.util
        spec = importlib.util.spec_from_file_location(
            "build_failure_summary", os.path.join(os.path.dirname(os.path.abspath(__file__)), "build_failure_summary.py"))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with open(log_path, encoding="utf-8", errors="replace") as f:
            return module.summarize(f.read())
    except Exception as error:  # never fail the reporter
        return f"(no summary: {error})"


def finish(args) -> None:
    progress = latest_progress(read_tail(args.log))
    output = {"title": title(progress), "summary": summary(args.build)}
    if args.status != 0:
        errors = failure_text(args.log)
        if errors:
            output["text"] = errors
    api("PATCH", f"check-runs/{args.id}", {
        "status": "completed",
        "conclusion": "success" if args.status == 0 else "failure",
        "completed_at": now(),
        "output": output,
    })


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("create")
    p.add_argument("--sha", required=True)
    p.add_argument("--build", required=True)
    for name in ("watch", "finish"):
        p = sub.add_parser(name)
        p.add_argument("--id", required=True)
        p.add_argument("--build", required=True)
        p.add_argument("--log", required=True)
        if name == "finish":
            p.add_argument("--status", type=int, required=True)
    args = parser.parse_args()
    {"create": create, "watch": watch, "finish": finish}[args.command](args)


if __name__ == "__main__":
    main()

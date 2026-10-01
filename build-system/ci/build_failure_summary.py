#!/usr/bin/env python3
"""Print the first compiler errors from a Bazel/Make.py build log.

Used by the CI notification steps so a failed build message already says
what broke, instead of only linking to a 40-minute log.
"""
from pathlib import Path
import re
import sys

MAX_LINES = 5
MAX_LINE_LENGTH = 300
MAX_TOTAL = 1500

# swiftc / clang: "path/File.swift:656:52: error: message"
COMPILER_ERROR = re.compile(r"^\S+:\d+:\d+: (?:fatal )?error: ")
# Bazel: "ERROR: /path/BUILD:3:14: Compiling Swift module //x:y failed: ..."
BAZEL_ERROR = re.compile(r"^ERROR: ")
BAZEL_NOISE = ("ERROR: Build did NOT complete successfully",)
TIMESTAMP = re.compile(r"^\d{4}-\d{2}-\d{2}T\S+Z ")


def summarize(text):
    compiler, bazel = [], []
    for raw in text.splitlines():
        line = TIMESTAMP.sub("", raw).strip()
        if COMPILER_ERROR.match(line):
            if line not in compiler:
                compiler.append(line)
        elif BAZEL_ERROR.match(line) and not line.startswith(BAZEL_NOISE):
            if line not in bazel:
                bazel.append(line)
    lines = (compiler or bazel)[:MAX_LINES]
    lines = [l if len(l) <= MAX_LINE_LENGTH else l[:MAX_LINE_LENGTH - 1] + "…" for l in lines]
    return "\n".join(lines)[:MAX_TOTAL]


def main(argv):
    if len(argv) != 2:
        raise SystemExit("usage: build_failure_summary.py <build.log>")
    path = Path(argv[1])
    if not path.is_file():
        return
    summary = summarize(path.read_text(encoding="utf-8", errors="replace"))
    if summary:
        print(summary)


if __name__ == "__main__":
    main(sys.argv)

#!/usr/bin/env python3
"""Compile and run Foundation-only tests with the actual Swift compiler."""
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main():
    compiler = shutil.which('swiftc')
    if compiler is None:
        raise SystemExit('Swift compiler unavailable. Foundation tests were NOT run.')
    with tempfile.TemporaryDirectory(prefix='shadow-foundation-tests-') as directory:
        executable = Path(directory) / 'document-tests'
        subprocess.run([
            compiler, '-warnings-as-errors', '-o', str(executable),
            str(ROOT / 'submodules/TelegramCore/Sources/AyuGram/ShadowSettingsDocument.swift'),
            str(ROOT / 'Tests/ShadowSettings/DocumentTests.swift'),
        ], check=True)
        subprocess.run([str(executable)], check=True)


if __name__ == '__main__':
    main()

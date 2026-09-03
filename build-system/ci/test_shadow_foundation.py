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
    cases = [
        ('document', 'submodules/TelegramCore/Sources/AyuGram/ShadowSettingsDocument.swift', 'Tests/ShadowSettings/DocumentTests.swift'),
        ('search', 'submodules/SettingsUI/Sources/ShadowSettingsSearchIndex.swift', 'Tests/ShadowSettings/SearchTests.swift'),
        ('tab-bar-scroll', 'submodules/Display/Source/TabBarScrollState.swift', 'Tests/ShadowSettings/TabBarScrollTests.swift'),
    ]
    with tempfile.TemporaryDirectory(prefix='shadow-foundation-tests-') as directory:
        for name, source, tests in cases:
            executable = Path(directory) / (name + '-tests')
            subprocess.run([
                compiler, '-warnings-as-errors', '-o', str(executable),
                str(ROOT / source), str(ROOT / tests),
            ], check=True)
            subprocess.run([str(executable)], check=True)


if __name__ == '__main__':
    main()

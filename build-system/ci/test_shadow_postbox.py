#!/usr/bin/env python3
"""Run a focused macOS CLI test using the real Postbox codec source files."""
from pathlib import Path
import os
import signal
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main():
    if sys.platform != 'darwin':
        raise SystemExit('The real Postbox codec test requires macOS/Xcode; NOT run.')
    sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
    with tempfile.TemporaryDirectory(prefix='shadow-postbox-tests-') as directory:
        directory = Path(directory)
        headers = ROOT / 'submodules/MurMurHash32/PublicHeaders'
        module = directory / 'module.modulemap'
        header = headers / 'MurMurHash32/MurMurHash32.h'
        module.write_text('module MurMurHash32 { header "' + str(header) + '" export * }\n')
        obj = directory / 'MurMurHash32.o'
        subprocess.run([
            'xcrun', '--sdk', 'macosx', 'clang', '-fobjc-arc', '-fmodules',
            '-isysroot', sdk, '-I', str(headers), '-c',
            str(ROOT / 'submodules/MurMurHash32/Sources/MurMurHash32.m'), '-o', str(obj),
        ], check=True)
        sources = [
            ROOT / 'submodules/Postbox/Sources/Coding.swift',
            # Coding.swift calls postboxLog when decoding fails. Include the
            # production logger even though the positive tests do not log.
            ROOT / 'submodules/Postbox/Sources/PostboxLogging.swift',
            ROOT / 'submodules/Postbox/Sources/ValueBoxKey.swift',
        ]
        for kind in ('Encoder', 'Decoder'):
            sources.extend(sorted((ROOT / 'submodules/Postbox/Sources/Utils' / kind).glob('*.swift')))
        sources.extend([
            ROOT / 'submodules/TelegramCore/Sources/AyuGram/ShadowMessageScreenshotSettings.swift',
            ROOT / 'Tests/ShadowSettings/PostboxScreenshotEncodingTests.swift',
        ])
        executable = directory / 'postbox-screenshot-tests'
        subprocess.run([
            'xcrun', '--sdk', 'macosx', 'swiftc', '-sdk', sdk, '-I', str(directory),
            '-o', str(executable), *map(str, sources), str(obj),
        ], check=True)
        subprocess.run([str(executable)], check=True)
        # Verify that this harness really catches the original enum bug. Keep
        # the expected fatal error outside the positive test process.
        env = dict(os.environ, SWIFT_BACKTRACE='enable=no')
        probe = subprocess.run([str(executable), '--legacy-enum-probe'], env=env, capture_output=True, text=True)
        if probe.returncode not in (-signal.SIGILL, -signal.SIGTRAP, -signal.SIGABRT):
            raise SystemExit('Legacy enum probe did not trap as expected: ' + str(probe.returncode))
        print('Legacy raw-enum regression reproduced in isolated process')


if __name__ == '__main__':
    main()

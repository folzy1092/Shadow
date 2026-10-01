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
        ('screenshot-anonymizer', 'submodules/TelegramCore/Sources/AyuGram/ShadowScreenshotAnonymizer.swift', 'Tests/ShadowSettings/ScreenshotAnonymizerTests.swift'),
        ('saved-media-files', 'submodules/TelegramCore/Sources/AyuGram/ShadowSavedMediaFiles.swift', 'Tests/ShadowSettings/SavedMediaFilesTests.swift'),
        ('push-diagnostics', 'submodules/TelegramCore/Sources/AyuGram/ShadowPushDiagnostics.swift', 'Tests/ShadowSettings/PushDiagnosticsTests.swift'),
        ('code-signature', 'submodules/TelegramCore/Sources/AyuGram/ShadowCodeSignature.swift', 'Tests/ShadowSettings/CodeSignatureTests.swift'),
        ('own-server-presence', 'submodules/TelegramCore/Sources/AyuGram/ShadowOwnServerPresence.swift', 'Tests/ShadowSettings/OwnServerPresenceTests.swift'),
        ('screenshot-grouping', 'submodules/TelegramUI/Sources/Chat/ShadowMessageScreenshotGrouping.swift', 'Tests/ShadowSettings/ScreenshotGroupingTests.swift'),
        ('peer-name', 'submodules/TelegramCore/Sources/AyuGram/ShadowPeerName.swift', 'Tests/ShadowSettings/PeerNameTests.swift'),
        ('message-screenshot', 'submodules/TelegramCore/Sources/AyuGram/ShadowMessageScreenshotSettings.swift', 'Tests/ShadowSettings/MessageScreenshotTests.swift'),
        ('document', 'submodules/TelegramCore/Sources/AyuGram/ShadowSettingsDocument.swift', 'Tests/ShadowSettings/DocumentTests.swift'),
        ('update-check', 'submodules/TelegramCore/Sources/AyuGram/ShadowUpdateCheck.swift', 'Tests/ShadowSettings/UpdateCheckTests.swift'),
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

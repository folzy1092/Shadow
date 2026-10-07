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
        ('chat-lock', ('submodules/TelegramCore/Sources/AyuGram/ShadowChatLock.swift', 'submodules/TelegramCore/Sources/AyuGram/ShadowDisguise.swift'), 'Tests/ShadowSettings/ChatLockTests.swift'),
        ('crash-reports', 'submodules/TelegramCore/Sources/AyuGram/ShadowCrashReports.swift', 'Tests/ShadowSettings/CrashReportsTests.swift'),
        ('online-history', 'submodules/TelegramCore/Sources/AyuGram/ShadowOnlineHistory.swift', 'Tests/ShadowSettings/OnlineHistoryTests.swift'),
        ('intruder-log', ('submodules/TelegramCore/Sources/AyuGram/ShadowIntruderLog.swift', 'submodules/TelegramCore/Sources/AyuGram/ShadowDisguise.swift'), 'Tests/ShadowSettings/IntruderLogTests.swift'),
        ('disguise', 'submodules/TelegramCore/Sources/AyuGram/ShadowDisguise.swift', 'Tests/ShadowSettings/DisguiseTests.swift'),
        ('spaces', ('submodules/TelegramCore/Sources/AyuGram/ShadowSpaces.swift', 'submodules/TelegramCore/Sources/AyuGram/ShadowChatLock.swift', 'submodules/TelegramCore/Sources/AyuGram/ShadowDisguise.swift'), 'Tests/ShadowSettings/SpacesTests.swift'),
        ('duress', ('submodules/TelegramCore/Sources/AyuGram/ShadowDuress.swift', 'submodules/TelegramCore/Sources/AyuGram/ShadowSpaces.swift', 'submodules/TelegramCore/Sources/AyuGram/ShadowChatLock.swift', 'submodules/TelegramCore/Sources/AyuGram/ShadowDisguise.swift'), 'Tests/ShadowSettings/DuressTests.swift'),
        ('device-access', 'submodules/TelegramCore/Sources/AyuGram/ShadowDeviceAccess.swift', 'Tests/ShadowSettings/DeviceAccessTests.swift'),
        ('message-filters', 'submodules/TelegramCore/Sources/AyuGram/ShadowMessageFilters.swift', 'Tests/ShadowSettings/MessageFiltersTests.swift'),
        ('links', 'submodules/TelegramCore/Sources/AyuGram/ShadowLinks.swift', 'Tests/ShadowSettings/LinksTests.swift'),
        ('header-buttons', 'submodules/TelegramCore/Sources/AyuGram/ShadowHeaderButtons.swift', 'Tests/ShadowSettings/HeaderButtonsTests.swift'),
        ('setting-links', ('submodules/TelegramCore/Sources/AyuGram/ShadowSettingLinks.swift', 'submodules/TelegramCore/Sources/AyuGram/ShadowLinks.swift', 'submodules/TelegramCore/Sources/AyuGram/ShadowVoiceTime.swift'), 'Tests/ShadowSettings/SettingLinksTests.swift'),
        ('voice-time', 'submodules/TelegramCore/Sources/AyuGram/ShadowVoiceTime.swift', 'Tests/ShadowSettings/VoiceTimeTests.swift'),
        ('registration-date', 'submodules/TelegramCore/Sources/AyuGram/ShadowRegistrationDate.swift', 'Tests/ShadowSettings/RegistrationDateTests.swift'),
        ('build-status', 'submodules/TelegramCore/Sources/AyuGram/ShadowBuildStatus.swift', 'Tests/ShadowSettings/BuildStatusTests.swift'),
        ('chat-export', 'submodules/TelegramCore/Sources/AyuGram/ShadowChatExport.swift', 'Tests/ShadowSettings/ChatExportTests.swift'),
        ('search', 'submodules/SettingsUI/Sources/ShadowSettingsSearchIndex.swift', 'Tests/ShadowSettings/SearchTests.swift'),
        ('tab-bar-scroll', 'submodules/Display/Source/TabBarScrollState.swift', 'Tests/ShadowSettings/TabBarScrollTests.swift'),
        ('self-update', ('submodules/ShadowSelfUpdate/Sources/ShadowProvisioningProfile.swift', 'submodules/ShadowSelfUpdate/Sources/ShadowBundlePreparer.swift', 'submodules/ShadowSelfUpdate/Sources/ShadowLocalTLSIdentity.swift', 'submodules/ShadowSelfUpdate/Sources/ShadowInstallLinks.swift', 'submodules/ShadowSelfUpdate/Sources/ShadowInstallDiagnostics.swift'), 'Tests/ShadowSettings/SelfUpdateTests.swift'),
    ]
    with tempfile.TemporaryDirectory(prefix='shadow-foundation-tests-') as directory:
        for name, sources, tests in cases:
            if isinstance(sources, str):
                sources = (sources,)
            executable = Path(directory) / (name + '-tests')
            subprocess.run([
                compiler, '-warnings-as-errors', '-o', str(executable),
                *(str(ROOT / source) for source in sources), str(ROOT / tests),
            ], check=True)
            subprocess.run([str(executable)], check=True)


if __name__ == '__main__':
    main()

"""Source wiring checks; behavioral coverage lives in the Swift fixtures."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class PushDiagnosticsContracts(unittest.TestCase):
    def test_all_apns_registration_paths_are_observed(self):
        source = (ROOT / 'submodules/TelegramUI/Sources/AppDelegate.swift').read_text()
        self.assertEqual(source.count('UIApplication.shared.registerForRemoteNotifications()'), source.count('ShadowPushDiagnostics.shared.apnsRegistrationCalled()'))
        self.assertIn('apnsRegistrationSucceeded(token: deviceToken)', source)
        self.assertIn('apnsRegistrationFailed(error: error)', source)
        self.assertNotIn('deviceToken: \\(hexString(deviceToken))', source)

    def test_rpc_result_is_not_swallowed(self):
        source = (ROOT / 'submodules/TelegramCore/Sources/TelegramEngine/AccountData/RegisterNotificationToken.swift').read_text()
        self.assertIn('case .boolFalse: accepted = false', source)
        self.assertIn('.rpcError(code: error.errorCode, description: error.errorDescription)', source)
        self.assertNotIn('return .single(true)', source)
        self.assertNotIn('return .single(false)', source)
        shared = (ROOT / 'submodules/TelegramUI/Sources/SharedAccountContext.swift').read_text()
        self.assertIn('requiresTokenInvalidation', shared)

    def test_screen_uses_signature_not_profile(self):
        source = (ROOT / 'submodules/SettingsUI/Sources/ShadowPushDiagnosticsController.swift').read_text()
        self.assertIn('ShadowCodeSignature.entitlements(executableURL: Bundle.main.executableURL)', source)
        self.assertIn('com.apple.usernotifications.service', source)
        self.assertIn('ValuePromise<Bool>(false', source)
        self.assertNotIn('UIPasteboard', source)

    def test_state_is_not_persisted(self):
        source = (ROOT / 'submodules/TelegramCore/Sources/AyuGram/ShadowPushDiagnostics.swift').read_text()
        self.assertNotIn('UserDefaults', source)
        self.assertNotIn('.write(', source)


if __name__ == '__main__':
    unittest.main()

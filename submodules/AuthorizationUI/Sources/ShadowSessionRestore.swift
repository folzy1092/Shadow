import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import PresentationDataUtils
import LocalAuthentication

// Shadow 2.1.0: «Восстановить аккаунты (N)» on the login screen
// (docs/specs/2026-10-30-shadow-2.1.0-session-backup.md). One button brings back
// every account in the keychain backup (ShadowSessionBackup), after Face ID or
// the phone's passcode. Anything that goes wrong is shown with «Скопировать».
extension AuthorizationSequencePhoneEntryController {
    func shadowOfferSessionRestore() {
        if self.shadowDidOfferSessionRestore {
            return
        }
        self.shadowDidOfferSessionRestore = true
        let _ = (ShadowSessionBackup.restorableCount(accountManager: self.sharedContext.accountManager)
        |> deliverOnMainQueue).start(next: { [weak self] count in
            guard let self, count > 0 else {
                return
            }
            let alert = textAlertController(sharedContext: self.sharedContext, title: "Бэкап аккаунтов", text: "На этом телефоне сохранены аккаунты Shadow: \(count). Их можно вернуть без номера и кода, если сессии не завершены в «Активных сеансах».", actions: [
                TextAlertAction(type: .defaultAction, title: "Восстановить аккаунты (\(count))", action: { [weak self] in
                    self?.shadowAuthenticateAndRestore()
                }),
                TextAlertAction(type: .genericAction, title: "Не сейчас", action: {})
            ], actionLayout: .vertical)
            self.present(alert, in: .window(.root))
        })
    }

    private func shadowAuthenticateAndRestore() {
        let context = LAContext()
        var policyError: NSError?
        // A phone without a passcode has nothing to ask; the backup is as open as the phone.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            self.shadowRestoreSessions()
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Восстановить аккаунты Shadow") { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                if success {
                    self.shadowRestoreSessions()
                } else if let error = error as? LAError, error.code == .userCancel || error.code == .appCancel || error.code == .systemCancel {
                    return
                } else {
                    self.shadowShowRestoreReport(title: "Не удалось подтвердить", text: "Face ID / код телефона: \(error?.localizedDescription ?? "неизвестная ошибка")")
                }
            }
        }
    }

    private func shadowRestoreSessions() {
        let _ = (ShadowSessionBackup.restoreAll(accountManager: self.sharedContext.accountManager, switchToRestored: true)
        |> deliverOnMainQueue).start(next: { [weak self] result in
            // With accounts restored the app leaves the login screen by itself;
            // a report is shown only when something did not work.
            if result.restored.isEmpty || !result.errors.isEmpty {
                self?.shadowShowRestoreReport(title: result.restored.isEmpty ? "Аккаунты не восстановлены" : "Восстановлено не всё", text: ShadowSessionBackup.report(result))
            }
        })
    }

    private func shadowShowRestoreReport(title: String, text: String) {
        let presentationData = self.sharedContext.currentPresentationData.with { $0 }
        let alert = textAlertController(sharedContext: self.sharedContext, title: title, text: text, actions: [
            TextAlertAction(type: .genericAction, title: "Скопировать", action: {
                UIPasteboard.general.string = text
            }),
            TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})
        ])
        if let mainWindow = self.sharedContext.mainWindow {
            mainWindow.present(alert, on: .root)
        } else {
            self.present(alert, in: .window(.root))
        }
    }
}

import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import LocalAuth
import PasscodeUI

// Shadow: chat lock UI (spec docs/specs/2026-10-01-shadow-batch.md, section 5).
// State lives in ShadowChatLockStore (TelegramCore); this file owns the
// authentication flow (Face ID / Touch ID, then the device password) and the
// cover shown over a locked chat.
enum ShadowChatLockUI {
    private static var didInstallRelockObserver = false

    // Unlocked chats lock again when the app goes to background.
    static func installRelockObserverIfNeeded() {
        if self.didInstallRelockObserver {
            return
        }
        self.didInstallRelockObserver = true
        let _ = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main, using: { _ in
            ShadowChatLockStore.shared.relockAll()
        })
    }

    static func showMessage(window: Window1?, title: String, message: String? = nil) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        DispatchQueue.main.async {
            window?.presentNative(alert)
        }
    }

    // Calls `completion` with the entered text, or nil when cancelled.
    static func promptPassword(window: Window1?, title: String, message: String?, completion: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addTextField { field in
            field.isSecureTextEntry = true
            field.placeholder = "Пароль"
            field.autocorrectionType = .no
            field.autocapitalizationType = .none
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: { _ in
            completion(nil)
        }))
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { [weak alert] _ in
            completion(alert?.textFields?.first?.text ?? "")
        }))
        DispatchQueue.main.async {
            window?.presentNative(alert)
        }
    }

    // Face ID / Touch ID first; on cancel or failure, the device password.
    static func authenticate(sharedContext: SharedAccountContext, reason: String, completion: @escaping (Bool) -> Void) {
        let store = ShadowChatLockStore.shared
        let window = sharedContext.mainWindow
        let passwordFallback: () -> Void = {
            guard store.hasPassword else {
                completion(false)
                return
            }
            self.promptPassword(window: window, title: "Введите пароль", message: reason, completion: { value in
                guard let value else {
                    completion(false)
                    return
                }
                if store.verifyPassword(value) {
                    completion(true)
                } else {
                    ShadowIntruderCamera.captureIfEnabled(reason: .chatLock)
                    self.showMessage(window: window, title: "Неверный пароль")
                    completion(false)
                }
            })
        }
        if LocalAuth.biometricAuthentication != nil {
            let _ = (LocalAuth.auth(reason: reason)
            |> deliverOnMainQueue).startStandalone(next: { result, _ in
                if result {
                    completion(true)
                } else {
                    passwordFallback()
                }
            })
        } else {
            passwordFallback()
        }
    }

    // Shadow disguise (debug menu): like `authenticate`, but a device with
    // neither biometrics nor a chat-lock password has nothing to check against,
    // so the switch is allowed there.
    static func authenticateOwner(sharedContext: SharedAccountContext, reason: String, completion: @escaping (Bool) -> Void) {
        if LocalAuth.biometricAuthentication == nil && !ShadowChatLockStore.shared.hasPassword {
            completion(true)
            return
        }
        self.authenticate(sharedContext: sharedContext, reason: reason, completion: completion)
    }

    // Asks for a new password twice. Calls `completion(true)` once it is stored.
    static func createPassword(sharedContext: SharedAccountContext, completion: @escaping (Bool) -> Void) {
        let window = sharedContext.mainWindow
        self.promptPassword(window: window, title: "Придумайте пароль", message: "Он нужен, если Face ID не сработает, и для сброса замков. Минимум \(ShadowChatLockStore.minimumPasswordLength) символа.", completion: { first in
            guard let first else {
                completion(false)
                return
            }
            guard first.count >= ShadowChatLockStore.minimumPasswordLength else {
                self.showMessage(window: window, title: "Слишком короткий пароль")
                completion(false)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: {
                self.promptPassword(window: window, title: "Повторите пароль", message: nil, completion: { second in
                    guard let second else {
                        completion(false)
                        return
                    }
                    guard second == first else {
                        self.showMessage(window: window, title: "Пароли не совпадают")
                        completion(false)
                        return
                    }
                    completion(ShadowChatLockStore.shared.setPassword(first))
                })
            })
        })
    }

    // Locks a chat; the first lock creates the device password.
    static func lockChat(context: AccountContext, peerId: EnginePeer.Id, completion: @escaping (Bool) -> Void) {
        let store = ShadowChatLockStore.shared
        let apply: () -> Void = {
            store.setLocked(true, accountPeerId: context.account.peerId.toInt64(), peerId: peerId.toInt64())
            completion(true)
        }
        if store.hasPassword {
            apply()
        } else {
            self.createPassword(sharedContext: context.sharedContext, completion: { created in
                if created {
                    apply()
                } else {
                    completion(false)
                }
            })
        }
    }

    // Removing a lock requires authentication.
    static func unlockChatPermanently(context: AccountContext, peerId: EnginePeer.Id, completion: @escaping (Bool) -> Void) {
        self.authenticate(sharedContext: context.sharedContext, reason: "Снять замок с чата", completion: { success in
            if success {
                let store = ShadowChatLockStore.shared
                store.markUnlocked(accountPeerId: context.account.peerId.toInt64(), peerId: peerId.toInt64())
                store.setLocked(false, accountPeerId: context.account.peerId.toInt64(), peerId: peerId.toInt64())
            }
            completion(success)
        })
    }
}

// Opaque cover over a locked chat. The navigation bar (name, back button)
// stays above it; the input panel and pinned-message panel are hidden.
final class ShadowChatLockOverlayView: UIView {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let button = UIButton(type: .system)
    private let action: () -> Void
    var didAutoAuthenticate = false

    init(theme: PresentationTheme, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: CGRect())

        self.backgroundColor = theme.list.plainBackgroundColor

        self.iconView.image = UIImage(systemName: "lock.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 44.0, weight: .regular))
        self.iconView.tintColor = theme.list.itemSecondaryTextColor
        self.iconView.contentMode = .center
        self.addSubview(self.iconView)

        self.titleLabel.text = "Чат заблокирован"
        self.titleLabel.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        self.titleLabel.textColor = theme.list.itemPrimaryTextColor
        self.titleLabel.textAlignment = .center
        self.addSubview(self.titleLabel)

        self.button.setTitle("Разблокировать", for: .normal)
        self.button.titleLabel?.font = UIFont.systemFont(ofSize: 17.0, weight: .regular)
        self.button.tintColor = theme.list.itemAccentColor
        self.button.addTarget(self, action: #selector(self.buttonPressed), for: .touchUpInside)
        self.addSubview(self.button)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func buttonPressed() {
        self.action()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = self.bounds
        let centerY = bounds.height * 0.45
        self.iconView.frame = CGRect(x: 0.0, y: centerY - 70.0, width: bounds.width, height: 56.0)
        self.titleLabel.frame = CGRect(x: 16.0, y: centerY, width: bounds.width - 32.0, height: 24.0)
        self.button.frame = CGRect(x: 16.0, y: centerY + 36.0, width: bounds.width - 32.0, height: 44.0)
    }
}

// Observer token holder: removes the observation when the chat controller goes away.
final class ShadowChatLockObserverHolder {
    private let token: NSObjectProtocol

    init(token: NSObjectProtocol) {
        self.token = token
    }

    deinit {
        NotificationCenter.default.removeObserver(self.token)
    }
}

extension ChatControllerImpl {
    private var shadowChatLockOverlay: ShadowChatLockOverlayView? {
        return self.chatDisplayNode.contentContainerNode.contentNode.view.subviews.first(where: { $0 is ShadowChatLockOverlayView }) as? ShadowChatLockOverlayView
    }

    // Covers or uncovers the chat according to ShadowChatLockStore. Works for
    // every way of opening a chat (list, search, notification, link, preview).
    func shadowChatLockUpdate(autoAuthenticate: Bool) {
        ShadowChatLockUI.installRelockObserverIfNeeded()
        if self.shadowChatLockObserver == nil {
            let token = NotificationCenter.default.addObserver(forName: ShadowChatLockStore.didChangeNotification, object: nil, queue: .main, using: { [weak self] _ in
                self?.shadowChatLockUpdate(autoAuthenticate: false)
            })
            self.shadowChatLockObserver = ShadowChatLockObserverHolder(token: token)
        }

        guard let peerId = self.chatLocation.peerId else {
            return
        }
        let accountPeerId = self.context.account.peerId.toInt64()
        let requiresUnlock = ShadowChatLockStore.shared.requiresUnlock(accountPeerId: accountPeerId, peerId: peerId.toInt64())

        if requiresUnlock {
            let overlay: ShadowChatLockOverlayView
            if let current = self.shadowChatLockOverlay {
                overlay = current
            } else {
                overlay = ShadowChatLockOverlayView(theme: self.presentationData.theme, action: { [weak self] in
                    self?.shadowChatLockRequestUnlock()
                })
                let container = self.chatDisplayNode.contentContainerNode.contentNode.view
                overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                if let navigationView = self.navigationBar?.view, navigationView.superview === container {
                    container.insertSubview(overlay, belowSubview: navigationView)
                } else {
                    container.addSubview(overlay)
                }
                self.chatDisplayNode.view.endEditing(true)
            }
            // The first update runs from loadDisplayNode, before the first layout,
            // when the container is still empty; shadowChatLockLayout() keeps the
            // frame in sync afterwards. The history itself is hidden regardless.
            self.shadowChatLockLayout()
            self.chatDisplayNode.shadowSetChatLockContentHidden(true)
            var isPreview = false
            if case .standard(.previewing) = self.mode {
                isPreview = true
            }
            if autoAuthenticate && !isPreview && !overlay.didAutoAuthenticate {
                overlay.didAutoAuthenticate = true
                self.shadowChatLockRequestUnlock()
            }
        } else if let overlay = self.shadowChatLockOverlay {
            self.chatDisplayNode.shadowSetChatLockContentHidden(false)
            UIView.animate(withDuration: 0.2, animations: {
                overlay.alpha = 0.0
            }, completion: { _ in
                overlay.removeFromSuperview()
            })
        }
    }

    // Called from containerLayoutUpdated: the cover always fills the chat.
    func shadowChatLockLayout() {
        guard let overlay = self.shadowChatLockOverlay else {
            return
        }
        // ChatControllerNode sizes contentContainerNode to the full layout size.
        var bounds = self.chatDisplayNode.contentContainerNode.contentNode.view.bounds
        if let layout = self.validLayout {
            bounds = CGRect(origin: CGPoint(), size: layout.size)
        }
        if overlay.frame != bounds {
            overlay.frame = bounds
        }
    }

    private func shadowChatLockRequestUnlock() {
        guard let peerId = self.chatLocation.peerId else {
            return
        }
        let accountPeerId = self.context.account.peerId.toInt64()
        ShadowChatLockUI.authenticate(sharedContext: self.context.sharedContext, reason: "Разблокировать чат", completion: { [weak self] success in
            guard let self, success else {
                return
            }
            ShadowChatLockStore.shared.markUnlocked(accountPeerId: accountPeerId, peerId: peerId.toInt64())
            self.shadowChatLockUpdate(autoAuthenticate: false)
            ShadowIntruderDelivery.deliverPending(context: self.context)
        })
    }
}

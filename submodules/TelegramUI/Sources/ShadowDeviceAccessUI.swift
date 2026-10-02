import Foundation
import UIKit
import TelegramCore

// Shadow: full-screen gate for devices missing from shadow-whitelist.json
// (ShadowDeviceAccess). It lives in its own window above everything, so it
// covers the auth flow and the main UI alike without touching their
// controllers. A logged-in admin account always passes.
final class ShadowDeviceAccessGate {
    private let windowScene: UIWindowScene?
    private let adminLoggedIn: () -> Bool
    private var window: UIWindow?
    private var controller: ShadowDeviceAccessViewController?
    private var lastFetch: Date?
    private var fetching = false

    init(windowScene: UIWindowScene?, adminLoggedIn: @escaping () -> Bool) {
        self.windowScene = windowScene
        self.adminLoggedIn = adminLoggedIn
    }

    func check(force: Bool) {
        if self.adminLoggedIn() {
            self.hide()
            return
        }
        self.apply(ShadowDeviceAccess.decide(deviceId: ShadowDeviceAccess.deviceId, whitelist: ShadowDeviceAccess.cachedWhitelist), offline: false)
        if self.fetching {
            return
        }
        if !force, let lastFetch = self.lastFetch, Date().timeIntervalSince(lastFetch) < 600.0 {
            return
        }
        self.fetching = true
        ShadowDeviceAccess.refresh { [weak self] whitelist in
            guard let self else {
                return
            }
            self.fetching = false
            self.lastFetch = Date()
            if self.adminLoggedIn() {
                self.hide()
                return
            }
            if let whitelist {
                self.apply(ShadowDeviceAccess.decide(deviceId: ShadowDeviceAccess.deviceId, whitelist: whitelist), offline: false)
            } else {
                self.apply(ShadowDeviceAccess.decide(deviceId: ShadowDeviceAccess.deviceId, whitelist: ShadowDeviceAccess.cachedWhitelist), offline: true)
            }
        }
    }

    private func apply(_ decision: ShadowDeviceAccess.Decision, offline: Bool) {
        switch decision {
        case .allowed:
            self.hide()
        case .denied:
            self.show(title: "Доступ ограничен", text: "Это устройство не в списке разрешённых. Отправь ID владельцу Shadow.")
        case .unknown:
            if offline {
                self.show(title: "Нет связи", text: "Не удалось проверить доступ. Подключись к интернету и нажми «Проверить снова».")
            } else {
                self.show(title: "Проверка доступа…", text: "Секунду, проверяю, разрешено ли это устройство.")
            }
        }
    }

    private func show(title: String, text: String) {
        if let controller = self.controller {
            controller.update(title: title, text: text)
            self.window?.isHidden = false
            return
        }
        let controller = ShadowDeviceAccessViewController(retry: { [weak self] in
            self?.check(force: true)
        })
        controller.loadViewIfNeeded()
        controller.update(title: title, text: text)
        let window: UIWindow
        if let windowScene = self.windowScene {
            window = UIWindow(windowScene: windowScene)
        } else {
            window = UIWindow(frame: UIScreen.main.bounds)
        }
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 10.0)
        window.rootViewController = controller
        window.isHidden = false
        self.window = window
        self.controller = controller
    }

    private func hide() {
        self.window?.isHidden = true
        self.window = nil
        self.controller = nil
    }
}

private final class ShadowDeviceAccessViewController: UIViewController {
    private let retry: () -> Void
    private let titleLabel = UILabel()
    private let textLabel = UILabel()
    private let idLabel = UILabel()

    init(retry: @escaping () -> Void) {
        self.retry = retry
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .black

        let icon = UIImageView(image: UIImage(systemName: "lock.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 44.0, weight: .semibold)))
        icon.tintColor = .white
        icon.contentMode = .scaleAspectFit

        self.titleLabel.font = UIFont.systemFont(ofSize: 24.0, weight: .bold)
        self.titleLabel.textColor = .white
        self.titleLabel.textAlignment = .center
        self.titleLabel.numberOfLines = 0

        self.textLabel.font = UIFont.systemFont(ofSize: 16.0)
        self.textLabel.textColor = UIColor(white: 1.0, alpha: 0.6)
        self.textLabel.textAlignment = .center
        self.textLabel.numberOfLines = 0

        let idCaption = UILabel()
        idCaption.font = UIFont.systemFont(ofSize: 13.0, weight: .medium)
        idCaption.textColor = UIColor(white: 1.0, alpha: 0.5)
        idCaption.textAlignment = .center
        idCaption.text = "ID УСТРОЙСТВА"

        self.idLabel.font = UIFont.monospacedSystemFont(ofSize: 22.0, weight: .semibold)
        self.idLabel.textColor = .white
        self.idLabel.textAlignment = .center
        self.idLabel.adjustsFontSizeToFitWidth = true
        self.idLabel.minimumScaleFactor = 0.6
        self.idLabel.text = ShadowDeviceAccess.deviceId

        let copyButton = self.makeButton(title: "Скопировать ID", filled: true, action: #selector(self.copyPressed))
        let retryButton = self.makeButton(title: "Проверить снова", filled: false, action: #selector(self.retryPressed))

        let stack = UIStackView(arrangedSubviews: [icon, self.titleLabel, self.textLabel, idCaption, self.idLabel, copyButton, retryButton])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 12.0
        stack.setCustomSpacing(20.0, after: icon)
        stack.setCustomSpacing(28.0, after: self.textLabel)
        stack.setCustomSpacing(4.0, after: idCaption)
        stack.setCustomSpacing(28.0, after: self.idLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.leadingAnchor, constant: 24.0),
            stack.trailingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.trailingAnchor, constant: -24.0),
            stack.centerYAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.centerYAnchor),
            copyButton.heightAnchor.constraint(equalToConstant: 50.0),
            retryButton.heightAnchor.constraint(equalToConstant: 50.0)
        ])
    }

    func update(title: String, text: String) {
        self.titleLabel.text = title
        self.textLabel.text = text
    }

    private func makeButton(title: String, filled: Bool, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        button.layer.cornerRadius = 12.0
        button.clipsToBounds = true
        if filled {
            button.backgroundColor = .systemBlue
            button.setTitleColor(.white, for: .normal)
        } else {
            button.backgroundColor = UIColor(white: 1.0, alpha: 0.12)
            button.setTitleColor(.white, for: .normal)
        }
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    @objc private func copyPressed() {
        UIPasteboard.general.string = ShadowDeviceAccess.deviceId
        self.textLabel.text = "ID скопирован. Отправь его владельцу Shadow."
    }

    @objc private func retryPressed() {
        self.retry()
    }
}

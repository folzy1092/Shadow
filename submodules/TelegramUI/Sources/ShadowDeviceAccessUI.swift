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
    // True once this process got an answer (or a failure) from the server. Until
    // then a stale cached "denied" must not flash the gate: the device may have
    // been accepted since the cache was written.
    private var resolved = false
    // The "checking" screen waits a moment, so a fast answer never shows it.
    private var checkingWorkItem: DispatchWorkItem?
    private static let checkingDelay: TimeInterval = 1.5
    // While the gate is on screen the whitelist is re-fetched on its own, so a
    // device the owner just accepted gets in without reopening the app.
    private var recheckTimer: Timer?
    private static let recheckInterval: TimeInterval = 10.0
    // A real request at every entry; this only drops duplicate calls fired
    // within a few seconds of each other (activation + launch).
    private static let minimumFetchSpacing: TimeInterval = 4.0

    init(windowScene: UIWindowScene?, adminLoggedIn: @escaping () -> Bool) {
        self.windowScene = windowScene
        self.adminLoggedIn = adminLoggedIn
    }

    func check(force: Bool) {
        if self.adminLoggedIn() {
            self.hide()
            return
        }
        self.apply(whitelist: ShadowDeviceAccess.cachedWhitelist, offline: false, fromServer: false)
        if self.fetching {
            return
        }
        if !force, self.controller == nil, let lastFetch = self.lastFetch, Date().timeIntervalSince(lastFetch) < ShadowDeviceAccessGate.minimumFetchSpacing {
            return
        }
        self.fetching = true
        ShadowDeviceAccess.refresh { [weak self] whitelist in
            guard let self else {
                return
            }
            self.fetching = false
            self.lastFetch = Date()
            self.resolved = true
            self.cancelChecking()
            if self.adminLoggedIn() {
                self.hide()
                return
            }
            if let whitelist {
                self.apply(whitelist: whitelist, offline: false, fromServer: true)
            } else {
                self.apply(whitelist: ShadowDeviceAccess.cachedWhitelist, offline: true, fromServer: false)
            }
        }
    }

    private func cancelChecking() {
        self.checkingWorkItem?.cancel()
        self.checkingWorkItem = nil
    }

    // fromServer: `whitelist` was just fetched. A cached list is trusted for
    // "allowed" at once (no gate, not even for a frame) but for "denied" only
    // after the server has answered, or failed, in this process.
    private func apply(whitelist: ShadowDeviceAccess.Whitelist?, offline: Bool, fromServer: Bool) {
        switch ShadowDeviceAccess.decide(deviceId: ShadowDeviceAccess.deviceId, whitelist: whitelist) {
        case .allowed:
            self.cancelChecking()
            self.hide()
        case .denied:
            if !fromServer && !self.resolved {
                // Stale cache says denied; wait for the fresh answer.
                return
            }
            self.cancelChecking()
            let hasRequest = whitelist?.requestURL != nil
            self.show(title: "Доступ ограничен", text: hasRequest ? "Это устройство не в списке разрешённых. Запроси доступ — владельцу Shadow придёт уведомление." : "Это устройство не в списке разрешённых. Отправь ID владельцу Shadow.", requestURL: whitelist?.requestURL)
        case .unknown:
            if offline {
                self.cancelChecking()
                self.show(title: "Нет связи", text: "Не удалось проверить доступ. Подключись к интернету и нажми «Проверить снова».", requestURL: nil)
            } else if self.controller == nil && self.checkingWorkItem == nil {
                // First launch, no cache: show "checking" only if the answer is slow.
                let item = DispatchWorkItem { [weak self] in
                    guard let self, !self.resolved, !self.adminLoggedIn() else {
                        return
                    }
                    self.checkingWorkItem = nil
                    self.show(title: "Проверка доступа…", text: "Секунду, проверяю, разрешено ли это устройство.", requestURL: nil)
                }
                self.checkingWorkItem = item
                DispatchQueue.main.asyncAfter(deadline: .now() + ShadowDeviceAccessGate.checkingDelay, execute: item)
            }
        }
    }

    private func show(title: String, text: String, requestURL: URL?) {
        if let controller = self.controller {
            controller.update(title: title, text: text, requestURL: requestURL)
            self.window?.isHidden = false
            return
        }
        let controller = ShadowDeviceAccessViewController(retry: { [weak self] in
            self?.check(force: true)
        })
        controller.loadViewIfNeeded()
        controller.update(title: title, text: text, requestURL: requestURL)
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
        self.startRecheckTimer()
    }

    private func startRecheckTimer() {
        if self.recheckTimer != nil {
            return
        }
        let timer = Timer(timeInterval: ShadowDeviceAccessGate.recheckInterval, repeats: true) { [weak self] _ in
            self?.check(force: true)
        }
        RunLoop.main.add(timer, forMode: .common)
        self.recheckTimer = timer
    }

    private func stopRecheckTimer() {
        self.recheckTimer?.invalidate()
        self.recheckTimer = nil
    }

    private func hide() {
        self.stopRecheckTimer()
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
    // "Запросить доступ": shown only when the whitelist names a request endpoint.
    private let nameField = UITextField()
    private var requestButton: UIButton?
    private var requestURL: URL?
    private var requestSentAt: Date?
    private var centerConstraint: NSLayoutConstraint?

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

        self.nameField.font = UIFont.systemFont(ofSize: 17.0)
        self.nameField.textColor = .white
        self.nameField.attributedPlaceholder = NSAttributedString(string: "Имя или @username (необязательно)", attributes: [.foregroundColor: UIColor(white: 1.0, alpha: 0.4)])
        self.nameField.backgroundColor = UIColor(white: 1.0, alpha: 0.08)
        self.nameField.layer.cornerRadius = 12.0
        self.nameField.leftView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 14.0, height: 1.0))
        self.nameField.leftViewMode = .always
        self.nameField.autocorrectionType = .no
        self.nameField.returnKeyType = .send
        self.nameField.keyboardAppearance = .dark
        self.nameField.addTarget(self, action: #selector(self.requestPressed), for: .editingDidEndOnExit)
        self.nameField.isHidden = true

        let requestButton = self.makeButton(title: "Запросить доступ", filled: true, action: #selector(self.requestPressed))
        requestButton.isHidden = true
        self.requestButton = requestButton

        let copyButton = self.makeButton(title: "Скопировать ID", filled: false, action: #selector(self.copyPressed))
        let retryButton = self.makeButton(title: "Проверить снова", filled: false, action: #selector(self.retryPressed))

        let stack = UIStackView(arrangedSubviews: [icon, self.titleLabel, self.textLabel, idCaption, self.idLabel, self.nameField, requestButton, copyButton, retryButton])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 12.0
        stack.setCustomSpacing(20.0, after: icon)
        stack.setCustomSpacing(28.0, after: self.textLabel)
        stack.setCustomSpacing(4.0, after: idCaption)
        stack.setCustomSpacing(28.0, after: self.idLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(stack)

        let centerConstraint = stack.centerYAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.centerYAnchor)
        self.centerConstraint = centerConstraint
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.leadingAnchor, constant: 24.0),
            stack.trailingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.trailingAnchor, constant: -24.0),
            centerConstraint,
            self.nameField.heightAnchor.constraint(equalToConstant: 50.0),
            requestButton.heightAnchor.constraint(equalToConstant: 50.0),
            copyButton.heightAnchor.constraint(equalToConstant: 50.0),
            retryButton.heightAnchor.constraint(equalToConstant: 50.0)
        ])

        // Keep the name field above the keyboard; a tap outside closes it.
        NotificationCenter.default.addObserver(self, selector: #selector(self.keyboardWillChange(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        self.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.backgroundTapped)))
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func update(title: String, text: String, requestURL: URL?) {
        self.titleLabel.text = title
        // A sent request keeps its confirmation instead of the generic text.
        if self.requestSentAt == nil || requestURL == nil {
            self.textLabel.text = text
        }
        // The id may be unavailable on a background launch before the first unlock.
        let deviceId = ShadowDeviceAccess.deviceId
        self.idLabel.text = deviceId.isEmpty ? "—" : deviceId
        self.requestURL = requestURL
        let showsRequest = requestURL != nil && !deviceId.isEmpty
        self.nameField.isHidden = !showsRequest
        self.requestButton?.isHidden = !showsRequest
    }

    @objc private func keyboardWillChange(_ notification: Notification) {
        guard let frame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else {
            return
        }
        let overlap = max(0.0, self.view.bounds.maxY - self.view.convert(frame, from: nil).minY)
        self.centerConstraint?.constant = -overlap * 0.5
        UIView.animate(withDuration: 0.25, animations: {
            self.view.layoutIfNeeded()
        })
    }

    @objc private func backgroundTapped() {
        self.view.endEditing(true)
    }

    @objc private func requestPressed() {
        self.view.endEditing(true)
        guard let requestURL = self.requestURL, let button = self.requestButton, button.isEnabled else {
            return
        }
        // One request a minute is plenty; the worker throttles too.
        if let sentAt = self.requestSentAt, Date().timeIntervalSince(sentAt) < 60.0 {
            return
        }
        let deviceId = ShadowDeviceAccess.deviceId
        if deviceId.isEmpty {
            return
        }
        var systemInfo = utsname()
        uname(&systemInfo)
        let model = withUnsafeBytes(of: &systemInfo.machine) { buffer -> String in
            return String(decoding: buffer.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        let build = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "?"
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = ShadowDeviceAccess.accessRequestBody(deviceId: deviceId, name: self.nameField.text ?? "", model: model, system: "iOS \(UIDevice.current.systemVersion)", build: build)

        button.isEnabled = false
        button.setTitle("Отправляю…", for: .normal)
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            DispatchQueue.main.async {
                guard let self, let button = self.requestButton else {
                    return
                }
                if error == nil, (200 ..< 300).contains(status) {
                    self.requestSentAt = Date()
                    button.setTitle("Запрос отправлен", for: .normal)
                    self.textLabel.text = "Запрос отправлен владельцу. Когда он добавит устройство, нажми «Проверить снова»."
                    DispatchQueue.main.asyncAfter(deadline: .now() + 60.0) { [weak self] in
                        self?.requestButton?.isEnabled = true
                        self?.requestButton?.setTitle("Запросить доступ", for: .normal)
                    }
                } else {
                    button.isEnabled = true
                    button.setTitle("Запросить доступ", for: .normal)
                    self.textLabel.text = status == 429 ? "Запрос уже отправлен недавно. Подожди немного." : "Не удалось отправить запрос. Проверь интернет и попробуй ещё раз."
                }
            }
        }.resume()
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

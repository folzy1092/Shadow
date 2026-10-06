import Foundation
import UIKit
import UniformTypeIdentifiers
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import AccountContext
import ShadowSelfUpdate

// Shadow: "Автообновление" — the .p12 + .mobileprovision pair that signs
// updates on this device (ShadowSigningStore). With both chosen, "Обновить"
// appears next to "Скачать IPA" in the Shadow hub (ShadowSelfUpdater).
// Device-level: not per account, not in settings backups, not synced.

private enum ShadowAutoUpdateSection: Int32 {
    case files
    case info
    case actions
}

private enum ShadowAutoUpdateEntry: ItemListNodeEntry {
    case certificate(String)
    case profile(String)
    case password(String)
    case filesFooter
    case profileInfo(String)
    case check(Bool)
    case checkStatus(String)
    case remove(Bool)

    var section: ItemListSectionId {
        switch self {
        case .certificate, .profile, .password, .filesFooter:
            return ShadowAutoUpdateSection.files.rawValue
        case .profileInfo:
            return ShadowAutoUpdateSection.info.rawValue
        case .check, .checkStatus, .remove:
            return ShadowAutoUpdateSection.actions.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .certificate: return 0
        case .profile: return 1
        case .password: return 2
        case .filesFooter: return 3
        case .profileInfo: return 4
        case .check: return 5
        case .checkStatus: return 6
        case .remove: return 7
        }
    }

    static func <(lhs: ShadowAutoUpdateEntry, rhs: ShadowAutoUpdateEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let coordinator = arguments as! ShadowAutoUpdateCoordinator
        switch self {
        case let .certificate(label):
            return ItemListDisclosureItem(presentationData: presentationData, title: "Сертификат (.p12)", label: label, sectionId: self.section, style: .blocks, action: {
                coordinator.pick(.certificate)
            })
        case let .profile(label):
            return ItemListDisclosureItem(presentationData: presentationData, title: "Профиль (.mobileprovision)", label: label, sectionId: self.section, style: .blocks, action: {
                coordinator.pick(.profile)
            })
        case let .password(label):
            return ItemListDisclosureItem(presentationData: presentationData, title: "Пароль от .p12", label: label, sectionId: self.section, style: .blocks, action: {
                coordinator.editPassword()
            })
        case .filesFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Тот же сертификат и профиль, которыми подписан установленный Shadow (например, в ESign). Файлы хранятся только на этом устройстве, пароль — в Keychain; в резервную копию настроек они не попадают."), sectionId: self.section)
        case let .profileInfo(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .check(enabled):
            return ItemListActionItem(presentationData: presentationData, title: "Проверить сертификат", kind: enabled ? .generic : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                if enabled {
                    coordinator.check()
                }
            })
        case let .checkStatus(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .remove(enabled):
            return ItemListActionItem(presentationData: presentationData, title: "Удалить сертификат и профиль", kind: enabled ? .destructive : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                if enabled {
                    coordinator.confirmRemove()
                }
            })
        }
    }
}

private final class ShadowAutoUpdateCoordinator: NSObject, UIDocumentPickerDelegate {
    enum PickKind {
        case certificate
        case profile
    }

    weak var controller: ViewController?
    let revision = ValuePromise<Int>(0, ignoreRepeated: false)
    let checkStatus = ValuePromise<String?>(nil, ignoreRepeated: true)
    let checking = ValuePromise<Bool>(false, ignoreRepeated: true)
    private var revisionValue = 0
    private var pickKind: PickKind = .certificate
    private var observer: NSObjectProtocol?

    override init() {
        super.init()
        self.observer = NotificationCenter.default.addObserver(forName: ShadowSigningStore.didChangeNotification, object: nil, queue: .main, using: { [weak self] _ in
            self?.bump()
        })
    }

    deinit {
        if let observer = self.observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func bump() {
        self.revisionValue += 1
        self.revision.set(self.revisionValue)
    }

    private func present(_ controller: UIViewController) {
        guard let owner = self.controller, owner.isViewLoaded, let window = owner.view.window,
              var presenter = window.rootViewController else { return }
        while let next = presenter.presentedViewController { presenter = next }
        guard !presenter.isBeingDismissed else { return }
        if let popover = controller.popoverPresentationController {
            popover.sourceView = owner.view
            popover.sourceRect = CGRect(x: owner.view.bounds.midX, y: owner.view.bounds.midY, width: 1.0, height: 1.0)
            popover.permittedArrowDirections = []
        }
        presenter.present(controller, animated: true)
    }

    private func message(_ text: String) {
        let alert = UIAlertController(title: "Автообновление", message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "ОК", style: .default))
        self.present(alert)
    }

    func pick(_ kind: PickKind) {
        self.pickKind = kind
        let picker: UIDocumentPickerViewController
        if #available(iOS 14.0, *) {
            // .mobileprovision has no system type; validate after picking.
            picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: true)
        } else {
            picker = UIDocumentPickerViewController(documentTypes: ["public.data"], in: .import)
        }
        picker.allowsMultipleSelection = false
        picker.delegate = self
        self.present(picker)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else {
            return
        }
        let kind = self.pickKind
        controller.dismiss(animated: true) { [weak self] in
            DispatchQueue.global(qos: .userInitiated).async {
                var failure: String?
                do {
                    switch kind {
                    case .certificate:
                        try ShadowSigningStore.shared.importCertificate(from: url)
                    case .profile:
                        try ShadowSigningStore.shared.importProfile(from: url)
                    }
                } catch {
                    failure = error.localizedDescription
                }
                DispatchQueue.main.async {
                    guard let self else {
                        return
                    }
                    self.checkStatus.set(nil)
                    if let failure {
                        self.message(failure)
                    } else if ShadowSigningStore.shared.isConfigured {
                        self.check()
                    }
                }
            }
        }
    }

    func editPassword() {
        let alert = UIAlertController(title: "Пароль от .p12", message: "Пароль, с которым экспортирован сертификат. Если пароля нет — оставьте поле пустым.", preferredStyle: .alert)
        alert.addTextField { field in
            field.isSecureTextEntry = true
            field.placeholder = "Пароль"
            field.textContentType = .password
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Сохранить", style: .default, handler: { [weak self, weak alert] _ in
            ShadowSigningStore.shared.password = alert?.textFields?.first?.text ?? ""
            self?.checkStatus.set(nil)
            if ShadowSigningStore.shared.isConfigured {
                self?.check()
            }
        }))
        self.present(alert)
    }

    func check() {
        self.checking.set(true)
        self.checkStatus.set("Проверяю…")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let error = ShadowSigningStore.shared.check()
            DispatchQueue.main.async {
                self?.checking.set(false)
                self?.checkStatus.set(error.map { "✕ " + $0 } ?? "✓ Сертификат открывается и входит в профиль — можно обновляться.")
            }
        }
    }

    func confirmRemove() {
        let alert = UIAlertController(title: "Удалить сертификат и профиль?", message: "Автообновление выключится до выбора новой пары.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Удалить", style: .destructive, handler: { [weak self] _ in
            ShadowSigningStore.shared.removeAll()
            self?.checkStatus.set(nil)
        }))
        self.present(alert)
    }
}

private let shadowAutoUpdateDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ru_RU")
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
}()

private func shadowAutoUpdateProfileText(_ profile: ShadowProvisioningProfile?) -> String {
    let installedId = Bundle.main.bundleIdentifier ?? "?"
    guard let profile else {
        return "Shadow установлен как \(installedId). Обновление подписывается с тем же bundle ID, поэтому заменяет установленную копию и сохраняет вход."
    }
    var lines: [String] = []
    lines.append("Профиль: " + (profile.name.isEmpty ? "без имени" : profile.name))
    lines.append("Команда: " + (profile.teamName.isEmpty ? profile.teamId : "\(profile.teamName) (\(profile.teamId))"))
    lines.append("App ID: \(profile.bundleIdPattern)")
    if let expiration = profile.expirationDate {
        lines.append((profile.isExpired() ? "Истёк " : "Действует до ") + shadowAutoUpdateDateFormatter.string(from: expiration))
    }
    lines.append(profile.provisionsAllDevices ? "Устройства: все" : "Устройств в профиле: \(profile.deviceCount)")
    if let aps = profile.apsEnvironment {
        lines.append("Push: \(aps)")
    }
    lines.append("")
    lines.append("Shadow установлен как \(installedId) — обновление подпишется с этим же bundle ID.")
    return lines.joined(separator: "\n")
}

func shadowAutoUpdateController(context: AccountContext, focus: ShadowSettingsSearchItem? = nil) -> ViewController {
    var focusedIndex: Int?
    let coordinator = ShadowAutoUpdateCoordinator()
    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, coordinator.revision.get(), coordinator.checkStatus.get(), coordinator.checking.get())
    |> map { presentationData, _, checkStatus, checking -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let store = ShadowSigningStore.shared
        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(presentationData: data, title: .text("Автообновление"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        var entries: [ShadowAutoUpdateEntry] = [
            .certificate(store.hasCertificate ? "Выбран" : "Не выбран"),
            .profile(store.hasProfile ? "Выбран" : "Не выбран"),
            .password(store.hasPassword ? "Задан" : "Не задан"),
            .filesFooter,
            .profileInfo(shadowAutoUpdateProfileText(store.profile)),
            .check(store.isConfigured && !checking)
        ]
        if let checkStatus {
            entries.append(.checkStatus(checkStatus))
        }
        entries.append(.remove(store.hasCertificate || store.hasProfile || store.hasPassword))
        focusedIndex = shadowSettingsFocusIndex(stableIds: entries.map { $0.stableId }, target: focus)
        return (state, (ItemListNodeState(presentationData: data, entries: entries, style: .blocks, initialScrollToItem: shadowSettingsInitialScroll(index: focusedIndex), animateChanges: true), coordinator))
    }
    let controller = ItemListController(context: context, state: signal)
    coordinator.controller = controller
    if focus != nil {
        shadowSettingsInstallFocus(controller: controller, index: { focusedIndex }, color: shadowSettingsPulseColor(context.sharedContext.currentPresentationData.with { $0 }.theme))
    }
    return controller
}

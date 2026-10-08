import Foundation
import UIKit
import UniformTypeIdentifiers
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext
import AlertUI
import PresentationDataUtils

private enum ShadowBackupEntry: ItemListNodeEntry {
    case export(Bool)
    case `import`(Bool)
    case restore(Bool)
    case info

    var section: ItemListSectionId { return 0 }
    var stableId: Int32 {
        switch self {
        case .export: return 0
        case .import: return 1
        case .restore: return 2
        case .info: return 3
        }
    }
    static func < (lhs: Self, rhs: Self) -> Bool { return lhs.stableId < rhs.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let coordinator = arguments as! ShadowSettingsBackupCoordinator
        let title: String
        let enabled: Bool
        let action: () -> Void
        switch self {
        case let .export(value):
            title = "Экспортировать настройки"; enabled = value; action = { coordinator.exportSettings() }
        case let .import(value):
            title = "Импортировать настройки"; enabled = value; action = { coordinator.selectFile() }
        case let .restore(value):
            title = "Отменить последний импорт"; enabled = value; action = { coordinator.confirmRestore() }
        case .info:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Переносятся все настройки Shadow текущего аккаунта: тумблеры, фильтры и теневой бан, шаблоны ответов, кнопки шапки, правила призрака для чатов, подмена профиля. Не попадают: сессии и коды (замки чатов, второе пространство, экстренная защита), картинки баннера и фона, история сообщений. Файл .shadow-settings можно отправить другу: у него в чате он откроется сразу с предпросмотром. Перед импортом сохраняется одна резервная копия для отмены. Настройки, которых нет в файле, не меняются."), sectionId: self.section)
        }
        return ItemListActionItem(presentationData: presentationData, title: title, kind: enabled ? .generic : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: {
            if enabled { action() }
        })
    }
}

private final class ShadowSettingsBackupCoordinator: NSObject, UIDocumentPickerDelegate {
    let context: AccountContext
    weak var controller: ViewController?
    let busy = ValuePromise<Bool>(false, ignoreRepeated: true)
    private var isBusy = false
    private let disposable = MetaDisposable()

    init(context: AccountContext) { self.context = context }
    deinit { self.disposable.dispose() }

    private func setBusy(_ value: Bool) {
        self.isBusy = value
        self.busy.set(value)
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
        let alert = UIAlertController(title: "Настройки Shadow", message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "ОК", style: .default))
        self.present(alert)
    }

    func exportSettings() {
        guard !self.isBusy else { return }
        self.setBusy(true)
        self.disposable.set((ayuGramSettings(postbox: self.context.account.postbox)
        |> take(1)
        |> deliverOnMainQueue).start(next: { [weak self] settings in
            guard let self else { return }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("shadow-export-" + UUID().uuidString, isDirectory: true)
                do {
                    let data = try ShadowSettingsTransfer.document(from: settings).encoded()
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: nil)
                    let file = directory.appendingPathComponent(ShadowSettingsFile.exportFileName)
                    try data.write(to: file, options: .atomic)
                    DispatchQueue.main.async { [weak self] in
                        self?.setBusy(false)
                        guard let self, self.controller?.viewIfLoaded?.window != nil else {
                            try? FileManager.default.removeItem(at: directory)
                            return
                        }
                        let share = UIActivityViewController(activityItems: [file], applicationActivities: nil)
                        share.completionWithItemsHandler = { _, _, _, _ in
                            // Only the UUID directory created for this export.
                            try? FileManager.default.removeItem(at: directory)
                        }
                        self.present(share)
                    }
                } catch {
                    try? FileManager.default.removeItem(at: directory)
                    DispatchQueue.main.async { [weak self] in
                        self?.setBusy(false)
                        self?.message(error.localizedDescription)
                    }
                }
            }
        }))
    }

    func selectFile() {
        guard !self.isBusy else { return }
        let picker: UIDocumentPickerViewController
        if #available(iOS 14.0, *) {
            // The own type and older *.shadow-settings.json exports.
            picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType(exportedAs: ShadowSettingsFile.typeIdentifier, conformingTo: .json), .json], asCopy: true)
        } else {
            picker = UIDocumentPickerViewController(documentTypes: [ShadowSettingsFile.typeIdentifier, "public.json"], in: .import)
        }
        picker.allowsMultipleSelection = false
        picker.delegate = self
        self.present(picker)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first, !self.isBusy else { return }
        self.setBusy(true)
        // Wait until the picker leaves the presentation stack before preview.
        controller.dismiss(animated: true) { [weak self] in self?.readFile(url) }
    }

    // A file opened from the share sheet, AirDrop, Files or a chat
    // (shadowPresentIncomingSettingsFile): the same read and preview as the
    // import button; the temporary copy goes away afterwards.
    func openIncoming(_ url: URL) {
        guard !self.isBusy else {
            ShadowSettingsFile.discard(url)
            self.message("Дождитесь окончания текущего импорта.")
            return
        }
        self.setBusy(true)
        self.readFile(url, discardAfterRead: true)
    }

    private func readFile(_ url: URL, discardAfterRead: Bool = false) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            var result: Result<ShadowSettingsDocument, Error>?
            var coordinationError: NSError?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { fileURL in
                result = Result {
                    let file = try FileHandle(forReadingFrom: fileURL)
                    defer { file.closeFile() }
                    // Bounded read: do not load an arbitrary document into RAM.
                    return try ShadowSettingsDocument.decode(file.readData(ofLength: ShadowSettingsDocument.maximumBytes + 1))
                }
            }
            let finalResult = result ?? .failure(coordinationError ?? NSError(domain: "ShadowSettings", code: 1, userInfo: [NSLocalizedDescriptionKey: "Не удалось прочитать файл."]))
            if discardAfterRead {
                ShadowSettingsFile.discard(url)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.setBusy(false)
                switch finalResult {
                case let .success(document): self.preview(document)
                case let .failure(error): self.message(error.localizedDescription)
                }
            }
        }
    }

    private func preview(_ document: ShadowSettingsDocument) {
        let context = self.context
        let accountName: Signal<String, NoError> = context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: context.account.peerId))
        |> map { peer -> String in
            guard let peer else {
                return ""
            }
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            return peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
        }
        self.disposable.set((combineLatest(ayuGramSettings(postbox: self.context.account.postbox) |> take(1), accountName)
        |> deliverOnMainQueue).start(next: { [weak self] current, accountName in
            guard let self else { return }
            do {
                let changed = try ShadowSettingsTransfer.changedKeys(document, from: current)
                let updated = ShadowSettingsTransfer.applying(document, to: current)
                if changed.isEmpty { self.message("Настройки из файла уже применены."); return }
                let ghost = updated.ghostMode ? "включён" : "выключен"
                let sections = Set(changed.map { key -> String in
                    if ["ghostMode", "hideOnlineStatus", "hideTyping", "hideReadReceipts", "hideStoryViews", "sendViaScheduled", "sendWithoutOnline", "chatPrivacyRules", "ghostAccountMode"].contains(key) { return "Приватность" }
                    if ["messageFilters", "shadowBannedPeerIds", "messageFilterShowPlaceholder"].contains(key) || key.hasPrefix("adFilter") || key == "adHideCompletely" { return "Фильтры" }
                    if key.hasPrefix("spoofProfile") || key.hasPrefix("customBanner") || key.hasPrefix("customProfileBackground") { return "Профиль" }
                    if key.hasPrefix("feed") { return "Лента" }
                    if key.hasPrefix("keep") || key.hasPrefix("save") || key.hasPrefix("mediaAutoClean") || key == "showEditComparisonAction" || key == "attachmentSizeLimit" || key == "allowSaveRestrictedContent" || key == "askBeforeStoryView" { return "Архив и медиа" }
                    return "Интерфейс"
                }).sorted().joined(separator: ", ")
                let accountLine = accountName.isEmpty ? "" : "Аккаунт: \(accountName)\n"
                let alert = UIAlertController(title: "Импорт в текущий аккаунт", message: "\(accountLine)Формат: \(document.version)\nИзменений: \(changed.count)\nРазделы: \(sections)\n\nПосле импорта режим призрака: \(ghost).\nТекущие настройки будут сохранены для отмены.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
                alert.addAction(UIAlertAction(title: "Импортировать", style: .default, handler: { [weak self] _ in
                    self?.apply(document, expected: current)
                }))
                self.present(alert)
            } catch { self.message(error.localizedDescription) }
        }))
    }

    private func apply(_ document: ShadowSettingsDocument, expected: AyuGramSettings) {
        guard !self.isBusy else { return }
        self.setBusy(true)
        self.disposable.set((importShadowSettings(postbox: self.context.account.postbox, document: document, expected: expected)
        |> deliverOnMainQueue).start(next: { [weak self] result in
            guard let self else { return }
            self.setBusy(false)
            switch result {
            case .applied: self.message("Настройки импортированы. Последний импорт можно отменить на этом экране.")
            case .unchanged: self.message("Настройки уже совпадают.")
            case .settingsChanged: self.message("Настройки изменились после предпросмотра. Выберите файл ещё раз, чтобы проверить актуальные изменения.")
            case .noBackup: break
            }
        }))
    }

    func confirmRestore() {
        guard !self.isBusy else { return }
        let alert = UIAlertController(title: "Отменить импорт?", message: "Вернутся настройки текущего аккаунта перед последним импортом. Все изменения настроек, сделанные после него, будут отменены.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Восстановить", style: .destructive, handler: { [weak self] _ in
            guard let self, !self.isBusy else { return }
            self.setBusy(true)
            self.disposable.set((restoreShadowSettingsBackup(postbox: self.context.account.postbox)
            |> deliverOnMainQueue).start(next: { [weak self] result in
                self?.setBusy(false)
                if case .noBackup = result { self?.message("Резервная копия не найдена.") }
                else { self?.message("Предыдущие настройки восстановлены.") }
            }))
        }))
        self.present(alert)
    }
}

func shadowSettingsBackupController(context: AccountContext, focus: ShadowSettingsSearchItem? = nil, incomingFile: URL? = nil) -> ViewController {
    var focusedIndex: Int?
    let coordinator = ShadowSettingsBackupCoordinator(context: context)
    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, shadowSettingsBackupAvailable(postbox: context.account.postbox), coordinator.busy.get())
    |> map { presentationData, hasBackup, busy -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(presentationData: data, title: .text("Резервная копия настроек"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let entries: [ShadowBackupEntry] = [.export(!busy), .import(!busy), .restore(hasBackup && !busy), .info]
        focusedIndex = shadowSettingsFocusIndex(stableIds: entries.map { $0.stableId }, target: focus)
        return (state, (ItemListNodeState(presentationData: data, entries: entries, style: .blocks, initialScrollToItem: shadowSettingsInitialScroll(index: focusedIndex), animateChanges: true), coordinator))
    }
    let controller = ItemListController(context: context, state: signal)
    coordinator.controller = controller
    if let incomingFile {
        var pending: URL? = incomingFile
        controller.didAppear = { [weak coordinator] _ in
            guard let file = pending else {
                return
            }
            pending = nil
            coordinator?.openIncoming(file)
        }
    }
    shadowSettingsBackupScreens.add(controller)
    if focus != nil {
        shadowSettingsInstallFocus(controller: controller, index: { focusedIndex }, color: shadowSettingsPulseColor(context.sharedContext.currentPresentationData.with { $0 }.theme))
    }
    return controller
}

// Open backup screens (weak), so a second file does not open a second screen.
let shadowSettingsBackupScreens = NSHashTable<ViewController>.weakObjects()

// Shadow (1.9.1): a settings file opened from the share sheet, AirDrop, Files
// or tapped in a chat — the backup screen with the import preview. Nothing
// is applied without «Импортировать». In the disguise / duress session the
// file is dropped silently.
public func shadowPresentIncomingSettingsFile(context: AccountContext, navigationController: NavigationController, file: URL) {
    if ShadowDisguise.shared.hidesSettings {
        ShadowSettingsFile.discard(file)
        return
    }
    if !shadowSettingsBackupScreens.allObjects.isEmpty, let screen = shadowSettingsBackupScreens.allObjects.last, screen.view.window != nil {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        ShadowSettingsFile.discard(file)
        screen.present(textAlertController(context: context, title: "Настройки Shadow", text: "Экран импорта уже открыт. Дождитесь окончания текущего импорта и откройте файл ещё раз.", actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), in: .window(.root))
        return
    }
    navigationController.pushViewController(shadowSettingsBackupController(context: context, incomingFile: file))
}

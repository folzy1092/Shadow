import Foundation
import UIKit
import SafariServices
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext
import ShadowSelfUpdate

// Shadow: "Обновление" — opened from the "Обновление Shadow" row at the top of
// the hub (and shadow://updates). Checks on open; shows current → new version,
// how many features / fixes / releases, the main button (with a signing pair:
// download + sign + install; without: the IPA link), progress of an on-device
// update, the update settings (certificate, beta, archive) and the changes of
// every skipped build, typed НОВОЕ / ИСПРАВЛЕНО when the changelog has it.
// While the update installs, a diagnostics line is under the status.

enum ShadowHubSelfUpdateAction: Int32 {
    // Raw values follow the display order (stable ids of the rows).
    case showPrompt = 0
    case retry = 1
    case share = 2
    case cancel = 3

    var title: String {
        switch self {
        case .showPrompt: return "Показать окно установки"
        case .share: return "Поделиться подписанным IPA"
        case .retry: return "Повторить"
        case .cancel: return "Отменить"
        }
    }

    var style: ShadowBigButtonItem.Style {
        switch self {
        case .showPrompt, .retry: return .filled
        case .share: return .plain
        case .cancel: return .destructive
        }
    }
}

enum ShadowHubUpdateState: Equatable {
    case idle
    case checking
    case result(ShadowUpdateCheck.Status)
}

private func shadowMegabytes(_ bytes: Int64) -> String {
    return String(format: "%.1f МБ", Double(bytes) / (1024.0 * 1024.0))
}

private func shadowPercent(_ fraction: Double) -> String {
    return "\(Int((max(0.0, min(1.0, fraction)) * 100.0).rounded(.down)))%"
}

// Title, detail and bar of the on-device update progress; nil = not running.
func shadowSelfUpdateRow(_ state: ShadowSelfUpdater.State) -> (String, String, Double?)? {
    let build = state.build.map { " \($0)" } ?? ""
    switch state.stage {
    case .idle:
        return nil
    case let .downloading(received, total):
        if total > 0 {
            let fraction = Double(received) / Double(total)
            return ("Загрузка сборки\(build) · \(shadowPercent(fraction))", "\(shadowMegabytes(received)) из \(shadowMegabytes(total))", fraction)
        }
        return ("Загрузка сборки\(build)…", received > 0 ? shadowMegabytes(received) : "", nil)
    case let .unpacking(fraction):
        return ("Распаковка · \(shadowPercent(fraction))", "", fraction)
    case .signing:
        return ("Подпись сертификатом…", "До минуты. Не сворачивайте Shadow, пока идёт подготовка.", nil)
    case let .packing(fraction):
        return ("Упаковка подписанного IPA · \(shadowPercent(fraction))", "", fraction)
    case .startingServer:
        return ("Подготовка установки…", "", nil)
    case let .waitingForConfirmation(hint):
        if hint {
            // No download hintDelay after the link: the cause, then the way around.
            let cause = state.diagnostics?.cause(now: Date()) ?? "Нажмите «Показать окно установки» или поделитесь IPA и установите его через ESign."
            // promptSeen: the window came, but the download did not start.
            let title = state.diagnostics?.promptSeen == true ? "Установка не началась" : "Окно установки не появилось"
            return (title, cause, nil)
        }
        return ("Подтвердите установку в окне iOS", "Нажмите «Установить» в системном окне.", nil)
    case let .sending(sent, total):
        let fraction = total > 0 ? Double(sent) / Double(total) : 0.0
        return ("Установка: передача в iOS · \(shadowPercent(fraction))", "Не закрывайте Shadow до конца передачи.", fraction)
    case .installing:
        return ("iOS устанавливает обновление", "Shadow сейчас закроется и обновится. Если иконка застряла на «Ожидание», откройте её ещё раз.", 1.0)
    case let .failed(reason):
        return ("Не удалось обновить", reason, nil)
    }
}

// The install page of the self-update: SFSafariViewController on
// http://127.0.0.1:PORT/install, which hands the itms-services link to iOS (as
// IPA Hub does). One at a time.
private final class ShadowInstallPage {
    static let shared = ShadowInstallPage()

    private weak var controller: SFSafariViewController?

    func show(_ url: URL, present: (UIViewController) -> Void) {
        self.hide(animated: false)
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        self.controller = controller
        present(controller)
    }

    func hide(animated: Bool = true) {
        guard let controller = self.controller else {
            return
        }
        self.controller = nil
        if controller.presentingViewController != nil {
            controller.dismiss(animated: animated, completion: nil)
        }
    }
}

// Keeps Shadow running for a while in the background: iOS takes the IPA from
// the local server, which stops when the app is suspended. A task lasts about
// 30 s in the background, so an expired one is begun again when Shadow comes
// back (download and signing can outlive it). Main thread only.
private final class ShadowBackgroundTask {
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    private var observer: NSObjectProtocol?
    private var ended = false

    init() {
        self.begin()
        self.observer = NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main, using: { [weak self] _ in
            self?.begin()
        })
    }

    private func begin() {
        guard !self.ended, self.identifier == .invalid else {
            return
        }
        self.identifier = UIApplication.shared.beginBackgroundTask(withName: "ShadowSelfUpdate", expirationHandler: { [weak self] in
            self?.release()
        })
    }

    private func release() {
        if self.identifier != .invalid {
            UIApplication.shared.endBackgroundTask(self.identifier)
            self.identifier = .invalid
        }
    }

    func end() {
        self.ended = true
        if let observer = self.observer {
            self.observer = nil
            NotificationCenter.default.removeObserver(observer)
        }
        self.release()
    }
}

// Short stage text for the hub row.
func shadowSelfUpdateShortText(_ state: ShadowSelfUpdater.State) -> String? {
    guard let row = shadowSelfUpdateRow(state) else {
        return nil
    }
    return row.0
}

private func shadowSelfUpdateActions(_ state: ShadowSelfUpdater.State, canRetry: Bool) -> [ShadowHubSelfUpdateAction] {
    switch state.stage {
    case .idle:
        return []
    case .waitingForConfirmation:
        return [.showPrompt, .share, .cancel]
    case .installing:
        return state.signedIPA != nil ? [.share] : []
    case .failed:
        var actions: [ShadowHubSelfUpdateAction] = []
        if canRetry {
            actions.append(.retry)
        }
        if state.signedIPA != nil {
            actions.append(.share)
        }
        actions.append(.cancel)
        return actions
    default:
        return [.cancel]
    }
}

func shadowPlural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
    let m10 = n % 10
    let m100 = n % 100
    if m10 == 1 && m100 != 11 {
        return one
    }
    if m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14) {
        return few
    }
    return many
}

// "1.5.0" out of "12.9.2-1.5.0"; nil when there is no fork part.
func shadowForkVersion(_ full: String?) -> String? {
    guard let full, let dash = full.lastIndex(of: "-") else {
        return nil
    }
    let fork = String(full[full.index(after: dash)...])
    return fork.isEmpty ? nil : fork
}

struct ShadowReleaseSummary {
    let newCount: Int
    let fixedCount: Int
    // Entries without typed notes: their items count as "changes".
    let otherCount: Int
    let releases: Int

    init(_ release: ShadowUpdateCheck.Release) {
        var newCount = 0
        var fixedCount = 0
        var otherCount = 0
        for entry in release.changelog {
            if entry.newItems.isEmpty && entry.fixedItems.isEmpty {
                otherCount += entry.items.count
            } else {
                newCount += entry.newItems.count
                fixedCount += entry.fixedItems.count
            }
        }
        self.newCount = newCount
        self.fixedCount = fixedCount
        self.otherCount = otherCount
        self.releases = max(1, release.changelog.count)
    }

    // "4 новые функции · 4 исправления · 3 выпуска"
    var text: String {
        var parts: [String] = []
        if self.newCount > 0 {
            parts.append("\(self.newCount) \(shadowPlural(self.newCount, "новая функция", "новые функции", "новых функций"))")
        }
        if self.fixedCount > 0 {
            parts.append("\(self.fixedCount) \(shadowPlural(self.fixedCount, "исправление", "исправления", "исправлений"))")
        }
        if self.otherCount > 0 {
            parts.append("\(self.otherCount) \(shadowPlural(self.otherCount, "изменение", "изменения", "изменений"))")
        }
        parts.append("\(self.releases) \(shadowPlural(self.releases, "выпуск", "выпуска", "выпусков"))")
        return parts.joined(separator: " · ")
    }

    // "4 новых, 4 испр." for the hub row.
    var shortText: String {
        var parts: [String] = []
        if self.newCount > 0 {
            parts.append("\(self.newCount) \(shadowPlural(self.newCount, "новая", "новые", "новых"))")
        }
        if self.fixedCount > 0 {
            parts.append("\(self.fixedCount) испр.")
        }
        if self.otherCount > 0 {
            parts.append("\(self.otherCount) \(shadowPlural(self.otherCount, "изменение", "изменения", "изменений"))")
        }
        return parts.joined(separator: ", ")
    }
}

private enum ShadowUpdateSection: Int32 {
    case top
    case settings
}

private final class ShadowUpdateArguments {
    var mainAction: () -> Void = {}
    var selfUpdateAction: (ShadowHubSelfUpdateAction) -> Void = { _ in }
    var openCertificate: () -> Void = {}
    var updateBeta: (Bool) -> Void = { _ in }
    var openArchive: () -> Void = {}
}

private enum ShadowUpdateEntry: ItemListNodeEntry {
    case summary(String)
    case counts(String)
    case status(String)
    case buildStatus(String)
    case progress(title: String, detail: String, progress: Double?)
    // What the local install saw (ShadowInstallDiagnostics.line).
    case diagnostics(String)
    case action(ShadowHubSelfUpdateAction)
    case mainButton(String, Bool)
    case mainFooter(String)
    case settingsHeader
    case certificate(String)
    case beta(Bool)
    case archive
    // Changes of one build: header, then one row per item. `release` is the
    // position among the skipped builds (0 = newest), `index` the item.
    case buildHeader(release: Int32, text: String)
    case change(release: Int32, index: Int32, text: String)

    var section: ItemListSectionId {
        switch self {
        case .summary, .counts, .status, .buildStatus, .progress, .diagnostics, .action, .mainButton, .mainFooter:
            return ShadowUpdateSection.top.rawValue
        case .settingsHeader, .certificate, .beta, .archive:
            return ShadowUpdateSection.settings.rawValue
        case let .buildHeader(release, _), let .change(release, _, _):
            return 10 + release
        }
    }

    // In display order (the list diff expects it).
    var stableId: Int32 {
        switch self {
        case .summary: return 0
        case .counts: return 1
        case .status: return 2
        case .buildStatus: return 3
        case .progress: return 4
        case .diagnostics: return 5
        case let .action(action): return 6 + action.rawValue
        case .mainButton: return 10
        case .mainFooter: return 11
        case .settingsHeader: return 20
        case .certificate: return 21
        case .beta: return 22
        case .archive: return 23
        case let .buildHeader(release, _): return 1000 + release * 1000
        case let .change(release, index, _): return 1000 + release * 1000 + 1 + min(index, 998)
        }
    }

    static func <(lhs: ShadowUpdateEntry, rhs: ShadowUpdateEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ShadowUpdateArguments
        switch self {
        case let .summary(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section, textAlignment: .center)
        case let .counts(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section, textAlignment: .center)
        case let .status(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section, textAlignment: .center)
        case let .buildStatus(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section, textAlignment: .center)
        case let .progress(title, detail, progress):
            return ShadowProgressItem(presentationData: presentationData, title: title, detail: detail, progress: progress, sectionId: self.section)
        case let .diagnostics(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section, textAlignment: .center)
        case let .action(action):
            return ShadowBigButtonItem(presentationData: presentationData, title: action.title, enabled: true, style: action.style, sectionId: self.section, action: {
                arguments.selfUpdateAction(action)
            })
        case let .mainButton(title, enabled):
            return ShadowBigButtonItem(presentationData: presentationData, title: title, enabled: enabled, sectionId: self.section, action: {
                arguments.mainAction()
            })
        case let .mainFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section, textAlignment: .center)
        case .settingsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "НАСТРОЙКИ ОБНОВЛЕНИЙ", sectionId: self.section)
        case let .certificate(label):
            return ItemListDisclosureItem(presentationData: presentationData, title: "Сертификат для подписи", label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openCertificate()
            })
        case let .beta(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Бета-версии", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateBeta(value)
            })
        case .archive:
            return ItemListDisclosureItem(presentationData: presentationData, title: "Архив версий", label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openArchive()
            })
        case let .buildHeader(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .change(_, _, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

// Rows of the changes: typed when the changelog has new/fixed, plain otherwise.
private func shadowChangeLines(_ entry: ShadowUpdateCheck.ChangelogEntry) -> [String] {
    if entry.newItems.isEmpty && entry.fixedItems.isEmpty {
        return entry.items.map { "• " + $0 }
    }
    return entry.newItems.map { "НОВОЕ · " + $0 } + entry.fixedItems.map { "ИСПРАВЛЕНО · " + $0 }
}

func shadowUpdateController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?
    let arguments = ShadowUpdateArguments()
    let updateState = ValuePromise<ShadowHubUpdateState>(.idle, ignoreRepeated: true)
    let buildStatus = ValuePromise<String?>(nil, ignoreRepeated: true)
    var availableRelease: ShadowUpdateCheck.Release?
    var currentStatus: ShadowHubUpdateState = .idle

    let signingChanges: Signal<Void, NoError> = Signal { subscriber in
        subscriber.putNext(Void())
        let observer = NotificationCenter.default.addObserver(forName: ShadowSigningStore.didChangeNotification, object: nil, queue: .main, using: { _ in
            subscriber.putNext(Void())
        })
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    let selfUpdate: Signal<(ShadowSelfUpdater.State, Bool), NoError> = combineLatest(ShadowSelfUpdater.shared.state, signingChanges)
    |> map { state, _ -> (ShadowSelfUpdater.State, Bool) in
        return (state, ShadowSigningStore.shared.isConfigured)
    }

    let check: () -> Void = {
        if case .checking = currentStatus {
            return
        }
        currentStatus = .checking
        updateState.set(.checking)
        let betaEnabled = currentAyuGramSettings(accountId: context.account.id).updateChannelBeta
        ShadowUpdateCheck.check(betaEnabled: betaEnabled) { status in
            if case let .available(release) = status {
                availableRelease = release
            } else {
                availableRelease = nil
            }
            currentStatus = .result(status)
            updateState.set(.result(status))
        }
        ShadowBuildStatus.fetch { info in
            buildStatus.set(info.map { ShadowBuildStatus.text($0) })
        }
    }

    let startSelfUpdate: () -> Void = {
        guard let release = availableRelease, let url = release.downloadURL else {
            return
        }
        let version = release.changelog.first(where: { $0.build == release.build })?.version
        let bindings = context.sharedContext.applicationBindings
        // The result of UIApplication.open goes to the diagnostics line.
        let opener = ShadowSelfUpdater.InstallOpener(openURL: { installURL, completion in
            UIApplication.shared.open(installURL, options: [:], completionHandler: completion)
        }, showPage: { pageURL in
            ShadowInstallPage.shared.show(pageURL, present: { controller in
                bindings.presentNativeController(controller)
            })
        }, hidePage: {
            ShadowInstallPage.shared.hide()
        })
        ShadowSelfUpdater.shared.start(ipaURL: url, build: release.build, version: version, opener: opener, keepAwake: {
            let idleTimer = bindings.pushIdleTimerExtension()
            let backgroundTask = ShadowBackgroundTask()
            return ActionDisposable {
                idleTimer.dispose()
                backgroundTask.end()
            }
        })
    }

    arguments.mainAction = {
        guard let release = availableRelease else {
            check()
            return
        }
        if ShadowSigningStore.shared.isConfigured, release.downloadURL != nil {
            startSelfUpdate()
        } else {
            context.sharedContext.applicationBindings.openUrl((release.downloadURL ?? release.pageURL).absoluteString)
        }
    }
    arguments.selfUpdateAction = { action in
        switch action {
        case .showPrompt:
            ShadowSelfUpdater.shared.retryInstallPrompt()
        case .share:
            guard let ipa = ShadowSelfUpdater.shared.currentState.signedIPA else {
                return
            }
            let share = UIActivityViewController(activityItems: [ipa], applicationActivities: nil)
            context.sharedContext.applicationBindings.presentNativeController(share)
        case .retry:
            startSelfUpdate()
        case .cancel:
            ShadowSelfUpdater.shared.cancel()
        }
    }
    arguments.openCertificate = {
        pushControllerImpl?(shadowAutoUpdateController(context: context))
    }
    arguments.updateBeta = { value in
        let _ = (updateAyuGramSettings(postbox: context.account.postbox, { settings in
            var settings = settings
            settings.updateChannelBeta = value
            return settings
        })
        |> deliverOnMainQueue).startStandalone(completed: {
            currentStatus = .idle
            check()
        })
    }
    arguments.openArchive = {
        pushControllerImpl?(shadowVersionArchiveController(context: context))
    }

    let settingsSignal: Signal<AyuGramSettings, NoError> = ayuGramSettings(postbox: context.account.postbox)
    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, updateState.get(), buildStatus.get(), selfUpdate, settingsSignal)
    |> map { presentationData, updateState, buildStatus, selfUpdate, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let (selfUpdateState, signingReady) = selfUpdate
        let installed = ShadowUpdateCheck.installedBuild.map { "\($0)" } ?? "?"
        let currentFork = ShadowVersion.fork
        var entries: [ShadowUpdateEntry] = []
        var release: ShadowUpdateCheck.Release?

        switch updateState {
        case .idle, .checking:
            entries.append(.summary("Shadow \(currentFork) · сборка \(installed)"))
            entries.append(.status("Проверяю обновления…"))
        case let .result(status):
            switch status {
            case let .available(value):
                release = value
                let target = shadowForkVersion(value.changelog.first(where: { $0.build == value.build })?.version) ?? "\(value.build)"
                entries.append(.summary("\(currentFork) → \(target)\nсборка \(installed) → \(value.build)" + (value.isBeta ? " · бета" : "")))
                entries.append(.counts(ShadowReleaseSummary(value).text))
                if value.isRequired {
                    entries.append(.status("Обязательное обновление"))
                }
            case .upToDate:
                entries.append(.summary("Shadow \(currentFork) · сборка \(installed)"))
                entries.append(.status("Актуальная версия"))
            case let .failed(reason):
                entries.append(.summary("Shadow \(currentFork) · сборка \(installed)"))
                entries.append(.status("Не удалось проверить: \(reason)"))
            }
        }
        if let buildStatus {
            entries.append(.buildStatus(buildStatus))
        }

        if let row = shadowSelfUpdateRow(selfUpdateState) {
            entries.append(.progress(title: row.0, detail: row.1, progress: row.2))
            if let diagnostics = selfUpdateState.diagnostics {
                entries.append(.diagnostics(diagnostics.line))
            }
            for action in shadowSelfUpdateActions(selfUpdateState, canRetry: signingReady && release != nil) {
                entries.append(.action(action))
            }
        } else if let release {
            let target = shadowForkVersion(release.changelog.first(where: { $0.build == release.build })?.version) ?? "\(release.build)"
            if signingReady, release.downloadURL != nil {
                entries.append(.mainButton("Обновить до \(target)", true))
            } else {
                entries.append(.mainButton("Скачать IPA \(target)", true))
                entries.append(.mainFooter("Нет сертификата — установка через ссылку."))
            }
        } else {
            var checking = false
            if case .checking = updateState {
                checking = true
            }
            entries.append(.mainButton("Проверить обновления", !checking))
        }

        entries.append(.settingsHeader)
        entries.append(.certificate(signingReady ? "Готов" : "Не выбран"))
        entries.append(.beta(settings.updateChannelBeta))
        entries.append(.archive)

        if let release {
            if release.changelog.isEmpty {
                let notes = release.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                if !notes.isEmpty {
                    entries.append(.buildHeader(release: 0, text: "СБОРКА \(release.build)"))
                    entries.append(.change(release: 0, index: 0, text: String(notes.prefix(1500))))
                }
            } else {
                // At most 20 builds, 60 items each: a long gap stays readable.
                for (position, entry) in release.changelog.prefix(20).enumerated() {
                    let header = "СБОРКА \(entry.build)" + (entry.date.isEmpty ? "" : " · \(entry.date)")
                    entries.append(.buildHeader(release: Int32(position), text: header))
                    for (index, line) in shadowChangeLines(entry).prefix(60).enumerated() {
                        entries.append(.change(release: Int32(position), index: Int32(index), text: line))
                    }
                }
            }
        }

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Обновление"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    check()
    return controller
}

import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import AlertUI
import ShadowSelfUpdate

// Shadow fork settings.
//
// The entry point (`ayuGramSettingsController`) groups settings by purpose:
// privacy, archive/media, interface, accounts and service tools. Everything is
// in Russian and uses Telegram's stock settings components.

// The maximum-age steps for the saved-attachments auto-clean, in seconds
// (0 = never). Kept in one place so picker and label stay in sync.
private let attachmentAgeIntervals: [Int32] = [0, 86400, 259200, 604800, 1209600, 2592000, 7776000, 15552000, 31536000]

private func attachmentAgeLabel(_ value: Int32) -> String {
    switch value {
    case 86400:
        return "1 день"
    case 259200:
        return "3 дня"
    case 604800:
        return "7 дней"
    case 1209600:
        return "14 дней"
    case 2592000:
        return "30 дней"
    case 7776000:
        return "90 дней"
    case 15552000:
        return "180 дней"
    case 31536000:
        return "1 год"
    default:
        return "Никогда"
    }
}

// The maximum-size steps for the saved-attachments cache, in bytes (0 = ∞).
private let attachmentSizeLimits: [Int64] = [0, 314572800, 1073741824, 2147483648, 5368709120, 6442450944, 12884901888]

private func shadowBottomBarScrollLabel(_ mode: Int32) -> String {
    switch mode {
    case 1: return "Скрывать при прокрутке вниз"
    case 2: return "Скрывать и показывать при остановке"
    case 3: return "Скрывать при прокрутке вверх и вниз"
    default: return "Всегда показывать"
    }
}

private func attachmentSizeLabel(_ value: Int64) -> String {
    switch value {
    case 314572800:
        return "300 МБ"
    case 1073741824:
        return "1 ГБ"
    case 2147483648:
        return "2 ГБ"
    case 5368709120:
        return "5 ГБ"
    case 6442450944:
        return "6 ГБ"
    case 12884901888:
        return "12 ГБ"
    default:
        return "∞"
    }
}

// MARK: - Hub

private enum AyuHubSection: Int32 {
    case updateBanner
    case search
    case privacy
    case interface
    case accounts
    case tools
    case info
    case updateCheck
    case admin
}

// Shadow: a big "check for updates" button opens the hub; status, the IPA
// download button and the notes of every skipped build go right under it
// (ShadowUpdateCheck).
private enum ShadowHubUpdateState: Equatable {
    case idle
    case checking
    case result(ShadowUpdateCheck.Status)
}

private enum AyuHubEntry: ItemListNodeEntry {
    case updateButton(enabled: Bool)
    case updateStatus(String)
    // Shadow: the build CI is running right now (ShadowBuildStatus).
    case buildStatus(String)
    case downloadButton(String, String)
    // Shadow: on-device update (ShadowSelfUpdater, "Автообновление").
    case selfUpdateButton(String)
    case selfUpdateProgress(title: String, detail: String, progress: Double?)
    case selfUpdateAction(ShadowHubSelfUpdateAction)
    case updateNotes(title: String, text: String)
    case query(String)
    case result(ShadowSettingsSearchItem)
    case noResults
    case customization
    case spy
    case ghost
    case misc
    case backup
    case filters
    case hiddenAccounts
    case settingsSync
    case pushDiagnostics
    case quickReplies
    case chatLocks
    case secondSpace
    case emergency
    case versionArchive
    case autoUpdate(String)
    case crashReports(Int)
    case infoFooter
    case deviceAccess

    var section: ItemListSectionId {
        switch self {
        case .updateButton, .updateStatus, .buildStatus, .downloadButton, .selfUpdateButton, .selfUpdateProgress, .selfUpdateAction:
            return AyuHubSection.updateBanner.rawValue
        case .updateNotes:
            return AyuHubSection.updateCheck.rawValue
        case .deviceAccess:
            return AyuHubSection.admin.rawValue
        case .query:
            return AyuHubSection.search.rawValue
        case .result:
            return AyuHubSection.privacy.rawValue
        case .noResults:
            return AyuHubSection.info.rawValue
        case .customization, .spy, .ghost, .filters, .misc, .hiddenAccounts, .settingsSync, .backup, .pushDiagnostics, .quickReplies, .chatLocks, .secondSpace, .emergency, .versionArchive, .autoUpdate, .crashReports:
            return AyuHubSection.tools.rawValue
        case .infoFooter:
            return AyuHubSection.info.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        // In display order: the list diff (mergeListsStableWithUpdates) expects it.
        case .updateButton: return -16
        case .updateStatus: return -15
        case .buildStatus: return -14
        case .selfUpdateProgress: return -13
        case .selfUpdateButton: return -12
        case let .selfUpdateAction(action): return -11 + action.rawValue
        case .downloadButton: return -3
        case .updateNotes: return -2
        case .query: return -1
        case .deviceAccess: return 30
        case let .result(item): return 100 + item.id
        case .noResults: return 10
        case .customization:
            return 0
        case .spy:
            return 1
        case .ghost:
            return 2
        case .filters:
            return 3
        case .misc:
            return 4
        case .quickReplies:
            return 12
        case .chatLocks:
            return 13
        case .secondSpace:
            return 14
        case .emergency:
            return 16
        case .versionArchive:
            return 17
        case .autoUpdate:
            return 18
        case .crashReports:
            return 15
        case .infoFooter:
            return 20
        case .backup:
            return 6
        case .hiddenAccounts:
            return 5
        case .settingsSync:
            return 8
        case .pushDiagnostics:
            return 7
        }
    }

    static func <(lhs: AyuHubEntry, rhs: AyuHubEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AyuHubArguments
        switch self {
        case let .query(value):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(string: ""), text: value, placeholder: "Поиск настроек Shadow", type: .regular(capitalization: false, autocorrection: false), clearType: .always, sectionId: self.section, textUpdated: arguments.updateQuery, action: {})
        case let .result(item):
            return ItemListDisclosureItem(presentationData: presentationData, title: item.title, label: item.path + "\n" + item.description, labelStyle: .multilineDetailText, sectionId: self.section, style: .blocks, action: { arguments.openResult(item) })
        case .noResults:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Ничего не найдено. Попробуйте другое слово на русском или английском."), sectionId: self.section)
        case .customization:
            return ItemListDisclosureItem(presentationData: presentationData, title: "Кастомизация", label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openCustomization()
            })
        case .spy:
            return ItemListDisclosureItem(presentationData: presentationData, title: "Шпион", label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openSpy()
            })
        case .ghost:
            return ItemListDisclosureItem(presentationData: presentationData, title: "Призрак", label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openGhost()
            })
        case .misc:
            return ItemListDisclosureItem(presentationData: presentationData, title: "Подмена профиля", label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openMisc()
            })
        case .infoFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Скрытый аккаунт остаётся авторизованным и продолжает получать обновления, но не показывается в переключателе аккаунтов."), sectionId: self.section)
        case .backup:
            return ItemListDisclosureItem(presentationData: presentationData, title: "Резервная копия настроек", label: "", sectionId: self.section, style: .blocks, action: arguments.openBackup)
        case .filters:
            return ItemListDisclosureItem(presentationData: presentationData, title: "Фильтры", label: "", sectionId: self.section, style: .blocks, action: arguments.openFilters)
        case .hiddenAccounts:
            return ItemListDisclosureItem(presentationData: presentationData, title: "Скрытие аккаунтов", label: "", sectionId: self.section, style: .blocks, action: arguments.openHiddenAccounts)
        case .settingsSync:
            return ItemListDisclosureItem(presentationData: presentationData, title: "Синхронизация аккаунтов", label: "", sectionId: self.section, style: .blocks, action: arguments.openSettingsSync)
        case .pushDiagnostics:
            return ItemListDisclosureItem(presentationData: presentationData, title: "Разное", label: "", sectionId: self.section, style: .blocks, action: arguments.openPushDiagnostics)
        case .quickReplies:
            return ItemListDisclosureItem(presentationData: presentationData, title: "Шаблоны ответов", label: "", sectionId: self.section, style: .blocks, action: { arguments.openFeature(.quickReplies) })
        case .chatLocks:
            return ItemListDisclosureItem(presentationData: presentationData, title: "Замки чатов", label: "", sectionId: self.section, style: .blocks, action: { arguments.openFeature(.chatLocks) })
        case .secondSpace:
            return ItemListDisclosureItem(presentationData: presentationData, title: "Второе пространство", label: "", sectionId: self.section, style: .blocks, action: { arguments.openFeature(.secondSpace) })
        case .emergency:
            return ItemListDisclosureItem(presentationData: presentationData, title: "Экстренная защита", label: "", sectionId: self.section, style: .blocks, action: { arguments.openFeature(.emergency) })
        case .versionArchive:
            return ItemListDisclosureItem(presentationData: presentationData, title: "Архив версий", label: "", sectionId: self.section, style: .blocks, action: { arguments.openVersionArchive() })
        case let .autoUpdate(label):
            return ItemListDisclosureItem(presentationData: presentationData, title: "Автообновление", label: label, sectionId: self.section, style: .blocks, action: { arguments.openAutoUpdate() })
        case let .selfUpdateButton(title):
            return ShadowBigButtonItem(presentationData: presentationData, title: title, enabled: true, sectionId: self.section, action: {
                arguments.startSelfUpdate()
            })
        case let .selfUpdateProgress(title, detail, progress):
            return ShadowProgressItem(presentationData: presentationData, title: title, detail: detail, progress: progress, sectionId: self.section)
        case let .selfUpdateAction(action):
            return ItemListActionItem(presentationData: presentationData, title: action.title, kind: action == .cancel ? .destructive : .generic, alignment: .center, sectionId: self.section, style: .blocks, action: {
                arguments.selfUpdateAction(action)
            })
        case let .crashReports(count):
            return ItemListDisclosureItem(presentationData: presentationData, title: "Отчёты о вылетах", label: "\(count)", sectionId: self.section, style: .blocks, action: { arguments.openCrashReports() })
        case let .updateButton(enabled):
            return ShadowBigButtonItem(presentationData: presentationData, title: "Проверить обновления", enabled: enabled, sectionId: self.section, action: {
                arguments.checkUpdates()
            })
        case let .updateStatus(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section, textAlignment: .center)
        case let .buildStatus(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section, textAlignment: .center)
        case let .downloadButton(title, url):
            return ShadowBigButtonItem(presentationData: presentationData, title: title, enabled: true, sectionId: self.section, action: {
                arguments.openUrl(url)
            })
        case let .updateNotes(title, text):
            return ItemListInfoItem(presentationData: presentationData, title: title, text: .plain(text), style: .blocks, sectionId: self.section, closeAction: {
                arguments.dismissUpdateBanner()
            })
        case .deviceAccess:
            return ItemListDisclosureItem(presentationData: presentationData, title: "Доступ устройств", label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openDeviceAccess()
            })
        }
    }
}

private final class AyuHubArguments {
    let updateQuery: (String) -> Void
    let openResult: (ShadowSettingsSearchItem) -> Void
    let openCustomization: () -> Void
    let openSpy: () -> Void
    let openGhost: () -> Void
    let openMisc: () -> Void
    let openBackup: () -> Void
    let openFilters: () -> Void
    let openHiddenAccounts: () -> Void
    let openPushDiagnostics: () -> Void
    var openFeature: (ShadowSettingsSearchDestination) -> Void = { _ in }
    var checkUpdates: () -> Void = {}
    var dismissUpdateBanner: () -> Void = {}
    var openUrl: (String) -> Void = { _ in }
    var openCrashReports: () -> Void = {}
    var openDeviceAccess: () -> Void = {}
    var openVersionArchive: () -> Void = {}
    var openSettingsSync: () -> Void = {}
    var openAutoUpdate: () -> Void = {}
    var startSelfUpdate: () -> Void = {}
    var selfUpdateAction: (ShadowHubSelfUpdateAction) -> Void = { _ in }

    init(updateQuery: @escaping (String) -> Void, openResult: @escaping (ShadowSettingsSearchItem) -> Void, openCustomization: @escaping () -> Void, openSpy: @escaping () -> Void, openGhost: @escaping () -> Void, openMisc: @escaping () -> Void, openBackup: @escaping () -> Void, openFilters: @escaping () -> Void, openHiddenAccounts: @escaping () -> Void, openPushDiagnostics: @escaping () -> Void) {
        self.updateQuery = updateQuery
        self.openResult = openResult
        self.openCustomization = openCustomization
        self.openSpy = openSpy
        self.openGhost = openGhost
        self.openMisc = openMisc
        self.openBackup = openBackup
        self.openFilters = openFilters
        self.openHiddenAccounts = openHiddenAccounts
        self.openPushDiagnostics = openPushDiagnostics
    }
}

func shadowSettingsSearchDestinationController(context: AccountContext, item: ShadowSettingsSearchItem) -> ViewController {
    switch item.destination {
    case .customization: return ayuCustomizationController(context: context, focus: item)
    case .spy: return ayuSpyController(context: context, focus: item)
    case .ghost: return ayuGhostController(context: context, focus: item)
    case .misc: return ayuMiscController(context: context, focus: item)
    case .backup: return shadowSettingsBackupController(context: context, focus: item)
    case .autoUpdate: return shadowAutoUpdateController(context: context, focus: item)
    case .filters: return shadowMessageFiltersController(context: context)
    case .pushDiagnostics:
        if item.entryId == 0 {
            return shadowPushDiagnosticsController(context: context)
        } else {
            return shadowMiscController(context: context)
        }
    case .quickReplies: return shadowQuickRepliesController(context: context, focus: item)
    case .chatLocks: return shadowChatLocksController(context: context, focus: item)
    case .secondSpace: return shadowSecondSpaceController(context: context, focus: item)
    case .emergency: return shadowEmergencyController(context: context, focus: item)
    }
}

// Notes of every build between the installed and the announced one, newest
// first; long gaps are cut by builds, not in the middle of an item.
private func shadowUpdateNotesText(_ release: ShadowUpdateCheck.Release) -> String {
    guard !release.changelog.isEmpty else {
        return String(release.notes.trimmingCharacters(in: .whitespacesAndNewlines).prefix(600))
    }
    let shown = release.changelog.prefix(5)
    var blocks = shown.map { entry -> String in
        let header = "Сборка \(entry.build)" + (entry.date.isEmpty ? "" : " · \(entry.date)") + ":"
        return header + "\n" + entry.items.map { "• \($0)" }.joined(separator: "\n")
    }
    let rest = release.changelog.count - shown.count
    if rest > 0 {
        blocks.append("…и ещё \(rest) сборок")
    }
    return blocks.joined(separator: "\n\n")
}

// Shadow: buttons under the on-device update progress.
enum ShadowHubSelfUpdateAction: Int32 {
    // Raw values follow the display order (stableIds of the rows).
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
}

private func shadowMegabytes(_ bytes: Int64) -> String {
    return String(format: "%.1f МБ", Double(bytes) / (1024.0 * 1024.0))
}

private func shadowPercent(_ fraction: Double) -> String {
    return "\(Int((max(0.0, min(1.0, fraction)) * 100.0).rounded(.down)))%"
}

// Title, detail and bar of the progress row; nil = nothing to show.
private func shadowSelfUpdateRow(_ state: ShadowSelfUpdater.State) -> (String, String, Double?)? {
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
        return ("Подтвердите установку в окне iOS", hint ? "Окно не появилось или закрыто — нажмите «Показать окно установки». Можно также поделиться IPA и поставить его вручную." : "Нажмите «Установить» в системном окне.", nil)
    case let .sending(sent, total):
        let fraction = total > 0 ? Double(sent) / Double(total) : 0.0
        return ("Установка: передача в iOS · \(shadowPercent(fraction))", "Не закрывайте Shadow до конца передачи.", fraction)
    case .installing:
        return ("iOS устанавливает обновление", "Shadow сейчас закроется и обновится. Если иконка застряла на «Ожидание», откройте её ещё раз.", 1.0)
    case let .failed(reason):
        return ("Не удалось обновить", reason, nil)
    }
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

// autoCheckUpdates: start "Проверить обновления" right away (shadow://updates).
public func ayuGramSettingsController(context: AccountContext, autoCheckUpdates: Bool = false) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?
    var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?
    let query = ValuePromise<String>("", ignoreRepeated: true)

    let arguments = AyuHubArguments(
        updateQuery: { query.set(String($0.prefix(256))) },
        openResult: { item in
            pushControllerImpl?(shadowSettingsSearchDestinationController(context: context, item: item))
        },
        openCustomization: {
            pushControllerImpl?(ayuCustomizationController(context: context))
        },
        openSpy: {
            pushControllerImpl?(ayuSpyController(context: context))
        },
        openGhost: {
            pushControllerImpl?(ayuGhostController(context: context))
        },
        openMisc: {
            pushControllerImpl?(ayuMiscController(context: context))
        },
        openBackup: {
            pushControllerImpl?(shadowSettingsBackupController(context: context))
        },
        openFilters: {
            pushControllerImpl?(shadowMessageFiltersController(context: context))
        },
        openHiddenAccounts: {
            pushControllerImpl?(shadowHiddenAccountsController(context: context))
        },
        openPushDiagnostics: {
            pushControllerImpl?(shadowMiscController(context: context))
        }
    )

    arguments.openSettingsSync = {
        pushControllerImpl?(shadowSettingsSyncController(context: context))
    }

    arguments.openFeature = { destination in
        switch destination {
        case .quickReplies:
            pushControllerImpl?(shadowQuickRepliesController(context: context))
        case .chatLocks:
            pushControllerImpl?(shadowChatLocksController(context: context))
        case .secondSpace:
            pushControllerImpl?(shadowSecondSpaceController(context: context))
        case .emergency:
            pushControllerImpl?(shadowEmergencyController(context: context))
        default:
            break
        }
    }

    let updateState = ValuePromise<ShadowHubUpdateState>(.idle, ignoreRepeated: true)
    // Shadow: the announced release, for "Обновить" (on-device signing).
    var availableRelease: ShadowUpdateCheck.Release?
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
    let bannerDismissed = ValuePromise<Bool>(false, ignoreRepeated: true)
    // Shadow: refreshed only by "Проверить обновления"; nil = no build running.
    let buildStatus = ValuePromise<String?>(nil, ignoreRepeated: true)
    // Shadow: bumped when crash reports are sent or deleted.
    let crashRevision = ValuePromise<Int>(0, ignoreRepeated: false)
    var crashRevisionValue = 0
    arguments.openCrashReports = {
        let reports = ShadowCrashReports.shared.reports()
        guard !reports.isEmpty else {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let actionSheet = ActionSheetController(presentationData: presentationData)
        actionSheet.setItemGroups([
            ActionSheetItemGroup(items: [
                ActionSheetTextItem(title: "Приложение падало \(reports.count) раз(а). Отправьте отчёты разработчику — в них нет переписки, только технические данные.", parseMarkdown: false),
                ActionSheetButtonItem(title: "Отправить в чат…", color: .accent, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    let picker = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(context: context, filter: [.onlyWriteable, .excludeDisabled], hasContactSelector: false, title: "Кому отправить"))
                    picker.peerSelected = { [weak picker] peer, _ in
                        picker?.dismiss()
                        shadowSendCrashReports(context: context, peerId: peer.id, reports: reports, completion: {
                            crashRevisionValue += 1
                            crashRevision.set(crashRevisionValue)
                        })
                    }
                    pushControllerImpl?(picker)
                }),
                ActionSheetButtonItem(title: "Удалить отчёты", color: .destructive, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    ShadowCrashReports.shared.removeAll()
                    crashRevisionValue += 1
                    crashRevision.set(crashRevisionValue)
                })
            ]),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
            })])
        ])
        presentControllerImpl?(actionSheet, nil)
    }
    arguments.checkUpdates = {
        updateState.set(.checking)
        bannerDismissed.set(false)
        let betaEnabled = currentAyuGramSettings(accountId: context.account.id).updateChannelBeta
        ShadowUpdateCheck.check(betaEnabled: betaEnabled) { status in
            if case let .available(release) = status {
                availableRelease = release
            } else {
                availableRelease = nil
            }
            updateState.set(.result(status))
        }
        ShadowBuildStatus.fetch { info in
            buildStatus.set(info.map { ShadowBuildStatus.text($0) })
        }
    }
    arguments.dismissUpdateBanner = {
        bannerDismissed.set(true)
    }
    arguments.openUrl = { url in
        context.sharedContext.applicationBindings.openUrl(url)
    }
    arguments.openVersionArchive = {
        pushControllerImpl?(shadowVersionArchiveController(context: context))
    }
    arguments.openDeviceAccess = {
        pushControllerImpl?(shadowDeviceAccessController(context: context))
    }
    arguments.openAutoUpdate = {
        pushControllerImpl?(shadowAutoUpdateController(context: context))
    }
    let startSelfUpdate: () -> Void = {
        guard let release = availableRelease, let url = release.downloadURL else {
            return
        }
        let version = release.changelog.first(where: { $0.build == release.build })?.version
        let bindings = context.sharedContext.applicationBindings
        ShadowSelfUpdater.shared.start(ipaURL: url, build: release.build, version: version, openURL: { installURL in
            bindings.openUrl(installURL.absoluteString)
        }, keepAwake: {
            return bindings.pushIdleTimerExtension()
        })
    }
    arguments.startSelfUpdate = startSelfUpdate
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
    // Shadow: the device whitelist editor is for the admins only.
    let isAdmin = ShadowDeviceAccess.hasAdminAccess(peerId: context.account.peerId.id._internalGetInt64Value())

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, query.get(), updateState.get(), bannerDismissed.get(), crashRevision.get(), buildStatus.get(), selfUpdate)
    |> deliverOnMainQueue
    |> map { presentationData, query, updateState, bannerDismissed, _, buildStatus, selfUpdate -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let (selfUpdateState, signingReady) = selfUpdate
        let installed = ShadowUpdateCheck.installedBuild.map { "\($0)" } ?? "?"
        var updateEnabled = true
        var statusText = "Установлена \(ShadowVersion.full) · сборка \(installed)"
        var download: (String, String)?
        var notes: (String, String)?
        var selfUpdateTitle: String?
        switch updateState {
        case .idle:
            break
        case .checking:
            statusText = "Проверяю…"
            updateEnabled = false
        case let .result(status):
            switch status {
            case .upToDate:
                statusText = "Актуально · \(ShadowVersion.full) · сборка \(installed)"
            case let .available(release):
                statusText = "У тебя \(installed) → доступна \(release.build)"
                if release.changelog.count > 1 {
                    statusText += ", пропущено \(release.changelog.count) обновлений"
                }
                if release.isRequired {
                    statusText = "Обязательное обновление. " + statusText
                }
                download = (release.isBeta ? "Скачать бету IPA (\(release.build))" : "Скачать IPA (\(release.build))", (release.downloadURL ?? release.pageURL).absoluteString)
                if signingReady, release.downloadURL != nil {
                    selfUpdateTitle = release.isBeta ? "Обновить до беты \(release.build)" : "Обновить до \(release.build)"
                }
                if !bannerDismissed {
                    notes = (release.title, shadowUpdateNotesText(release))
                }
            case let .failed(reason):
                statusText = "Не удалось проверить: \(reason)"
            }
        }
        var entries: [AyuHubEntry] = [.updateButton(enabled: updateEnabled), .updateStatus(statusText)]
        if let buildStatus {
            entries.append(.buildStatus(buildStatus))
        }
        if let row = shadowSelfUpdateRow(selfUpdateState) {
            entries.append(.selfUpdateProgress(title: row.0, detail: row.1, progress: row.2))
            for action in shadowSelfUpdateActions(selfUpdateState, canRetry: signingReady && availableRelease != nil) {
                entries.append(.selfUpdateAction(action))
            }
        } else if let selfUpdateTitle {
            entries.append(.selfUpdateButton(selfUpdateTitle))
        }
        if let download {
            entries.append(.downloadButton(download.0, download.1))
        }
        if let notes, !notes.1.isEmpty {
            entries.append(.updateNotes(title: notes.0, text: notes.1))
        }
        entries.append(.query(query))
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            entries += [.customization, .spy, .ghost, .filters, .misc, .hiddenAccounts, .settingsSync, .backup, .pushDiagnostics, .quickReplies, .chatLocks, .secondSpace, .emergency, .versionArchive, .autoUpdate(signingReady ? "Вкл" : "Выкл"), .infoFooter]
            let crashCount = ShadowCrashReports.shared.reports().count
            if crashCount > 0 {
                entries.insert(.crashReports(crashCount), at: entries.firstIndex(where: { if case .infoFooter = $0 { return true } else { return false } }) ?? entries.count)
            }
            if isAdmin {
                entries.append(.deviceAccess)
            }
        } else {
            let matches = ShadowSettingsSearchIndex.search(query)
            entries += matches.isEmpty ? [.noResults] : matches.map { .result($0) }
        }
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Shadow"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] c in
        controller?.view.endEditing(true)
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    presentControllerImpl = { [weak controller] c, a in
        controller?.present(c, in: .window(.root), with: a)
    }
    if autoCheckUpdates {
        arguments.checkUpdates()
    }
    return controller
}

// MARK: - Accounts

private enum ShadowHiddenAccountsSection: Int32 {
    case accounts
    case info
}

private final class ShadowHiddenAccountsArguments {
    let updateHidden: (PeerId, Bool) -> Void

    init(updateHidden: @escaping (PeerId, Bool) -> Void) {
        self.updateHidden = updateHidden
    }
}

private enum ShadowHiddenAccountsEntry: ItemListNodeEntry {
    case account(Int32, PeerId, String, Bool, Bool)
    case info

    var section: ItemListSectionId {
        switch self {
        case .account:
            return ShadowHiddenAccountsSection.accounts.rawValue
        case .info:
            return ShadowHiddenAccountsSection.info.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case let .account(index, _, _, _, _):
            return index
        case .info:
            return 10_000
        }
    }

    static func <(lhs: ShadowHiddenAccountsEntry, rhs: ShadowHiddenAccountsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ShadowHiddenAccountsArguments
        switch self {
        case let .account(_, peerId, title, isCurrent, isHidden):
            let suffix = isCurrent ? " · текущий" : ""
            let userId = peerId.id._internalGetInt64Value()
            return ItemListSwitchItem(presentationData: presentationData, title: "\(title) · ID \(userId)\(suffix)", value: isHidden, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateHidden(peerId, value)
            })
        case .info:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Включённый переключатель скрывает аккаунт из списка и быстрого переключателя. Аккаунт не выходит из системы, продолжает синхронизацию и остаётся доступен на этом экране. Текущий аккаунт исчезнет из переключателя после перехода на другой."), sectionId: self.section)
        }
    }
}

private struct ShadowActiveAccount {
    let context: AccountContext
    let peer: EnginePeer
    let isCurrent: Bool
    let sortOrder: Int32
}

private func shadowActiveAccounts(context: AccountContext) -> Signal<[ShadowActiveAccount], NoError> {
    return context.sharedContext.activeAccountContexts
    |> mapToSignal { primary, accounts, _ -> Signal<[ShadowActiveAccount], NoError> in
        let primaryId = primary?.account.id
        let accountSignals: [Signal<ShadowActiveAccount?, NoError>] = accounts.map { _, accountContext, sortOrder in
            return accountContext.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: accountContext.account.peerId))
            |> map { peer -> ShadowActiveAccount? in
                guard let peer else {
                    return nil
                }
                return ShadowActiveAccount(
                    context: accountContext,
                    peer: peer,
                    isCurrent: accountContext.account.id == primaryId,
                    sortOrder: sortOrder
                )
            }
        }
        guard !accountSignals.isEmpty else {
            return .single([])
        }
        return combineLatest(accountSignals)
        |> map { values -> [ShadowActiveAccount] in
            return values.compactMap { $0 }.sorted { lhs, rhs in
                if lhs.isCurrent != rhs.isCurrent {
                    return lhs.isCurrent
                }
                return lhs.sortOrder < rhs.sortOrder
            }
        }
    }
}

func shadowHiddenAccountsController(context: AccountContext) -> ViewController {
    let arguments = ShadowHiddenAccountsArguments(updateHidden: { peerId, value in
        ShadowHiddenAccounts.setHidden(value, peerId: peerId)
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        shadowActiveAccounts(context: context),
        ShadowHiddenAccounts.signal()
    )
    |> deliverOnMainQueue
    |> map { presentationData, accounts, hiddenIds -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [ShadowHiddenAccountsEntry] = []
        var index: Int32 = 0
        for account in accounts {
            let peerId = account.context.account.peerId
            entries.append(.account(index, peerId, account.peer.compactDisplayTitle, account.isCurrent, hiddenIds.contains(peerId.toInt64())))
            index += 1
        }
        entries.append(.info)

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Скрытые аккаунты"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}

// MARK: - Синхронизация аккаунтов (ShadowSettingsSync)

private enum ShadowSettingsSyncSection: Int32 {
    case accounts
    case info
    case banners
}

private final class ShadowSettingsSyncArguments {
    let updateSynced: (Int64, Bool) -> Void
    var updateBanners: (Bool) -> Void = { _ in }

    init(updateSynced: @escaping (Int64, Bool) -> Void) {
        self.updateSynced = updateSynced
    }
}

private enum ShadowSettingsSyncEntry: ItemListNodeEntry {
    case header
    case account(Int32, Int64, String, Bool, Bool)
    case info
    case banners(Bool)
    case bannersFooter

    var section: ItemListSectionId {
        switch self {
        case .header, .account:
            return ShadowSettingsSyncSection.accounts.rawValue
        case .info:
            return ShadowSettingsSyncSection.info.rawValue
        case .banners, .bannersFooter:
            return ShadowSettingsSyncSection.banners.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .banners:
            return 20_000
        case .bannersFooter:
            return 20_001
        case .header:
            return -1
        case let .account(index, _, _, _, _):
            return index
        case .info:
            return 10_000
        }
    }

    static func <(lhs: ShadowSettingsSyncEntry, rhs: ShadowSettingsSyncEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ShadowSettingsSyncArguments
        switch self {
        case .header:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "СИНХРОНИЗИРОВАТЬ НАСТРОЙКИ SHADOW", sectionId: self.section)
        case let .account(_, peerId, title, isCurrent, isSynced):
            let suffix = isCurrent ? " · текущий" : ""
            return ItemListCheckboxItem(presentationData: presentationData, title: "\(title)\(suffix)", style: .left, checked: isSynced, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.updateSynced(peerId, !isSynced)
            })
        case .info:
            return ItemListTextItem(presentationData: presentationData, text: .plain("У отмеченных аккаунтов все настройки Shadow одинаковые: изменение на одном сразу повторяется на остальных. При включении настройки текущего аккаунта копируются на все отмеченные — их прежние настройки заменятся. Работает только на этом устройстве."), sectionId: self.section)
        case let .banners(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Синхронизировать баннеры", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateBanners(value)
            })
        case .bannersFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Картинка над списком чатов и фон профиля/настроек тоже станут общими. Выключите, чтобы на аккаунтах были разные картинки."), sectionId: self.section)
        }
    }
}

func shadowSettingsSyncController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?
    var latestAccounts: [ShadowActiveAccount] = []
    let currentPeerId = context.account.peerId.toInt64()

    let arguments = ShadowSettingsSyncArguments(updateSynced: { peerId, value in
        var ids = ShadowSettingsSync.ids()
        guard value else {
            ids.remove(peerId)
            ShadowSettingsSync.setIds(ids)
            return
        }
        // The current account's settings become the group's settings.
        var updatedIds = ids
        updatedIds.insert(peerId)
        updatedIds.insert(currentPeerId)
        let targets = latestAccounts.filter { account in
            let id = account.context.account.peerId.toInt64()
            return id != currentPeerId && updatedIds.contains(id)
        }
        let apply: () -> Void = {
            let _ = (shadowStoredAyuGramSettingsOnce(postbox: context.account.postbox)
            |> mapToSignal { source -> Signal<Never, NoError> in
                var writes: Signal<Never, NoError> = .complete()
                for target in targets {
                    writes = writes |> then(shadowApplySyncedAyuGramSettings(source, to: target.context.account.postbox))
                }
                return writes
            }
            |> deliverOnMainQueue).startStandalone(completed: {
                if ShadowSettingsSync.syncBanners {
                    let source = context.account.postbox.mediaBox.basePath
                    for target in targets {
                        AyuSavedMedia.copyBanners(fromBasePath: source, toBasePath: target.context.account.postbox.mediaBox.basePath)
                    }
                }
                ShadowSettingsSync.setIds(updatedIds)
            })
        }
        if targets.isEmpty {
            ShadowSettingsSync.setIds(updatedIds)
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let names = targets.map { $0.peer.compactDisplayTitle }.joined(separator: ", ")
        presentControllerImpl?(textAlertController(context: context, title: "Синхронизировать?", text: "Настройки Shadow на аккаунтах \(names) заменятся настройками текущего аккаунта. Дальше изменения будут общими.", actions: [
            TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
            TextAlertAction(type: .defaultAction, title: "Синхронизировать", action: {
                apply()
            })
        ]))
    })

    arguments.updateBanners = { value in
        ShadowSettingsSync.setSyncBanners(value)
        // Turning it on: the current account's images become everyone's.
        if value {
            let ids = ShadowSettingsSync.ids()
            let currentId = context.account.peerId.toInt64()
            guard ids.contains(currentId) else {
                return
            }
            let source = context.account.postbox.mediaBox.basePath
            for account in latestAccounts where ids.contains(account.context.account.peerId.toInt64()) {
                AyuSavedMedia.copyBanners(fromBasePath: source, toBasePath: account.context.account.postbox.mediaBox.basePath)
            }
        }
    }

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        shadowActiveAccounts(context: context),
        ShadowSettingsSync.signal(),
        ShadowSettingsSync.syncBannersSignal()
    )
    |> deliverOnMainQueue
    |> map { presentationData, accounts, syncedIds, syncBanners -> (ItemListControllerState, (ItemListNodeState, Any)) in
        latestAccounts = accounts
        var entries: [ShadowSettingsSyncEntry] = [.header]
        var index: Int32 = 0
        for account in accounts {
            let peerId = account.context.account.peerId.toInt64()
            entries.append(.account(index, peerId, account.peer.compactDisplayTitle, account.isCurrent, syncedIds.contains(peerId)))
            index += 1
        }
        entries.append(.info)
        entries.append(.banners(syncBanners))
        entries.append(.bannersFooter)

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Синхронизация аккаунтов"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}

// A small shared helper for the sub-controllers.
private func ayuUpdateSettings(context: AccountContext, _ f: @escaping (AyuGramSettings) -> AyuGramSettings) {
    let _ = updateAyuGramSettings(postbox: context.account.postbox, { current in
        return f(current)
    }).start()
}

// MARK: - Кастомизация

private final class AyuCustomizationArguments {
    var openMessageScreenshot: () -> Void = {}
    var openHeaderButtons: () -> Void = {}
    var selectVoiceTimeFormat: () -> Void = {}
    var updateSetting: (@escaping (inout AyuGramSettings) -> Void) -> Void = { _ in }
    // true: background color, false: glyph color.
    var pickSettingsIconColor: (Bool) -> Void = { _ in }
    var updatePreferUsernameForNonContacts: (Bool) -> Void = { _ in }
    var updatePreferUsernameForBots: (Bool) -> Void = { _ in }
    let updateShowMessageSeconds: (Bool) -> Void
    let updateEditedIndicatorAsPencil: (Bool) -> Void
    let updateEditedIndicatorText: (String) -> Void
    let updateDeletedIndicatorText: (String) -> Void
    let updateRegularEmojiFirst: (Bool) -> Void
    let updateDoubleTapToEdit: (Bool) -> Void
    let updateShowExactLastSeen: (Bool) -> Void
    let updateShowExactLastSeenSeconds: (Bool) -> Void
    let updateWideChannelPosts: (Bool) -> Void
    let updateShowExactViewCounts: (Bool) -> Void
    let updateShowForwardCount: (Bool) -> Void
    let updateRoundVideoBackCamera: (Bool) -> Void
    let updateCustomVideoMessageSpeed: (Bool) -> Void
    let updateShowCameraTile: (Bool) -> Void
    let updateCameraTileLivePreview: (Bool) -> Void
    let updateConfirmCalls: (Bool) -> Void
    let updateHideAllChatsFolder: (Bool) -> Void
    let updateFoldersAtBottom: (Bool) -> Void
    let updateHideBottomSearch: (Bool) -> Void
    let updateCompactBottomBar: (Bool) -> Void
    let selectBottomBarScrollMode: () -> Void
    let updateShowProfileId: (Bool) -> Void
    let updateShowProfileDC: (Bool) -> Void
    let updateShowRegistrationDate: (Bool) -> Void
    let updateHideOwnPhoneNumber: (Bool) -> Void
    let syncGitConfig: () -> Void
    let updateCustomBanner: (Bool) -> Void
    let chooseBanner: () -> Void
    let updateCustomProfileBackground: (Bool) -> Void
    let updateCustomProfileBackgroundForOthers: (Bool) -> Void
    let updateCustomProfileBackgroundForSettings: (Bool) -> Void
    let chooseProfileBackground: () -> Void

    init(
        updateShowMessageSeconds: @escaping (Bool) -> Void,
        updateEditedIndicatorAsPencil: @escaping (Bool) -> Void,
        updateEditedIndicatorText: @escaping (String) -> Void,
        updateDeletedIndicatorText: @escaping (String) -> Void,
        updateRegularEmojiFirst: @escaping (Bool) -> Void,
        updateDoubleTapToEdit: @escaping (Bool) -> Void,
        updateShowExactLastSeen: @escaping (Bool) -> Void,
        updateShowExactLastSeenSeconds: @escaping (Bool) -> Void,
        updateWideChannelPosts: @escaping (Bool) -> Void,
        updateShowExactViewCounts: @escaping (Bool) -> Void,
        updateShowForwardCount: @escaping (Bool) -> Void,
        updateRoundVideoBackCamera: @escaping (Bool) -> Void,
        updateCustomVideoMessageSpeed: @escaping (Bool) -> Void,
        updateShowCameraTile: @escaping (Bool) -> Void,
        updateCameraTileLivePreview: @escaping (Bool) -> Void,
        updateConfirmCalls: @escaping (Bool) -> Void,
        updateHideAllChatsFolder: @escaping (Bool) -> Void,
        updateFoldersAtBottom: @escaping (Bool) -> Void,
        updateHideBottomSearch: @escaping (Bool) -> Void,
        updateCompactBottomBar: @escaping (Bool) -> Void,
        selectBottomBarScrollMode: @escaping () -> Void,
        updateShowProfileId: @escaping (Bool) -> Void,
        updateShowProfileDC: @escaping (Bool) -> Void,
        updateShowRegistrationDate: @escaping (Bool) -> Void,
        updateHideOwnPhoneNumber: @escaping (Bool) -> Void,
        syncGitConfig: @escaping () -> Void,
        updateCustomBanner: @escaping (Bool) -> Void,
        chooseBanner: @escaping () -> Void,
        updateCustomProfileBackground: @escaping (Bool) -> Void,
        updateCustomProfileBackgroundForOthers: @escaping (Bool) -> Void,
        updateCustomProfileBackgroundForSettings: @escaping (Bool) -> Void,
        chooseProfileBackground: @escaping () -> Void
    ) {
        self.updateShowMessageSeconds = updateShowMessageSeconds
        self.updateEditedIndicatorAsPencil = updateEditedIndicatorAsPencil
        self.updateEditedIndicatorText = updateEditedIndicatorText
        self.updateDeletedIndicatorText = updateDeletedIndicatorText
        self.updateRegularEmojiFirst = updateRegularEmojiFirst
        self.updateDoubleTapToEdit = updateDoubleTapToEdit
        self.updateShowExactLastSeen = updateShowExactLastSeen
        self.updateShowExactLastSeenSeconds = updateShowExactLastSeenSeconds
        self.updateWideChannelPosts = updateWideChannelPosts
        self.updateShowExactViewCounts = updateShowExactViewCounts
        self.updateShowForwardCount = updateShowForwardCount
        self.updateRoundVideoBackCamera = updateRoundVideoBackCamera
        self.updateCustomVideoMessageSpeed = updateCustomVideoMessageSpeed
        self.updateShowCameraTile = updateShowCameraTile
        self.updateCameraTileLivePreview = updateCameraTileLivePreview
        self.updateConfirmCalls = updateConfirmCalls
        self.updateHideAllChatsFolder = updateHideAllChatsFolder
        self.updateFoldersAtBottom = updateFoldersAtBottom
        self.updateHideBottomSearch = updateHideBottomSearch
        self.updateCompactBottomBar = updateCompactBottomBar
        self.selectBottomBarScrollMode = selectBottomBarScrollMode
        self.updateShowProfileId = updateShowProfileId
        self.updateShowProfileDC = updateShowProfileDC
        self.updateShowRegistrationDate = updateShowRegistrationDate
        self.updateHideOwnPhoneNumber = updateHideOwnPhoneNumber
        self.syncGitConfig = syncGitConfig
        self.updateCustomBanner = updateCustomBanner
        self.chooseBanner = chooseBanner
        self.updateCustomProfileBackground = updateCustomProfileBackground
        self.updateCustomProfileBackgroundForOthers = updateCustomProfileBackgroundForOthers
        self.updateCustomProfileBackgroundForSettings = updateCustomProfileBackgroundForSettings
        self.chooseProfileBackground = chooseProfileBackground
    }
}

private enum AyuCustomizationSection: Int32 {
    case buildInfo
    case appearance
    case chats
    case bottomBar
    case profiles
    case media
    case customRoundVideos
    case calls
    case githubConfig
    case banner
    case profileBackground
    case settingsIcons
}

private enum AyuCustomizationEntry: ItemListNodeEntry {
    // Shadow: shown at the very top so a build can always be identified from
    // inside the app — this session's repeated "which build is this" confusion
    // (a compile error meant an earlier push never actually produced an
    // installable IPA, but there was no way to tell from the device alone)
    // is exactly what this is for. CFBundleVersion here is the exact commit-
    // count-based BUILD_NUMBER the CI workflow already stamps into the IPA
    // (same number the Telegram/Discord "Сборка готова" notification prints),
    // so no new build-system wiring is needed — just surfacing existing data.
    case buildInfo
    case appearanceHeader
    case messageScreenshot
    case headerButtons(String)
    case preferUsernameForNonContacts(Bool)
    case preferUsernameForBots(Bool)
    case showMessageSeconds(Bool)
    case editedIndicatorAsPencil(Bool)
    case editedIndicatorText(String)
    case deletedIndicatorText(String)
    case regularEmojiFirst(Bool)
    case doubleTapToEdit(Bool)
    case showExactLastSeen(Bool)
    case showExactLastSeenSeconds(Bool)
    case wideChannelPosts(Bool)
    case showExactViewCounts(Bool)
    case showForwardCount(Bool)
    case appearanceFooter

    case settingsIconsHeader
    case monochromeSettingsIcons(Bool)
    case settingsIconBackground(Int32)
    case settingsIconGlyph(Int32)
    case settingsIconsFooter

    case chatsHeader
    case hideAllChatsFolder(Bool)
    case hideStoriesBar(Bool)
    case hideGiftButton(Bool)
    case hideGreetingSticker(Bool)
    case hidePremiumBadges(Bool)
    case hideSponsoredMessages(Bool)
    case unlimitedPinnedChats(Bool)
    case compactChatList(Bool)
    case localVoiceTranscription(Bool)
    case voiceTimeFormat(Int32)
    case voiceTimeRoundVideos(Bool)
    case voiceTimeInPlayer(Bool)
    case chatsFooter

    case bottomBarHeader
    case foldersAtBottom(Bool)
    case hideBottomSearch(Bool)
    case compactBottomBar(Bool)
    case bottomBarScrollMode(Int32)
    case bottomBarFooter

    case profilesHeader
    case showProfileId(Bool)
    case showProfileDC(Bool)
    case showRegistrationDate(Bool)
    case hideOwnPhoneNumber(Bool)
    case profilesFooter

    case mediaHeader
    case roundVideoBackCamera(Bool)
    case showCameraTile(Bool)
    case cameraTileLivePreview(Bool)
    case cameraTileCompact(Bool)
    case mediaFooter

    case customRoundVideosHeader
    case customVideoMessageSpeed(Bool)
    case customRoundVideosFooter

    case callsHeader
    case confirmCalls(Bool)
    case callsFooter

    case githubConfigHeader
    case syncGithub
    case githubConfigFooter

    case bannerHeader
    case customBanner(Bool)
    case bannerChoose
    case bannerFooter

    case profileBackgroundHeader
    case customProfileBackground(Bool)
    case customProfileBackgroundForOthers(Bool)
    case customProfileBackgroundForSettings(Bool)
    case profileBackgroundChoose
    case profileBackgroundFooter

    var section: ItemListSectionId {
        switch self {
        case .messageScreenshot: return AyuCustomizationSection.appearance.rawValue
        case .preferUsernameForNonContacts, .preferUsernameForBots: return AyuCustomizationSection.appearance.rawValue
        case .buildInfo:
            return AyuCustomizationSection.buildInfo.rawValue
        case .settingsIconsHeader, .monochromeSettingsIcons, .settingsIconBackground, .settingsIconGlyph, .settingsIconsFooter:
            return AyuCustomizationSection.settingsIcons.rawValue
        case .appearanceHeader, .showMessageSeconds, .editedIndicatorAsPencil, .editedIndicatorText, .deletedIndicatorText, .regularEmojiFirst, .doubleTapToEdit, .showExactLastSeen, .showExactLastSeenSeconds, .wideChannelPosts, .showExactViewCounts, .showForwardCount, .appearanceFooter:
            return AyuCustomizationSection.appearance.rawValue
        case .headerButtons: return AyuCustomizationSection.chats.rawValue
        case .chatsHeader, .hideAllChatsFolder, .hideStoriesBar, .hideGiftButton, .hideGreetingSticker, .hidePremiumBadges, .hideSponsoredMessages, .unlimitedPinnedChats, .compactChatList, .chatsFooter:
            return AyuCustomizationSection.chats.rawValue
        case .bottomBarHeader, .foldersAtBottom, .hideBottomSearch, .compactBottomBar, .bottomBarScrollMode, .bottomBarFooter:
            return AyuCustomizationSection.bottomBar.rawValue
        case .profilesHeader, .showProfileId, .showProfileDC, .showRegistrationDate, .hideOwnPhoneNumber, .profilesFooter:
            return AyuCustomizationSection.profiles.rawValue
        case .mediaHeader, .roundVideoBackCamera, .showCameraTile, .cameraTileLivePreview, .cameraTileCompact, .localVoiceTranscription, .voiceTimeFormat, .voiceTimeRoundVideos, .voiceTimeInPlayer, .mediaFooter:
            return AyuCustomizationSection.media.rawValue
        case .customRoundVideosHeader, .customVideoMessageSpeed, .customRoundVideosFooter:
            return AyuCustomizationSection.customRoundVideos.rawValue
        case .callsHeader, .confirmCalls, .callsFooter:
            return AyuCustomizationSection.calls.rawValue
        case .githubConfigHeader, .syncGithub, .githubConfigFooter:
            return AyuCustomizationSection.githubConfig.rawValue
        case .bannerHeader, .customBanner, .bannerChoose, .bannerFooter:
            return AyuCustomizationSection.banner.rawValue
        case .profileBackgroundHeader, .customProfileBackground, .customProfileBackgroundForOthers, .customProfileBackgroundForSettings, .profileBackgroundChoose, .profileBackgroundFooter:
            return AyuCustomizationSection.profileBackground.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .messageScreenshot: return 93
        case .headerButtons: return 111
        case .preferUsernameForNonContacts: return 94
        case .preferUsernameForBots: return 95
        case .buildInfo: return -1
        case .appearanceHeader: return 0
        case .showMessageSeconds: return 1
        case .editedIndicatorAsPencil: return 2
        case .editedIndicatorText: return 90
        case .deletedIndicatorText: return 91
        case .regularEmojiFirst: return 3
        case .doubleTapToEdit: return 4
        case .showExactLastSeen: return 5
        case .showExactLastSeenSeconds: return 6
        case .wideChannelPosts: return 7
        case .showExactViewCounts: return 8
        case .showForwardCount: return 9
        case .appearanceFooter: return 10
        case .chatsHeader: return 11
        case .hideAllChatsFolder: return 12
        case .chatsFooter: return 13
        case .hideStoriesBar: return 99
        case .hideGiftButton: return 100
        case .hideGreetingSticker: return 116
        case .hidePremiumBadges: return 101
        case .hideSponsoredMessages: return 102
        case .localVoiceTranscription: return 103
        case .voiceTimeFormat: return 112
        case .voiceTimeRoundVideos: return 113
        case .voiceTimeInPlayer: return 114
        case .unlimitedPinnedChats: return 104
        case .settingsIconsHeader: return 105
        case .compactChatList: return 110
        case .monochromeSettingsIcons: return 106
        case .settingsIconBackground: return 107
        case .settingsIconGlyph: return 108
        case .settingsIconsFooter: return 109
        case .bottomBarHeader: return 14
        case .foldersAtBottom: return 15
        case .hideBottomSearch: return 16
        case .compactBottomBar: return 17
        case .bottomBarScrollMode: return 92
        case .bottomBarFooter: return 18
        case .profilesHeader: return 19
        case .showProfileId: return 20
        case .showProfileDC: return 21
        case .showRegistrationDate: return 22
        case .hideOwnPhoneNumber: return 23
        case .profilesFooter: return 24
        case .mediaHeader: return 25
        case .roundVideoBackCamera: return 26
        case .showCameraTile: return 27
        case .cameraTileLivePreview: return 28
        case .cameraTileCompact: return 115
        case .mediaFooter: return 29
        case .customRoundVideosHeader: return 96
        case .customVideoMessageSpeed: return 97
        case .customRoundVideosFooter: return 98
        case .callsHeader: return 30
        case .confirmCalls: return 31
        case .callsFooter: return 32
        case .githubConfigHeader: return 33
        case .syncGithub: return 34
        case .githubConfigFooter: return 35
        case .bannerHeader: return 36
        case .customBanner: return 37
        case .bannerChoose: return 38
        case .bannerFooter: return 39
        case .profileBackgroundHeader: return 40
        case .customProfileBackground: return 41
        case .customProfileBackgroundForOthers: return 42
        case .customProfileBackgroundForSettings: return 43
        case .profileBackgroundChoose: return 44
        case .profileBackgroundFooter: return 45
        }
    }

    private var sortKey: (Int32, Int) {
        switch self {
        case .messageScreenshot: return (9, 1)
        case .headerButtons: return (11, 1)
        case .preferUsernameForNonContacts: return (9, 2)
        case .preferUsernameForBots: return (9, 3)
        case .editedIndicatorText: return (2, 1)
        case .deletedIndicatorText: return (2, 2)
        case .bottomBarScrollMode: return (17, 1)
        case .hideStoriesBar: return (12, 1)
        case .hideGiftButton: return (12, 2)
        case .hidePremiumBadges: return (12, 3)
        case .hideSponsoredMessages: return (12, 4)
        case .unlimitedPinnedChats: return (12, 5)
        case .compactChatList: return (12, 6)
        case .hideGreetingSticker: return (12, 7)
        case .cameraTileCompact: return (28, 1)
        case .localVoiceTranscription: return (28, 2)
        case .voiceTimeFormat: return (28, 3)
        case .voiceTimeRoundVideos: return (28, 4)
        case .voiceTimeInPlayer: return (28, 5)
        // After the media section (mediaFooter = 29), in display order.
        case .customRoundVideosHeader: return (29, 1)
        case .customVideoMessageSpeed: return (29, 2)
        case .customRoundVideosFooter: return (29, 3)
        case .bannerHeader: return (29, 4)
        case .customBanner: return (29, 5)
        case .bannerChoose: return (29, 6)
        case .bannerFooter: return (29, 7)
        case .profileBackgroundHeader: return (29, 8)
        case .customProfileBackground: return (29, 9)
        case .customProfileBackgroundForOthers: return (29, 10)
        case .customProfileBackgroundForSettings: return (29, 11)
        case .profileBackgroundChoose: return (29, 12)
        case .profileBackgroundFooter: return (29, 13)
        case .callsHeader: return (29, 14)
        case .confirmCalls: return (29, 15)
        case .callsFooter: return (29, 16)
        case .githubConfigHeader: return (29, 17)
        case .syncGithub: return (29, 18)
        case .githubConfigFooter: return (29, 19)
        // Right after the appearance section.
        case .settingsIconsHeader: return (10, 1)
        case .monochromeSettingsIcons: return (10, 2)
        case .settingsIconBackground: return (10, 3)
        case .settingsIconGlyph: return (10, 4)
        case .settingsIconsFooter: return (10, 5)
        default: return (self.stableId, 0)
        }
    }

    static func <(lhs: AyuCustomizationEntry, rhs: AyuCustomizationEntry) -> Bool {
        // Stable IDs do not encode insertion order for later-added controls.
        return lhs.sortKey < rhs.sortKey
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AyuCustomizationArguments
        switch self {
        case .messageScreenshot:
            return ItemListDisclosureItem(presentationData: presentationData, title: "Скриншоты сообщений", label: "", sectionId: self.section, style: .blocks, action: arguments.openMessageScreenshot)
        case let .headerButtons(label):
            return ItemListDisclosureItem(presentationData: presentationData, title: "Кнопки шапки", label: label, sectionId: self.section, style: .blocks, action: arguments.openHeaderButtons)
        case let .preferUsernameForNonContacts(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "@username вместо имени незнакомых", value: value, sectionId: self.section, style: .blocks, updated: arguments.updatePreferUsernameForNonContacts)
        case let .preferUsernameForBots(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Также для ботов", value: value, sectionId: self.section, style: .blocks, updated: arguments.updatePreferUsernameForBots)
        case let .bottomBarScrollMode(mode):
            return ItemListDisclosureItem(presentationData: presentationData, title: "Скрытие нижней панели", label: shadowBottomBarScrollLabel(mode), labelStyle: .detailText, sectionId: self.section, style: .blocks, action: arguments.selectBottomBarScrollMode)
        case .buildInfo:
            let bundle = Bundle.main
            let bundleVersion = (bundle.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
            let bundleBuild = (bundle.infoDictionary?[kCFBundleVersionKey as String] as? String) ?? ""
            return ItemListTextItem(presentationData: presentationData, text: .plain("Shadow \(bundleVersion) (build \(bundleBuild))"), sectionId: self.section)
        case .appearanceHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ОФОРМЛЕНИЕ", sectionId: self.section)
        case let .showMessageSeconds(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Секунды в метках времени", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateShowMessageSeconds(value)
            })
        case let .editedIndicatorAsPencil(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Значок ✎ вместо «Изменено»", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateEditedIndicatorAsPencil(value)
            })
        case let .editedIndicatorText(value):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(string: "Свой значок правки", textColor: presentationData.theme.list.itemPrimaryTextColor), text: value, placeholder: "По умолчанию: ✎", type: .regular(capitalization: false, autocorrection: false), spacing: 8.0, clearType: .always, sectionId: self.section, textUpdated: { updatedText in
                arguments.updateEditedIndicatorText(updatedText)
            }, action: {})
        case let .deletedIndicatorText(value):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(string: "Свой значок удалёнки", textColor: presentationData.theme.list.itemPrimaryTextColor), text: value, placeholder: "По умолчанию: 🗑", type: .regular(capitalization: false, autocorrection: false), spacing: 8.0, clearType: .always, sectionId: self.section, textUpdated: { updatedText in
                arguments.updateDeletedIndicatorText(updatedText)
            }, action: {})
        case let .regularEmojiFirst(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Обычные эмодзи в начале клавиатуры", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateRegularEmojiFirst(value)
            })
        case let .doubleTapToEdit(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Двойной тап — редактирование", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateDoubleTapToEdit(value)
            })
        case let .showExactLastSeen(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Точное время последнего захода", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateShowExactLastSeen(value)
            })
        case let .showExactLastSeenSeconds(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Секунды у последнего захода", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateShowExactLastSeenSeconds(value)
            })
        case let .wideChannelPosts(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Широкие посты в каналах", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateWideChannelPosts(value)
            })
        case let .showExactViewCounts(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Точные просмотры на постах", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateShowExactViewCounts(value)
            })
        case let .showForwardCount(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Счётчик пересылок", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateShowForwardCount(value)
            })
        case .appearanceFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("«Секунды в метках времени» показывают ЧЧ:ММ:СС вместо ЧЧ:ММ. «Двойной тап — редактирование» открывает редактирование при двойном нажатии на своё сообщение. «Точное время последнего захода» вместо «был в сети час назад» показывает точное время, например «был в сети сегодня в 12:10»; дополнительный переключатель «Секунды у последнего захода» добавляет к нему секунды («12:10:12»). «Широкие посты в каналах» отображают сообщения каналов на увеличенную ширину — удобно для длинных постов и статей. Влияет только на каналы: личные чаты и группы не меняются. «Точные просмотры на постах» показывают полное число просмотров (5678) вместо сокращённого (5.6K). «Счётчик пересылок» показывает рядом со временем, сколько раз сообщение переслали (приходит только для постов в каналах, как и просмотры)."), sectionId: self.section)
        case .chatsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ЧАТЫ", sectionId: self.section)
        case let .hideAllChatsFolder(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Скрыть папку «Все чаты»", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateHideAllChatsFolder(value)
            })
        case .settingsIconsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ИКОНКИ НАСТРОЕК", sectionId: self.section)
        case let .monochromeSettingsIcons(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Одноцветные иконки", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSetting { $0.monochromeSettingsIcons = value }
            })
        case let .settingsIconBackground(color):
            return ItemListDisclosureItem(presentationData: presentationData, title: "Цвет фона", label: shadowHexColorString(color), sectionId: self.section, style: .blocks, action: {
                arguments.pickSettingsIconColor(true)
            })
        case let .settingsIconGlyph(color):
            return ItemListDisclosureItem(presentationData: presentationData, title: "Цвет значка", label: shadowHexColorString(color), sectionId: self.section, style: .blocks, action: {
                arguments.pickSettingsIconColor(false)
            })
        case .settingsIconsFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Как тонированные иконки iOS: все иконки в настройках Telegram и Shadow получают один цвет фона и один цвет значка. Например, тёмно-серый фон и белый значок. Иконки мини-приложений не меняются."), sectionId: self.section)
        case let .hideStoriesBar(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Скрыть истории", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSetting { $0.hideStoriesBar = value }
            })
        case let .hideGreetingSticker(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Скрыть приветственный стикер", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSetting { $0.hideGreetingSticker = value }
            })
        case let .hideGiftButton(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Скрыть кнопку подарка", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSetting { $0.hideGiftButton = value }
            })
        case let .hidePremiumBadges(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Скрыть значки Premium у имён", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSetting { $0.hidePremiumBadges = value }
            })
        case let .hideSponsoredMessages(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Скрыть рекламу в каналах", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSetting { $0.hideSponsoredMessages = value }
            })
        case let .unlimitedPinnedChats(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Безлимитные закрепы", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSetting { $0.unlimitedPinnedChats = value }
            })
        case let .compactChatList(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Компактный список чатов", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSetting { $0.compactChatList = value }
            })
        case let .localVoiceTranscription(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Расшифровка голосовых на устройстве", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSetting { $0.localVoiceTranscription = value }
            })
        case let .voiceTimeFormat(format):
            return ItemListDisclosureItem(presentationData: presentationData, title: "Время на голосовых", label: ShadowVoiceTime.title(format), labelStyle: .detailText, sectionId: self.section, style: .blocks, action: arguments.selectVoiceTimeFormat)
        case let .voiceTimeRoundVideos(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Также на кружках", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSetting { $0.voiceTimeRoundVideos = value }
            })
        case let .voiceTimeInPlayer(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Время в верхнем плеере", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSetting { $0.voiceTimeInPlayer = value }
            })
        case .chatsFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("«Скрыть папку «Все чаты»» убирает эту вкладку, остальные папки работают. «Скрыть истории» убирает ленту историй над списком чатов. «Скрыть кнопку подарка» убирает подарок из поля ввода. «Скрыть приветственный стикер» убирает карточку со стикером в пустом чате с незнакомым. «Скрыть значки Premium» убирает звёздочку и эмодзи-статус рядом с именами (галочки верификации остаются). «Скрыть рекламу в каналах» — спонсорские сообщения не загружаются; применяется при следующем открытии канала. «Безлимитные закрепы» снимают ограничение на закрепы в списке чатов, архиве, папках, «Избранном» и темах форумов; всё сверх лимита Telegram хранится только на этом устройстве."), sectionId: self.section)
        case .bottomBarHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "НИЖНИЙ ИНТЕРФЕЙС", sectionId: self.section)
        case let .foldersAtBottom(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Папки снизу", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateFoldersAtBottom(value)
            })
        case let .hideBottomSearch(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Убрать поиск снизу", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateHideBottomSearch(value)
            })
        case let .compactBottomBar(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Уменьшить интерфейс снизу", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateCompactBottomBar(value)
            })
        case .bottomBarFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("«Папки снизу» показывают папки чатов над нижней панелью. «Убрать поиск снизу» скрывает нижнюю кнопку поиска, чтобы поиск не дублировался (верхняя строка поиска не затрагивается). «Уменьшить интерфейс снизу» делает нижнюю панель компактнее. Все три переключателя работают независимо. Режим «Скрывать при прокрутке вверх и вниз» возвращает панель после полной остановки списка, включая инерцию."), sectionId: self.section)
        case .profilesHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ПРОФИЛЬ", sectionId: self.section)
        case let .showProfileId(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "ID профиля (Bot API)", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateShowProfileId(value)
            })
        case let .showProfileDC(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Дата-центр (DC)", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateShowProfileDC(value)
            })
        case let .showRegistrationDate(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Дата регистрации", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateShowRegistrationDate(value)
            })
        case let .hideOwnPhoneNumber(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Скрыть свой номер", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateHideOwnPhoneNumber(value)
            })
        case .profilesFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Показывать в профилях пользователей, ботов и каналов дополнительные поля: числовой ID (в формате Bot API, копируется по удержанию), дата-центр фото профиля и примерную дату регистрации. Дата регистрации приблизительная — Telegram не раскрывает точную.\n\n«Скрыть свой номер» полностью убирает плашку с вашим номером телефона в настройках/профиле."), sectionId: self.section)
        case .mediaHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "МЕДИА", sectionId: self.section)
        case let .roundVideoBackCamera(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Кружки на заднюю камеру", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateRoundVideoBackCamera(value)
            })
        case let .showCameraTile(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Камера в галерее", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateShowCameraTile(value)
            })
        case let .cameraTileLivePreview(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Живой предпросмотр камеры", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateCameraTileLivePreview(value)
            })
        case let .cameraTileCompact(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Компактная плитка камеры", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSetting { $0.cameraTileCompact = value }
            })
        case .mediaFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Начинать запись видеосообщений («кружков») с задней камеры. Во время записи можно переключиться на фронтальную. «Камера в галерее» показывает плитку камеры первой ячейкой в галерее вложений. «Живой предпросмотр камеры» запускает в этой плитке видео с камеры вживую вместо статичной иконки. «Компактная плитка камеры» занимает одну ячейку вместо двух — в первом ряду видно больше медиа. «Расшифровка голосовых на устройстве» без Premium распознаёт речь прямо на телефоне — аудио никуда не отправляется. «Время на голосовых» меняет время под голосовым во время прослушивания: сколько осталось (как в Telegram), сколько прошло, «прошло / всего», «-осталось / всего» или процент; пока голосовое не играет, видна его длина. «Также на кружках» применяет тот же формат к видеосообщениям, «Время в верхнем плеере» добавляет его в полоску плеера над чатом."), sectionId: self.section)
        case .customRoundVideosHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "КАСТОМНЫЕ КРУЖКИ", sectionId: self.section)
        case let .customVideoMessageSpeed(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Кастомная скорость кружков", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateCustomVideoMessageSpeed(value)
            })
        case .customRoundVideosFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("После записи кружка появится кнопка скорости: от 0.5× до 3×. Меняет видео и звук перед отправкой."), sectionId: self.section)
        case .callsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ЗВОНКИ", sectionId: self.section)
        case let .confirmCalls(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Подтверждение звонков", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateConfirmCalls(value)
            })
        case .callsFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Перед аудио- или видеозвонком запрашивать подтверждение — защита от случайного нажатия. Не влияет на входящие звонки."), sectionId: self.section)
        case .githubConfigHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ЗНАЧКИ", sectionId: self.section)
        case .syncGithub:
            return ItemListActionItem(presentationData: presentationData, title: "Синхронизировать с GitHub", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.syncGitConfig()
            })
        case .githubConfigFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Значки профилей и каналов из GitHub. Обновляются сами при запуске, кнопка — сразу."), sectionId: self.section)
        case .bannerHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "БАННЕР", sectionId: self.section)
        case let .customBanner(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Кастомный баннер", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateCustomBanner(value)
            })
        case .bannerChoose:
            return ItemListActionItem(presentationData: presentationData, title: "Выбрать изображение", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.chooseBanner()
            })
        case .bannerFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Отображает выбранное изображение как фон верхней части списка чатов (за историями, заголовком и поиском). Внизу баннера — затемнение для читаемости текста. Выключите переключатель, чтобы вернуть стандартный вид."), sectionId: self.section)
        case .profileBackgroundHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ФОН ПРОФИЛЯ", sectionId: self.section)
        case let .customProfileBackground(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Кастомный фон профиля", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateCustomProfileBackground(value)
            })
        case let .customProfileBackgroundForOthers(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Применять для всех профилей", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateCustomProfileBackgroundForOthers(value)
            })
        case let .customProfileBackgroundForSettings(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Применять в Settings", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateCustomProfileBackgroundForSettings(value)
            })
        case .profileBackgroundChoose:
            return ItemListActionItem(presentationData: presentationData, title: "Выбрать изображение", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.chooseProfileBackground()
            })
        case .profileBackgroundFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Отображает выбранное изображение как фон верхней части экрана «Мой профиль» (за аватаром и именем), с затемнением по всей области для читаемости и плавным переходом в обычный фон внизу. Работает только визуально в интерфейсе Shadow и видно только вам — другие пользователи и другие устройства видят обычный профиль. Заменяет собой стандартный цвет/эмодзи-статус профиля, если он у вас включён."), sectionId: self.section)
        }
    }
}

private func ayuCustomizationEntries(settings: AyuGramSettings) -> [AyuCustomizationEntry] {
    var entries: [AyuCustomizationEntry] = []

    entries.append(.buildInfo)
    entries.append(.appearanceHeader)
    entries.append(.showMessageSeconds(settings.showMessageSeconds))
    entries.append(.editedIndicatorAsPencil(settings.editedIndicatorAsPencil))
    entries.append(.editedIndicatorText(settings.editedIndicatorText))
    entries.append(.deletedIndicatorText(settings.deletedIndicatorText))
    entries.append(.regularEmojiFirst(settings.regularEmojiFirst))
    entries.append(.doubleTapToEdit(settings.doubleTapToEdit))
    entries.append(.showExactLastSeen(settings.showExactLastSeen))
    if settings.showExactLastSeen {
        entries.append(.showExactLastSeenSeconds(settings.showExactLastSeenSeconds))
    }
    entries.append(.wideChannelPosts(settings.wideChannelPosts))
    entries.append(.showExactViewCounts(settings.showExactViewCounts))
    entries.append(.showForwardCount(settings.showForwardCount))
    entries.append(.messageScreenshot)
    entries.append(.preferUsernameForNonContacts(settings.preferUsernameForNonContacts))
    if settings.preferUsernameForNonContacts {
        entries.append(.preferUsernameForBots(settings.preferUsernameForBots))
    }
    entries.append(.appearanceFooter)

    entries.append(.settingsIconsHeader)
    entries.append(.monochromeSettingsIcons(settings.monochromeSettingsIcons))
    if settings.monochromeSettingsIcons {
        entries.append(.settingsIconBackground(settings.settingsIconBackgroundColor))
        entries.append(.settingsIconGlyph(settings.settingsIconGlyphColor))
    }
    entries.append(.settingsIconsFooter)

    entries.append(.chatsHeader)
    entries.append(.headerButtons(settings.headerButtons.isStock ? "Стандартные" : "Свои"))
    entries.append(.hideAllChatsFolder(settings.hideAllChatsFolder))
    entries.append(.hideStoriesBar(settings.hideStoriesBar))
    entries.append(.hideGiftButton(settings.hideGiftButton))
    entries.append(.hidePremiumBadges(settings.hidePremiumBadges))
    entries.append(.hideSponsoredMessages(settings.hideSponsoredMessages))
    entries.append(.unlimitedPinnedChats(settings.unlimitedPinnedChats))
    entries.append(.compactChatList(settings.compactChatList))
    entries.append(.hideGreetingSticker(settings.hideGreetingSticker))
    entries.append(.chatsFooter)

    entries.append(.bottomBarHeader)
    entries.append(.foldersAtBottom(settings.foldersAtBottom))
    entries.append(.hideBottomSearch(settings.hideBottomSearch))
    entries.append(.compactBottomBar(settings.compactBottomBar))
    entries.append(.bottomBarScrollMode(settings.bottomBarScrollMode))
    entries.append(.bottomBarFooter)

    entries.append(.profilesHeader)
    entries.append(.showProfileId(settings.showProfileId))
    entries.append(.showProfileDC(settings.showProfileDC))
    entries.append(.showRegistrationDate(settings.showRegistrationDate))
    entries.append(.hideOwnPhoneNumber(settings.hideOwnPhoneNumber))
    entries.append(.profilesFooter)

    entries.append(.mediaHeader)
    entries.append(.roundVideoBackCamera(settings.roundVideoUseBackCamera))
    entries.append(.showCameraTile(settings.showCameraTile))
    entries.append(.cameraTileLivePreview(settings.cameraTileLivePreview))
    entries.append(.cameraTileCompact(settings.cameraTileCompact))
    entries.append(.localVoiceTranscription(settings.localVoiceTranscription))
    entries.append(.voiceTimeFormat(settings.voiceTimeFormat))
    entries.append(.voiceTimeRoundVideos(settings.voiceTimeRoundVideos))
    entries.append(.voiceTimeInPlayer(settings.voiceTimeInPlayer))
    entries.append(.mediaFooter)

    entries.append(.customRoundVideosHeader)
    entries.append(.customVideoMessageSpeed(settings.customVideoMessageSpeed))
    entries.append(.customRoundVideosFooter)

    entries.append(.bannerHeader)
    entries.append(.customBanner(settings.customBannerEnabled))
    if settings.customBannerEnabled {
        entries.append(.bannerChoose)
    }
    entries.append(.bannerFooter)

    entries.append(.profileBackgroundHeader)
    entries.append(.customProfileBackground(settings.customProfileBackgroundEnabled))
    if settings.customProfileBackgroundEnabled {
        entries.append(.customProfileBackgroundForOthers(settings.customProfileBackgroundForOthers))
        entries.append(.customProfileBackgroundForSettings(settings.customProfileBackgroundForSettings))
        entries.append(.profileBackgroundChoose)
    }
    entries.append(.profileBackgroundFooter)

    entries.append(.callsHeader)
    entries.append(.confirmCalls(settings.confirmCalls))
    entries.append(.callsFooter)

    // Shadow: the badge sync button is hidden; badges refresh by themselves on
    // launch (startGitConfigIfNeeded).

    return entries
}

func ayuCustomizationController(context: AccountContext, focus: ShadowSettingsSearchItem? = nil) -> ViewController {
    let linkRows = ShadowSettingsLinkRows()
    var focusedIndex: Int?
    var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?
    var presentBannerImagePickerImpl: (() -> Void)?
    var presentProfileBackgroundImagePickerImpl: (() -> Void)?

    let arguments = AyuCustomizationArguments(
        updateShowMessageSeconds: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.showMessageSeconds = value; return s }
        },
        updateEditedIndicatorAsPencil: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.editedIndicatorAsPencil = value; return s }
        },
        updateEditedIndicatorText: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.editedIndicatorText = value; return s }
        },
        updateDeletedIndicatorText: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.deletedIndicatorText = value; return s }
        },
        updateRegularEmojiFirst: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.regularEmojiFirst = value; return s }
        },
        updateDoubleTapToEdit: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.doubleTapToEdit = value; return s }
        },
        updateShowExactLastSeen: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.showExactLastSeen = value; return s }
        },
        updateShowExactLastSeenSeconds: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.showExactLastSeenSeconds = value; return s }
        },
        updateWideChannelPosts: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.wideChannelPosts = value; return s }
        },
        updateShowExactViewCounts: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.showExactViewCounts = value; return s }
        },
        updateShowForwardCount: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.showForwardCount = value; return s }
        },
        updateRoundVideoBackCamera: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.roundVideoUseBackCamera = value; return s }
        },
        updateCustomVideoMessageSpeed: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.customVideoMessageSpeed = value; return s }
        },
        updateShowCameraTile: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.showCameraTile = value; return s }
        },
        updateCameraTileLivePreview: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.cameraTileLivePreview = value; return s }
        },
        updateConfirmCalls: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.confirmCalls = value; return s }
        },
        updateHideAllChatsFolder: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.hideAllChatsFolder = value; return s }
        },
        updateFoldersAtBottom: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.foldersAtBottom = value; return s }
        },
        updateHideBottomSearch: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.hideBottomSearch = value; return s }
        },
        updateCompactBottomBar: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.compactBottomBar = value; return s }
        },
        selectBottomBarScrollMode: {
            let data = context.sharedContext.currentPresentationData.with { $0 }
            let sheet = ActionSheetController(presentationData: data)
            let items: [ActionSheetItem] = (0...3).map { mode in
                ActionSheetButtonItem(title: shadowBottomBarScrollLabel(Int32(mode)), action: { [weak sheet] in
                    sheet?.dismissAnimated()
                    ayuUpdateSettings(context: context) { var settings = $0; settings.bottomBarScrollMode = Int32(mode); return settings }
                })
            }
            sheet.setItemGroups([
                ActionSheetItemGroup(items: items),
                ActionSheetItemGroup(items: [ActionSheetButtonItem(title: data.strings.Common_Cancel, action: { [weak sheet] in sheet?.dismissAnimated() })])
            ])
            presentControllerImpl?(sheet, nil)
        },
        updateShowProfileId: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.showProfileId = value; return s }
        },
        updateShowProfileDC: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.showProfileDC = value; return s }
        },
        updateShowRegistrationDate: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.showRegistrationDate = value; return s }
        },
        updateHideOwnPhoneNumber: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.hideOwnPhoneNumber = value; return s }
        },
        syncGitConfig: {
            refreshGitConfig(completion: { success in
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                let text = success ? "Значки обновлены с GitHub." : "Не удалось связаться с GitHub. Попробуйте позже."
                presentControllerImpl?(textAlertController(context: context, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), nil)
            })
        },
        updateCustomBanner: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.customBannerEnabled = value; return s }
            if !value {
                // Turning the banner off also drops the stored image, so re-enabling
                // starts clean.
                let _ = AyuSavedMedia.removeBanner(basePath: context.account.postbox.mediaBox.basePath)
            }
        },
        chooseBanner: {
            presentBannerImagePickerImpl?()
        },
        updateCustomProfileBackground: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.customProfileBackgroundEnabled = value; return s }
            if !value {
                let _ = AyuSavedMedia.removeProfileBackground(basePath: context.account.postbox.mediaBox.basePath)
            }
        },
        updateCustomProfileBackgroundForOthers: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.customProfileBackgroundForOthers = value; return s }
        },
        updateCustomProfileBackgroundForSettings: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.customProfileBackgroundForSettings = value; return s }
        },
        chooseProfileBackground: {
            presentProfileBackgroundImagePickerImpl?()
        }
    )

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        ayuGramSettings(postbox: context.account.postbox)
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Кастомизация"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let entries = ayuCustomizationEntries(settings: settings)
        linkRows.stableIds = entries.map { $0.stableId }
        focusedIndex = shadowSettingsFocusIndex(stableIds: entries.map { $0.stableId }, target: focus)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, initialScrollToItem: shadowSettingsInitialScroll(index: focusedIndex), animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    shadowSettingsInstallLinkMenu(controller: controller, context: context, screen: "customization", rows: linkRows)
    if focus != nil {
        shadowSettingsInstallFocus(controller: controller, index: { focusedIndex }, color: shadowSettingsPulseColor(context.sharedContext.currentPresentationData.with { $0 }.theme))
    }
    presentControllerImpl = { [weak controller] c, a in
        controller?.present(c, in: .window(.root), with: a)
    }

    // Shadow: present the system photo picker, then persist the picked image as
    // the custom banner via AyuSavedMedia. The delegate keeps a strong reference
    // to itself until the picker finishes, so it isn't deallocated mid-flow.
    presentBannerImagePickerImpl = { [weak controller] in
        guard let controller = controller else {
            return
        }
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.mediaTypes = ["public.image"]
        let delegate = BannerImagePickerDelegate(completion: { image in
            guard let image = image, let data = image.jpegData(compressionQuality: 0.9) else {
                return
            }
            let _ = AyuSavedMedia.saveBanner(basePath: context.account.postbox.mediaBox.basePath, jpegData: data)
            ayuUpdateSettings(context: context) { var s = $0; s.customBannerEnabled = true; return s }
        })
        delegate.retainSelf()
        picker.delegate = delegate
        controller.view.window?.rootViewController?.present(picker, animated: true)
    }

    // Same picker pattern for the "Мой профиль" custom background.
    presentProfileBackgroundImagePickerImpl = { [weak controller] in
        guard let controller = controller else {
            return
        }
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.mediaTypes = ["public.image"]
        let delegate = BannerImagePickerDelegate(completion: { image in
            guard let image = image, let data = image.jpegData(compressionQuality: 0.9) else {
                return
            }
            let _ = AyuSavedMedia.saveProfileBackground(basePath: context.account.postbox.mediaBox.basePath, jpegData: data)
            ayuUpdateSettings(context: context) { var s = $0; s.customProfileBackgroundEnabled = true; return s }
        })
        delegate.retainSelf()
        picker.delegate = delegate
        controller.view.window?.rootViewController?.present(picker, animated: true)
    }
    arguments.updateSetting = { f in
        ayuUpdateSettings(context: context) { current in
            var current = current
            f(&current)
            return current
        }
    }
    arguments.pickSettingsIconColor = { [weak arguments] isBackground in
        let current = ayuGramSettingsCurrent
        let value = isBackground ? current.settingsIconBackgroundColor : current.settingsIconGlyphColor
        ShadowColorPicker.present(context: context, title: isBackground ? "Цвет фона иконок" : "Цвет значков", color: UIColor(rgb: UInt32(truncatingIfNeeded: value) & 0xFFFFFF), completion: { color in
            let rgb = shadowRGBValue(color)
            arguments?.updateSetting { settings in
                if isBackground {
                    settings.settingsIconBackgroundColor = rgb
                } else {
                    settings.settingsIconGlyphColor = rgb
                }
            }
        })
    }
    arguments.openMessageScreenshot = { [weak controller] in
        controller?.push(shadowMessageScreenshotSettingsController(context: context))
    }
    arguments.openHeaderButtons = { [weak controller] in
        controller?.push(shadowHeaderButtonsController(context: context))
    }
    arguments.selectVoiceTimeFormat = {
        let data = context.sharedContext.currentPresentationData.with { $0 }
        let sheet = ActionSheetController(presentationData: data)
        var items: [ActionSheetItem] = [ActionSheetTextItem(title: "Пример: голосовое 1:14, прослушано 0:22", parseMarkdown: false)]
        for format in ShadowVoiceTime.formats {
            items.append(ActionSheetButtonItem(title: "\(ShadowVoiceTime.title(format)) — \(ShadowVoiceTime.example(format))", action: { [weak sheet] in
                sheet?.dismissAnimated()
                ayuUpdateSettings(context: context) { var settings = $0; settings.voiceTimeFormat = format; return settings }
            }))
        }
        sheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: data.strings.Common_Cancel, action: { [weak sheet] in sheet?.dismissAnimated() })])
        ])
        presentControllerImpl?(sheet, nil)
    }
    arguments.updatePreferUsernameForBots = { value in
        ayuUpdateSettings(context: context) { var s = $0; s.preferUsernameForBots = value; return s }
    }
    arguments.updatePreferUsernameForNonContacts = { value in
        ayuUpdateSettings(context: context) { var s = $0; s.preferUsernameForNonContacts = value; return s }
    }
    return controller
}

// Retained delegate for the banner photo picker: returns the picked image (or
// nil on cancel) and always dismisses the picker.
private final class BannerImagePickerDelegate: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private let completion: (UIImage?) -> Void
    // Self-retain cycle held only for the picker's lifetime (see retainSelf()).
    private var selfReference: BannerImagePickerDelegate?

    init(completion: @escaping (UIImage?) -> Void) {
        self.completion = completion
    }

    // Keep this delegate alive (UIImagePickerController's delegate is weak) until
    // the picker finishes or is cancelled.
    func retainSelf() {
        self.selfReference = self
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
        picker.dismiss(animated: true)
        self.completion(image)
        self.selfReference = nil
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        self.completion(nil)
        self.selfReference = nil
    }
}

private final class AyuSpyArguments {
    let updateKeepDeleted: (Bool) -> Void
    let updateKeepDeletedSecretChats: (Bool) -> Void
    let updateSaveEditHistory: (Bool) -> Void
    let updateShowEditComparisonAction: (Bool) -> Void
    let updateKeepSelfDestructMedia: (Bool) -> Void
    let updateAllowSaveRestrictedContent: (Bool) -> Void
    let updateAskBeforeStoryView: (Bool) -> Void
    let updateSaveDestructingMedia: (Bool) -> Void
    let updateSaveAllIncomingMedia: (Bool) -> Void
    let selectAttachmentSizeLimit: () -> Void
    let selectAttachmentAge: () -> Void
    let updateKeepPinned: (Bool) -> Void
    let updateKeepChannels: (Bool) -> Void
    let updateKeepBots: (Bool) -> Void
    let openForkStorage: () -> Void
    var updateOnlineHistory: (Bool) -> Void = { _ in }
    var updateSaveViewedStories: (Bool) -> Void = { _ in }
    var openSavedStories: () -> Void = {}

    init(
        updateKeepDeleted: @escaping (Bool) -> Void,
        updateKeepDeletedSecretChats: @escaping (Bool) -> Void,
        updateSaveEditHistory: @escaping (Bool) -> Void,
        updateShowEditComparisonAction: @escaping (Bool) -> Void,
        updateKeepSelfDestructMedia: @escaping (Bool) -> Void,
        updateAllowSaveRestrictedContent: @escaping (Bool) -> Void,
        updateAskBeforeStoryView: @escaping (Bool) -> Void,
        updateSaveDestructingMedia: @escaping (Bool) -> Void,
        updateSaveAllIncomingMedia: @escaping (Bool) -> Void,
        selectAttachmentSizeLimit: @escaping () -> Void,
        selectAttachmentAge: @escaping () -> Void,
        updateKeepPinned: @escaping (Bool) -> Void,
        updateKeepChannels: @escaping (Bool) -> Void,
        updateKeepBots: @escaping (Bool) -> Void,
        openForkStorage: @escaping () -> Void
    ) {
        self.updateKeepDeleted = updateKeepDeleted
        self.updateKeepDeletedSecretChats = updateKeepDeletedSecretChats
        self.updateSaveEditHistory = updateSaveEditHistory
        self.updateShowEditComparisonAction = updateShowEditComparisonAction
        self.updateKeepSelfDestructMedia = updateKeepSelfDestructMedia
        self.updateAllowSaveRestrictedContent = updateAllowSaveRestrictedContent
        self.updateAskBeforeStoryView = updateAskBeforeStoryView
        self.updateSaveDestructingMedia = updateSaveDestructingMedia
        self.updateSaveAllIncomingMedia = updateSaveAllIncomingMedia
        self.selectAttachmentSizeLimit = selectAttachmentSizeLimit
        self.selectAttachmentAge = selectAttachmentAge
        self.updateKeepPinned = updateKeepPinned
        self.updateKeepChannels = updateKeepChannels
        self.updateKeepBots = updateKeepBots
        self.openForkStorage = openForkStorage
    }
}

private enum AyuSpySection: Int32 {
    case deleted
    case edits
    case restricted
    case storyPrompt
    case savedMedia
    case onlineHistory
    case stories
}

private enum AyuSpyEntry: ItemListNodeEntry {
    case deletedHeader
    case keepDeleted(Bool)
    case keepDeletedSecretChats(Bool)
    case keepSelfDestructMedia(Bool)
    case deletedFooter

    case editsHeader
    case saveEditHistory(Bool)
    case showEditComparisonAction(Bool)
    case editsFooter

    case restrictedHeader
    case allowSaveRestrictedContent(Bool)
    case restrictedFooter

    case storyPromptHeader
    case askBeforeStoryView(Bool)
    case storyPromptFooter

    case savedMediaHeader
    case saveDestructingMedia(Bool)
    case saveAllIncomingMedia(Bool)
    case attachmentSizeLimit(Int64)
    case attachmentAge(Int32)
    case keepPinned(Bool)
    case keepChannels(Bool)
    case keepBots(Bool)
    case forkStorage
    case savedMediaFooter

    case onlineHistoryHeader
    case onlineHistory(Bool)
    case onlineHistoryFooter

    case storiesHeader
    case saveViewedStories(Bool)
    case openSavedStories
    case storiesFooter

    var section: ItemListSectionId {
        switch self {
        case .deletedHeader, .keepDeleted, .keepDeletedSecretChats, .keepSelfDestructMedia, .deletedFooter:
            return AyuSpySection.deleted.rawValue
        case .editsHeader, .saveEditHistory, .showEditComparisonAction, .editsFooter:
            return AyuSpySection.edits.rawValue
        case .restrictedHeader, .allowSaveRestrictedContent, .restrictedFooter:
            return AyuSpySection.restricted.rawValue
        case .storyPromptHeader, .askBeforeStoryView, .storyPromptFooter:
            return AyuSpySection.storyPrompt.rawValue
        case .savedMediaHeader, .saveDestructingMedia, .saveAllIncomingMedia, .attachmentSizeLimit, .attachmentAge, .keepPinned, .keepChannels, .keepBots, .forkStorage, .savedMediaFooter:
            return AyuSpySection.savedMedia.rawValue
        case .onlineHistoryHeader, .onlineHistory, .onlineHistoryFooter:
            return AyuSpySection.onlineHistory.rawValue
        case .storiesHeader, .saveViewedStories, .openSavedStories, .storiesFooter:
            return AyuSpySection.stories.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .deletedHeader: return 0
        case .keepDeleted: return 1
        case .keepDeletedSecretChats: return 2
        case .keepSelfDestructMedia: return 3
        case .deletedFooter: return 4
        case .editsHeader: return 5
        case .saveEditHistory: return 6
        case .showEditComparisonAction: return 7
        case .editsFooter: return 8
        case .restrictedHeader: return 9
        case .allowSaveRestrictedContent: return 10
        case .restrictedFooter: return 11
        case .storyPromptHeader: return 12
        case .askBeforeStoryView: return 13
        case .storyPromptFooter: return 14
        case .savedMediaHeader: return 15
        case .saveDestructingMedia: return 16
        case .saveAllIncomingMedia: return 17
        case .attachmentSizeLimit: return 18
        case .attachmentAge: return 19
        case .keepPinned: return 20
        case .keepChannels: return 21
        case .keepBots: return 22
        case .forkStorage: return 23
        case .savedMediaFooter: return 24
        case .onlineHistoryHeader: return 25
        case .onlineHistory: return 26
        case .onlineHistoryFooter: return 27
        case .storiesHeader: return 28
        case .saveViewedStories: return 29
        case .openSavedStories: return 30
        case .storiesFooter: return 31
        }
    }

    static func <(lhs: AyuSpyEntry, rhs: AyuSpyEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AyuSpyArguments
        switch self {
        case .storiesHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ИСТОРИИ", sectionId: self.section)
        case let .saveViewedStories(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Сохранять просмотренные истории", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSaveViewedStories(value)
            })
        case .openSavedStories:
            return ItemListDisclosureItem(presentationData: presentationData, title: "Сохранённые истории", label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openSavedStories()
            })
        case .storiesFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Каждая история, которую вы открыли, копируется на устройство и остаётся доступной, даже если автор её удалил или она истекла. Сохраняется только то, что вы сами посмотрели."), sectionId: self.section)
        case .onlineHistoryHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ИСТОРИЯ «В СЕТИ»", sectionId: self.section)
        case let .onlineHistory(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Записывать, когда контакты в сети", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateOnlineHistory(value)
            })
        case .onlineHistoryFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Shadow запоминает входы и выходы контактов из обновлений статуса, которые Telegram и так присылает, и хранит их 30 дней только на этом устройстве. Смотреть — в профиле контакта: «История в сети». Если контакт скрыл время захода, записываются только моменты, когда приложение видело его онлайн."), sectionId: self.section)
        case .deletedHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "УДАЛЁННЫЕ СООБЩЕНИЯ", sectionId: self.section)
        case let .keepDeleted(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Сохранять удалённые", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateKeepDeleted(value)
            })
        case let .keepDeletedSecretChats(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Сохранять удалённые в секретных чатах", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateKeepDeletedSecretChats(value)
            })
        case let .keepSelfDestructMedia(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Сохранять «одноразовые»", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateKeepSelfDestructMedia(value)
            })
        case .deletedFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("«Сохранять удалённые» работает в обычных облачных чатах. Для секретных чатов используется отдельный переключатель: он сохраняет входящие сообщения, подписи и уже загруженные медиа только на этом устройстве, удерживает их при удалении собеседником и при очистке истории, а также показывает их в архиве Shadow. Уже удалённое до включения восстановить нельзя.\n\n«Сохранять одноразовые» оставляет view-once / самоуничтожающиеся медиа облачных чатов доступными после просмотра. В секретных чатах одноразовые медиа сохраняются отдельной настройкой секретных чатов."), sectionId: self.section)
        case .editsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ИСТОРИЯ ИЗМЕНЕНИЙ", sectionId: self.section)
        case let .saveEditHistory(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Сохранять историю правок", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSaveEditHistory(value)
            })
        case let .showEditComparisonAction(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Показывать «Сравнить правки»", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateShowEditComparisonAction(value)
            })
        case .editsFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("При каждом изменении сообщения сохраняется предыдущая версия — старый текст, подписи и медиа. «История изменений» остаётся в контекстном меню. Включите отдельный переключатель, если хотите также видеть кнопку сравнения добавленного и удалённого текста."), sectionId: self.section)
        case .restrictedHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ЗАЩИЩЁННЫЙ КОНТЕНТ", sectionId: self.section)
        case let .allowSaveRestrictedContent(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Разрешить сохранение", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateAllowSaveRestrictedContent(value)
            })
        case .restrictedFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Снимает защиту от копирования: разрешает копировать, пересылать и сохранять в защищённых чатах, приватных каналах и личных чатах с запретом сохранения. Истории с запретом пересылки тоже можно сохранить в галерею (без Premium) и снять скриншотом."), sectionId: self.section)
        case .storyPromptHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ИСТОРИИ", sectionId: self.section)
        case let .askBeforeStoryView(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Спросить перед просмотром истории", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateAskBeforeStoryView(value)
            })
        case .storyPromptFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Если скрытие просмотров историй («Призрак») выключено, перед открытием чужой истории будет предложено включить его. Для собственных историй не спрашивается."), sectionId: self.section)
        case .savedMediaHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "СОХРАНЁННЫЕ ВЛОЖЕНИЯ", sectionId: self.section)
        case let .saveDestructingMedia(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Сохранять самоуничтожающиеся", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSaveDestructingMedia(value)
            })
        case let .saveAllIncomingMedia(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Сохранять все входящие медиа", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSaveAllIncomingMedia(value)
            })
        case let .attachmentSizeLimit(value):
            return ItemListDisclosureItem(presentationData: presentationData, title: "Лимит размера", label: attachmentSizeLabel(value), sectionId: self.section, style: .blocks, action: {
                arguments.selectAttachmentSizeLimit()
            })
        case let .attachmentAge(value):
            return ItemListDisclosureItem(presentationData: presentationData, title: "Срок хранения", label: attachmentAgeLabel(value), sectionId: self.section, style: .blocks, action: {
                arguments.selectAttachmentAge()
            })
        case let .keepPinned(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Не очищать закреплённые", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateKeepPinned(value)
            })
        case let .keepChannels(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Исключить каналы", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateKeepChannels(value)
            })
        case let .keepBots(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Исключить ботов", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateKeepBots(value)
            })
        case .forkStorage:
            return ItemListDisclosureItem(presentationData: presentationData, title: "Хранилище и размер папки", label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openForkStorage()
            })
        case .savedMediaFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Приватная локальная копия медиа, которая переживает удаление. «Сохранять самоуничтожающиеся» копирует view-once / TTL-медиа до их исчезновения (и не уведомляет отправителя). «Сохранять все входящие медиа» сохраняет каждое входящее фото, видео, документ, голосовое и кружок — независимо от «Сохранения в галерею» и защиты от копирования.\n\nАвтоочистка работает по двум независимым лимитам, их можно использовать вместе: «Лимит размера» удаляет самые старые файлы при превышении общего размера папки; «Срок хранения» удаляет вложения старше выбранного срока, а также сами сохранённые удалённые сообщения, помеченные корзиной раньше этого срока. При очистке всегда удаляются самые старые файлы. Исключения (закреплённые, каналы, боты) никогда не очищаются. «Хранилище и размер папки» показывает занятое место по чатам."), sectionId: self.section)
        }
    }
}

private func ayuSpyEntries(settings: AyuGramSettings) -> [AyuSpyEntry] {
    var entries: [AyuSpyEntry] = []

    entries.append(.deletedHeader)
    entries.append(.keepDeleted(settings.keepDeletedMessages))
    entries.append(.keepDeletedSecretChats(settings.keepDeletedSecretChatMessages))
    entries.append(.keepSelfDestructMedia(settings.keepSelfDestructMedia))
    entries.append(.deletedFooter)

    entries.append(.editsHeader)
    entries.append(.saveEditHistory(settings.saveEditHistory))
    entries.append(.showEditComparisonAction(settings.showEditComparisonAction))
    entries.append(.editsFooter)

    entries.append(.restrictedHeader)
    entries.append(.allowSaveRestrictedContent(settings.allowSaveRestrictedContent))
    entries.append(.restrictedFooter)

    entries.append(.storyPromptHeader)
    entries.append(.askBeforeStoryView(settings.askBeforeStoryView))
    entries.append(.storyPromptFooter)

    entries.append(.savedMediaHeader)
    entries.append(.saveDestructingMedia(settings.saveDestructingMedia))
    entries.append(.saveAllIncomingMedia(settings.saveAllIncomingMedia))
    entries.append(.attachmentSizeLimit(settings.attachmentSizeLimit))
    entries.append(.attachmentAge(settings.mediaAutoCleanInterval))
    entries.append(.keepPinned(settings.mediaAutoCleanKeepPinned))
    entries.append(.keepChannels(settings.mediaAutoCleanKeepChannels))
    entries.append(.keepBots(settings.mediaAutoCleanKeepBots))
    entries.append(.forkStorage)
    entries.append(.savedMediaFooter)

    entries.append(.onlineHistoryHeader)
    entries.append(.onlineHistory(settings.onlineHistory))
    entries.append(.onlineHistoryFooter)

    entries.append(.storiesHeader)
    entries.append(.saveViewedStories(settings.saveViewedStories))
    entries.append(.openSavedStories)
    entries.append(.storiesFooter)

    return entries
}

func ayuSpyController(context: AccountContext, focus: ShadowSettingsSearchItem? = nil) -> ViewController {
    let linkRows = ShadowSettingsLinkRows()
    var focusedIndex: Int?
    var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?

    let arguments = AyuSpyArguments(
        updateKeepDeleted: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.keepDeletedMessages = value; return s }
        },
        updateKeepDeletedSecretChats: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.keepDeletedSecretChatMessages = value; return s }
        },
        updateSaveEditHistory: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.saveEditHistory = value; return s }
        },
        updateShowEditComparisonAction: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.showEditComparisonAction = value; return s }
        },
        updateKeepSelfDestructMedia: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.keepSelfDestructMedia = value; return s }
        },
        updateAllowSaveRestrictedContent: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.allowSaveRestrictedContent = value; return s }
        },
        updateAskBeforeStoryView: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.askBeforeStoryView = value; return s }
        },
        updateSaveDestructingMedia: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.saveDestructingMedia = value; return s }
        },
        updateSaveAllIncomingMedia: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.saveAllIncomingMedia = value; return s }
        },
        selectAttachmentSizeLimit: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let actionSheet = ActionSheetController(presentationData: presentationData)
            var items: [ActionSheetItem] = []
            for limit in attachmentSizeLimits {
                items.append(ActionSheetButtonItem(title: attachmentSizeLabel(limit), action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    ayuUpdateSettings(context: context) { var s = $0; s.attachmentSizeLimit = limit; return s }
                }))
            }
            actionSheet.setItemGroups([
                ActionSheetItemGroup(items: items),
                ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                    })
                ])
            ])
            presentControllerImpl?(actionSheet, nil)
        },
        selectAttachmentAge: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let actionSheet = ActionSheetController(presentationData: presentationData)
            var items: [ActionSheetItem] = []
            for interval in attachmentAgeIntervals {
                items.append(ActionSheetButtonItem(title: attachmentAgeLabel(interval), action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    ayuUpdateSettings(context: context) { var s = $0; s.mediaAutoCleanInterval = interval; return s }
                }))
            }
            actionSheet.setItemGroups([
                ActionSheetItemGroup(items: items),
                ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                    })
                ])
            ])
            presentControllerImpl?(actionSheet, nil)
        },
        updateKeepPinned: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.mediaAutoCleanKeepPinned = value; return s }
        },
        updateKeepChannels: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.mediaAutoCleanKeepChannels = value; return s }
        },
        updateKeepBots: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.mediaAutoCleanKeepBots = value; return s }
        },
        openForkStorage: {
            pushControllerImpl?(ayuForkStorageController(context: context))
        }
    )
    arguments.updateOnlineHistory = { value in
        ayuUpdateSettings(context: context) { var s = $0; s.onlineHistory = value; return s }
    }
    arguments.updateSaveViewedStories = { value in
        ayuUpdateSettings(context: context) { var s = $0; s.saveViewedStories = value; return s }
    }
    arguments.openSavedStories = {
        pushControllerImpl?(shadowSavedStoriesController(context: context))
    }

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        ayuGramSettings(postbox: context.account.postbox)
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Шпион"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let entries = ayuSpyEntries(settings: settings)
        linkRows.stableIds = entries.map { $0.stableId }
        focusedIndex = shadowSettingsFocusIndex(stableIds: entries.map { $0.stableId }, target: focus)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, initialScrollToItem: shadowSettingsInitialScroll(index: focusedIndex), animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    shadowSettingsInstallLinkMenu(controller: controller, context: context, screen: "spy", rows: linkRows)
    if focus != nil {
        shadowSettingsInstallFocus(controller: controller, index: { focusedIndex }, color: shadowSettingsPulseColor(context.sharedContext.currentPresentationData.with { $0 }.theme))
    }
    presentControllerImpl = { [weak controller] c, a in
        controller?.present(c, in: .window(.root), with: a)
    }
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    return controller
}

// MARK: - Призрак

private final class AyuGhostArguments {
    let updateGhostMode: (Bool) -> Void
    let selectAccountMode: () -> Void
    let updateHideOnline: (Bool) -> Void
    let updateHideTyping: (Bool) -> Void
    let updateHideReadReceipts: (Bool) -> Void
    let updateHideStoryViews: (Bool) -> Void
    let updateOfferGhostBeforeStories: (Bool) -> Void
    let updateSendViaScheduled: (Bool) -> Void
    let updateSendWithoutOnline: (Bool) -> Void

    init(
        updateGhostMode: @escaping (Bool) -> Void,
        selectAccountMode: @escaping () -> Void,
        updateHideOnline: @escaping (Bool) -> Void,
        updateHideTyping: @escaping (Bool) -> Void,
        updateHideReadReceipts: @escaping (Bool) -> Void,
        updateHideStoryViews: @escaping (Bool) -> Void,
        updateOfferGhostBeforeStories: @escaping (Bool) -> Void,
        updateSendViaScheduled: @escaping (Bool) -> Void,
        updateSendWithoutOnline: @escaping (Bool) -> Void
    ) {
        self.updateGhostMode = updateGhostMode
        self.selectAccountMode = selectAccountMode
        self.updateHideOnline = updateHideOnline
        self.updateHideTyping = updateHideTyping
        self.updateHideReadReceipts = updateHideReadReceipts
        self.updateHideStoryViews = updateHideStoryViews
        self.updateOfferGhostBeforeStories = updateOfferGhostBeforeStories
        self.updateSendViaScheduled = updateSendViaScheduled
        self.updateSendWithoutOnline = updateSendWithoutOnline
    }
}

private enum AyuGhostSection: Int32 {
    case ghost
    case sending
}

private enum AyuGhostEntry: ItemListNodeEntry {
    case ghostHeader
    case ghostMode(Bool)
    case accountMode(ShadowGhostAccountMode)
    case hideOnline(Bool)
    case hideTyping(Bool)
    case hideReadReceipts(Bool)
    case hideStoryViews(Bool)
    case offerGhostBeforeStories(Bool)
    case ghostFooter

    case sendingHeader
    case sendViaScheduled(Bool)
    case sendWithoutOnline(Bool)
    case sendingFooter

    var section: ItemListSectionId {
        switch self {
        case .ghostHeader, .ghostMode, .accountMode, .hideOnline, .hideTyping, .hideReadReceipts, .hideStoryViews, .offerGhostBeforeStories, .ghostFooter:
            return AyuGhostSection.ghost.rawValue
        case .sendingHeader, .sendViaScheduled, .sendWithoutOnline, .sendingFooter:
            return AyuGhostSection.sending.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .ghostHeader: return 0
        case .ghostMode: return 1
        case .accountMode: return 11
        case .hideOnline: return 2
        case .hideTyping: return 3
        case .hideReadReceipts: return 4
        case .hideStoryViews: return 5
        case .ghostFooter: return 6
        case .sendingHeader: return 7
        case .sendViaScheduled: return 8
        case .sendWithoutOnline: return 9
        case .sendingFooter: return 10
        case .offerGhostBeforeStories: return 12
        }
    }

    // Display order; stable ids of later-added rows do not follow it.
    private var sortKey: Double {
        switch self {
        case .accountMode: return 1.5
        case .offerGhostBeforeStories: return 5.5
        default: return Double(self.stableId)
        }
    }

    static func <(lhs: AyuGhostEntry, rhs: AyuGhostEntry) -> Bool {
        return lhs.sortKey < rhs.sortKey
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AyuGhostArguments
        switch self {
        case .ghostHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "РЕЖИМ ПРИЗРАКА", sectionId: self.section)
        case let .ghostMode(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Режим призрака", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateGhostMode(value)
            })
        case let .accountMode(value):
            let label: String
            switch value {
            case .manual: label = "Вручную"
            case .alwaysOn: label = "Всегда включён"
            case .alwaysOff: label = "Всегда выключен"
            case .followPrevious: label = "Как в предыдущем аккаунте"
            }
            return ItemListDisclosureItem(presentationData: presentationData, title: "Для этого аккаунта", label: label, sectionId: self.section, style: .blocks, action: {
                arguments.selectAccountMode()
            })
        case let .hideOnline(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Не показывать онлайн", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateHideOnline(value)
            })
        case let .hideTyping(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Не показывать набор текста", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateHideTyping(value)
            })
        case let .hideReadReceipts(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Не отправлять прочтения", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateHideReadReceipts(value)
            })
        case let .hideStoryViews(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Скрывать просмотры историй", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateHideStoryViews(value)
            })
        case let .offerGhostBeforeStories(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Предлагать призрак перед историями", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateOfferGhostBeforeStories(value)
            })
        case .ghostFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("«Предлагать призрак перед историями»: если призрак выключен, перед чужой историей спросит, включить ли его.\n\n«Режим призрака» — главный переключатель. Пока он выключен, ни один из переключателей ниже не действует, даже если включён — онлайн, прочтения, набор текста, запись, загрузка и просмотры историй сообщаются как обычно. Включите «Режим призрака», чтобы переключатели ниже вступили в силу.\n\n«Не отправлять прочтения» не даёт чтению чата отмечать вас онлайн — вы остаётесь офлайн даже после открытия сообщений — и скрывает галочки прочтения от отправителя (счётчики непрочитанного при этом обнуляются локально). «Скрывать просмотры историй» убирает вас из списка зрителей. Чужой статус вы продолжаете видеть как обычно."), sectionId: self.section)
        case .sendingHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ОТЛОЖЕННАЯ ОТПРАВКА", sectionId: self.section)
        case let .sendViaScheduled(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Отправлять через отложенные сообщения", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSendViaScheduled(value)
            })
        case let .sendWithoutOnline(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Отправлять без появления онлайн", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSendWithoutOnline(value)
            })
        case .sendingFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Помогает отправлять сообщения, не появляясь онлайн.\n\nРаботает только при включённом режиме призрака. «Отправлять через отложенные сообщения» отправляет сообщения как запланированные (schedule_date): текст — с задержкой 12 секунд, медиа (фото, видео, документы, голосовые, видеосообщения) — с динамической задержкой. Сервер публикует их позже и не отмечает вас онлайн в момент отправки. «Отправлять без появления онлайн» дополнительно сразу переустанавливает статус «офлайн» после отправки."), sectionId: self.section)
        }
    }
}

private func ayuGhostEntries(settings: AyuGramSettings) -> [AyuGhostEntry] {
    return [
        .ghostHeader,
        .ghostMode(settings.ghostMode),
        .accountMode(settings.ghostAccountMode),
        .hideOnline(settings.hideOnlineStatus),
        .hideTyping(settings.hideTyping),
        .hideReadReceipts(settings.hideReadReceipts),
        .hideStoryViews(settings.hideStoryViews),
        .offerGhostBeforeStories(settings.offerGhostBeforeStories),
        .ghostFooter,
        .sendingHeader,
        .sendViaScheduled(settings.sendViaScheduled),
        .sendWithoutOnline(settings.sendWithoutOnline),
        .sendingFooter
    ]
}

public func ayuGhostController(context: AccountContext) -> ViewController {
    return ayuGhostController(context: context, focus: nil)
}

private func ayuGhostController(context: AccountContext, focus: ShadowSettingsSearchItem?) -> ViewController {
    let linkRows = ShadowSettingsLinkRows()
    var focusedIndex: Int?
    var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?
    let arguments = AyuGhostArguments(
        updateGhostMode: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.ghostMode = value; s.ghostAccountMode = .manual; return s }
        },
        selectAccountMode: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let actionSheet = ActionSheetController(presentationData: presentationData)
            let choices: [(String, ShadowGhostAccountMode)] = [
                ("Вручную", .manual),
                ("Всегда включён", .alwaysOn),
                ("Всегда выключен", .alwaysOff),
                ("Как в предыдущем аккаунте", .followPrevious)
            ]
            let items: [ActionSheetItem] = choices.map { title, mode in
                ActionSheetButtonItem(title: title, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    ayuUpdateSettings(context: context) { var s = $0; s.ghostAccountMode = mode; if mode == .alwaysOn { s.ghostMode = true }; if mode == .alwaysOff { s.ghostMode = false }; return s }
                })
            }
            actionSheet.setItemGroups([ActionSheetItemGroup(items: items)])
            presentControllerImpl?(actionSheet, nil)
        },
        updateHideOnline: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.hideOnlineStatus = value; return s }
        },
        updateHideTyping: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.hideTyping = value; return s }
        },
        updateHideReadReceipts: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.hideReadReceipts = value; return s }
        },
        updateHideStoryViews: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.hideStoryViews = value; return s }
        },
        updateOfferGhostBeforeStories: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.offerGhostBeforeStories = value; return s }
        },
        updateSendViaScheduled: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.sendViaScheduled = value; return s }
        },
        updateSendWithoutOnline: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.sendWithoutOnline = value; return s }
        }
    )

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        ayuGramSettings(postbox: context.account.postbox)
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Призрак"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let entries = ayuGhostEntries(settings: settings)
        linkRows.stableIds = entries.map { $0.stableId }
        focusedIndex = shadowSettingsFocusIndex(stableIds: entries.map { $0.stableId }, target: focus)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, initialScrollToItem: shadowSettingsInitialScroll(index: focusedIndex), animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    shadowSettingsInstallLinkMenu(controller: controller, context: context, screen: "ghost", rows: linkRows)
    presentControllerImpl = { [weak controller] c, a in
        controller?.present(c, in: .window(.root), with: a)
    }
    if focus != nil {
        shadowSettingsInstallFocus(controller: controller, index: { focusedIndex }, color: shadowSettingsPulseColor(context.sharedContext.currentPresentationData.with { $0 }.theme))
    }
    return controller
}

// MARK: - Разное (visual profile spoofing for screenshots)

private enum AyuMiscSection: Int32 {
    case profileSpoof
}

private enum AyuMiscEntryTag: ItemListItemTag {
    case spoofId
    case spoofDc
    case spoofPhone

    func isEqual(to other: ItemListItemTag) -> Bool {
        if let other = other as? AyuMiscEntryTag, other == self {
            return true
        }
        return false
    }
}

private enum AyuMiscEntry: ItemListNodeEntry {
    case spoofHeader
    case spoofIdToggle(Bool)
    case spoofIdInput(String)
    case spoofDcToggle(Bool)
    case spoofDcInput(String)
    case spoofPhoneToggle(Bool)
    case spoofPhoneInput(String)
    case spoofFooter

    var section: ItemListSectionId {
        return AyuMiscSection.profileSpoof.rawValue
    }

    var stableId: Int32 {
        switch self {
        case .spoofHeader: return 0
        case .spoofIdToggle: return 1
        case .spoofIdInput: return 2
        case .spoofDcToggle: return 3
        case .spoofDcInput: return 4
        case .spoofPhoneToggle: return 5
        case .spoofPhoneInput: return 6
        case .spoofFooter: return 7
        }
    }

    static func <(lhs: AyuMiscEntry, rhs: AyuMiscEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AyuMiscArguments
        switch self {
        case .spoofHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ВИЗУАЛЬНАЯ ПОДМЕНА ПРОФИЛЯ", sectionId: self.section)
        case let .spoofIdToggle(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Подменить ID", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSpoofIdEnabled(value)
            })
        case let .spoofIdInput(value):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(string: "ID", textColor: presentationData.theme.list.itemPrimaryTextColor), text: value, placeholder: "Например: 2016", type: .number, clearType: .always, tag: AyuMiscEntryTag.spoofId, sectionId: self.section, textUpdated: { updatedText in
                arguments.updateSpoofIdValue(updatedText)
            }, shouldUpdateText: { text in
                return text.allSatisfy { $0.isNumber }
            }, action: {})
        case let .spoofDcToggle(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Подменить DC", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSpoofDcEnabled(value)
            })
        case let .spoofDcInput(value):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(string: "DC", textColor: presentationData.theme.list.itemPrimaryTextColor), text: value, placeholder: "Например: 5", type: .regular(capitalization: false, autocorrection: false), clearType: .always, tag: AyuMiscEntryTag.spoofDc, sectionId: self.section, textUpdated: { updatedText in
                arguments.updateSpoofDcValue(updatedText)
            }, action: {})
        case let .spoofPhoneToggle(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Подменить номер", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSpoofPhoneEnabled(value)
            })
        case let .spoofPhoneInput(value):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(string: "Номер", textColor: presentationData.theme.list.itemPrimaryTextColor), text: value, placeholder: "Только цифры, без +", type: .number, clearType: .always, tag: AyuMiscEntryTag.spoofPhone, sectionId: self.section, textUpdated: { updatedText in
                arguments.updateSpoofPhoneValue(updatedText)
            }, shouldUpdateText: { text in
                return text.allSatisfy { $0.isNumber }
            }, action: {})
        case .spoofFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Работает только визуально в интерфейсе Shadow и предназначено для скриншотов. Реальные данные аккаунта, номер телефона и то, что отправляется на сервер, не меняются. Если поле пустое, показываются реальные данные."), sectionId: self.section)
        }
    }
}

private final class AyuMiscArguments {
    let updateSpoofIdEnabled: (Bool) -> Void
    let updateSpoofIdValue: (String) -> Void
    let updateSpoofDcEnabled: (Bool) -> Void
    let updateSpoofDcValue: (String) -> Void
    let updateSpoofPhoneEnabled: (Bool) -> Void
    let updateSpoofPhoneValue: (String) -> Void

    init(
        updateSpoofIdEnabled: @escaping (Bool) -> Void,
        updateSpoofIdValue: @escaping (String) -> Void,
        updateSpoofDcEnabled: @escaping (Bool) -> Void,
        updateSpoofDcValue: @escaping (String) -> Void,
        updateSpoofPhoneEnabled: @escaping (Bool) -> Void,
        updateSpoofPhoneValue: @escaping (String) -> Void
    ) {
        self.updateSpoofIdEnabled = updateSpoofIdEnabled
        self.updateSpoofIdValue = updateSpoofIdValue
        self.updateSpoofDcEnabled = updateSpoofDcEnabled
        self.updateSpoofDcValue = updateSpoofDcValue
        self.updateSpoofPhoneEnabled = updateSpoofPhoneEnabled
        self.updateSpoofPhoneValue = updateSpoofPhoneValue
    }
}

private func ayuMiscEntries(settings: AyuGramSettings) -> [AyuMiscEntry] {
    var entries: [AyuMiscEntry] = []
    entries.append(.spoofHeader)
    entries.append(.spoofIdToggle(settings.spoofProfileIdEnabled))
    if settings.spoofProfileIdEnabled {
        entries.append(.spoofIdInput(settings.spoofProfileIdValue))
    }
    entries.append(.spoofDcToggle(settings.spoofProfileDcEnabled))
    if settings.spoofProfileDcEnabled {
        entries.append(.spoofDcInput(settings.spoofProfileDcValue))
    }
    entries.append(.spoofPhoneToggle(settings.spoofProfilePhoneEnabled))
    if settings.spoofProfilePhoneEnabled {
        entries.append(.spoofPhoneInput(settings.spoofProfilePhoneValue))
    }
    entries.append(.spoofFooter)
    return entries
}

func ayuMiscController(context: AccountContext, focus: ShadowSettingsSearchItem? = nil) -> ViewController {
    let linkRows = ShadowSettingsLinkRows()
    var focusedIndex: Int?
    let arguments = AyuMiscArguments(
        updateSpoofIdEnabled: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.spoofProfileIdEnabled = value; return s }
        },
        updateSpoofIdValue: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.spoofProfileIdValue = value; return s }
        },
        updateSpoofDcEnabled: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.spoofProfileDcEnabled = value; return s }
        },
        updateSpoofDcValue: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.spoofProfileDcValue = value; return s }
        },
        updateSpoofPhoneEnabled: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.spoofProfilePhoneEnabled = value; return s }
        },
        updateSpoofPhoneValue: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.spoofProfilePhoneValue = value; return s }
        }
    )

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        ayuGramSettings(postbox: context.account.postbox)
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Подмена профиля"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let entries = ayuMiscEntries(settings: settings)
        linkRows.stableIds = entries.map { $0.stableId }
        focusedIndex = shadowSettingsFocusIndex(stableIds: entries.map { $0.stableId }, target: focus)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, initialScrollToItem: shadowSettingsInitialScroll(index: focusedIndex), animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    shadowSettingsInstallLinkMenu(controller: controller, context: context, screen: "profile", rows: linkRows)
    if focus != nil {
        shadowSettingsInstallFocus(controller: controller, index: { focusedIndex }, color: shadowSettingsPulseColor(context.sharedContext.currentPresentationData.with { $0 }.theme))
    }
    return controller
}

// Shadow: 0xRRGGBB of a color; extended-range components (the system picker
// can return them) are clamped to 0...1.
private func shadowRGBValue(_ color: UIColor) -> Int32 {
    var red: CGFloat = 0.0
    var green: CGFloat = 0.0
    var blue: CGFloat = 0.0
    var alpha: CGFloat = 0.0
    guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
        return 0
    }
    func channel(_ value: CGFloat) -> Int32 {
        return Int32((min(1.0, max(0.0, value)) * 255.0).rounded())
    }
    return (channel(red) << 16) | (channel(green) << 8) | channel(blue)
}

// Shadow: "#RRGGBB" for a stored 0xRRGGBB value.
private func shadowHexColorString(_ value: Int32) -> String {
    let hex = String(UInt32(truncatingIfNeeded: value) & 0xFFFFFF, radix: 16, uppercase: true)
    return "#" + String(repeating: "0", count: max(0, 6 - hex.count)) + hex
}

// Shadow: the system color picker (UIColorPickerViewController, iOS 14+),
// presented natively; reports the final color when the picker is dismissed.
// iOS 13 gets a #RRGGBB text prompt instead.
private enum ShadowColorPicker {
    static func present(context: AccountContext, title: String, color: UIColor, completion: @escaping (UIColor) -> Void) {
        if #available(iOS 14.0, *) {
            ShadowSystemColorPicker.present(context: context, title: title, color: color, completion: completion)
            return
        }
        let alert = UIAlertController(title: title, message: "Цвет в формате #RRGGBB", preferredStyle: .alert)
        alert.addTextField { field in
            field.text = shadowHexColorString(shadowRGBValue(color))
            field.autocapitalizationType = .allCharacters
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { [weak alert] _ in
            var text = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if text.hasPrefix("#") {
                text.removeFirst()
            }
            if text.count == 6, let value = UInt32(text, radix: 16) {
                completion(UIColor(rgb: value))
            }
        }))
        context.sharedContext.mainWindow?.presentNative(alert)
    }
}

@available(iOS 14.0, *)
private final class ShadowSystemColorPicker: NSObject, UIColorPickerViewControllerDelegate {
    private static var active: ShadowSystemColorPicker?
    private let completion: (UIColor) -> Void

    private init(completion: @escaping (UIColor) -> Void) {
        self.completion = completion
        super.init()
    }

    static func present(context: AccountContext, title: String, color: UIColor, completion: @escaping (UIColor) -> Void) {
        let picker = UIColorPickerViewController()
        picker.title = title
        picker.selectedColor = color
        picker.supportsAlpha = false
        let delegate = ShadowSystemColorPicker(completion: completion)
        ShadowSystemColorPicker.active = delegate
        picker.delegate = delegate
        context.sharedContext.mainWindow?.presentNative(picker)
    }

    func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        self.completion(viewController.selectedColor)
        ShadowSystemColorPicker.active = nil
    }
}

// Shadow: sends crash reports (JSON from MetricKit) as files to a chat, then deletes them.
private func shadowSendCrashReports(context: AccountContext, peerId: EnginePeer.Id, reports: [ShadowCrashReports.Report], completion: @escaping () -> Void) {
    var messages: [EnqueueMessage] = []
    let info = "Shadow \(ShadowVersion.full) (\(ShadowUpdateCheck.installedBuild.map { "\($0)" } ?? "?")), iOS \(UIDevice.current.systemVersion)"
    for (index, report) in reports.enumerated() {
        guard let data = try? Data(contentsOf: report.url) else {
            continue
        }
        let resource = LocalFileMediaResource(fileId: Int64.random(in: Int64.min ... Int64.max))
        context.engine.resources.storeResourceData(id: EngineMediaResource.Id(resource.id), data: data)
        let file = TelegramMediaFile(fileId: EngineMedia.Id(namespace: Namespaces.Media.LocalFile, id: Int64.random(in: Int64.min ... Int64.max)), partialReference: nil, resource: resource, previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: "application/json", size: Int64(data.count), attributes: [.FileName(fileName: report.url.lastPathComponent)], alternativeRepresentations: [])
        messages.append(.message(text: index == 0 ? info : "", attributes: [], inlineStickers: [:], mediaReference: .standalone(media: file), threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: []))
    }
    guard !messages.isEmpty else {
        return
    }
    let _ = (enqueueMessages(account: context.account, peerId: peerId, messages: messages)
    |> deliverOnMainQueue).startStandalone(next: { ids in
        if ids.contains(where: { $0 != nil }) {
            for report in reports {
                ShadowCrashReports.shared.remove(report)
            }
        }
        completion()
    })
}

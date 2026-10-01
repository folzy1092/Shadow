import Foundation
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext

// Shadow: "Обновления" — compares the installed build with the build announced
// in shadow-update.json (fallback: the latest GitHub Release; ShadowUpdateCheck). Checks only when the screen is
// opened or on request; there is no background polling.

private enum ShadowUpdatesState: Equatable {
    case checking
    case result(ShadowUpdateCheck.Status)
}

private enum ShadowUpdatesSection: Int32 {
    case status
    case actions
}

private enum ShadowUpdatesEntry: ItemListNodeEntry {
    case installed(String)
    case status(String)
    case notes(String)
    case open(String)
    case recheck(enabled: Bool)

    var section: ItemListSectionId {
        switch self {
        case .installed, .status, .notes:
            return ShadowUpdatesSection.status.rawValue
        case .open, .recheck:
            return ShadowUpdatesSection.actions.rawValue
        }
    }

    // 0 is the search entry id (ShadowSettingsSearchIndex, destination .updates).
    var stableId: Int32 {
        switch self {
        case .installed: return 0
        case .status: return 1
        case .notes: return 2
        case .open: return 3
        case .recheck: return 4
        }
    }

    static func <(lhs: ShadowUpdatesEntry, rhs: ShadowUpdatesEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ShadowUpdatesArguments
        switch self {
        case let .installed(text):
            return ItemListDisclosureItem(presentationData: presentationData, title: "Установлена", label: text, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil)
        case let .status(text):
            return ItemListDisclosureItem(presentationData: presentationData, title: "Статус", label: text, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil)
        case let .notes(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .open(title):
            return ItemListActionItem(presentationData: presentationData, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: arguments.open)
        case let .recheck(enabled):
            return ItemListActionItem(presentationData: presentationData, title: "Проверить снова", kind: enabled ? .generic : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: arguments.recheck)
        }
    }
}

private final class ShadowUpdatesArguments {
    let open: () -> Void
    let recheck: () -> Void

    init(open: @escaping () -> Void, recheck: @escaping () -> Void) {
        self.open = open
        self.recheck = recheck
    }
}

private func shadowUpdatesEntries(state: ShadowUpdatesState) -> [ShadowUpdatesEntry] {
    let installedBuild = ShadowUpdateCheck.installedBuild.flatMap { "\($0)" } ?? "?"
    var entries: [ShadowUpdatesEntry] = [.installed("Shadow \(ShadowUpdateCheck.installedVersion) (\(installedBuild))")]
    switch state {
    case .checking:
        entries.append(.status("Проверяю…"))
        entries.append(.recheck(enabled: false))
    case let .result(status):
        switch status {
        case let .upToDate(release):
            entries.append(.status("Актуальная версия"))
            if let release {
                entries.append(.notes("Последняя объявленная сборка: \(release.title)."))
            }
            entries.append(.open("Открыть страницу релизов"))
        case let .available(release):
            entries.append(.status(release.isRequired ? "Обязательное обновление: сборка \(release.build)" : "Доступна сборка \(release.build)"))
            var notes = release.title
            let body = release.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                notes += "\n\n" + String(body.prefix(600))
            }
            entries.append(.notes(notes))
            entries.append(.open("Открыть страницу загрузки"))
        case let .failed(reason):
            entries.append(.status("Не удалось проверить"))
            entries.append(.notes(reason))
            entries.append(.open("Открыть страницу релизов"))
        }
        entries.append(.recheck(enabled: true))
    }
    return entries
}

func shadowUpdatesController(context: AccountContext, focus: ShadowSettingsSearchItem? = nil) -> ViewController {
    let statePromise = ValuePromise<ShadowUpdatesState>(.checking, ignoreRepeated: true)
    let stateValue = Atomic<ShadowUpdatesState>(value: .checking)
    let updateState: (ShadowUpdatesState) -> Void = { state in
        let _ = stateValue.swap(state)
        statePromise.set(state)
    }
    let runCheck: () -> Void = {
        updateState(.checking)
        ShadowUpdateCheck.check { status in
            updateState(.result(status))
        }
    }

    let arguments = ShadowUpdatesArguments(open: {
        var url = ShadowUpdateCheck.releasesPageURL
        if case let .result(status) = stateValue.with({ $0 }) {
            switch status {
            case let .available(release):
                url = release.pageURL
            case let .upToDate(release):
                url = release?.pageURL ?? url
            case .failed:
                break
            }
        }
        context.sharedContext.applicationBindings.openUrl(url.absoluteString)
    }, recheck: {
        runCheck()
    })

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, statePromise.get())
    |> deliverOnMainQueue
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let entries = shadowUpdatesEntries(state: state)
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Обновления"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    runCheck()
    return controller
}

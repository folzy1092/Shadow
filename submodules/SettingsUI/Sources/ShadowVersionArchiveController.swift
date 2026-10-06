import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext

// Shadow: "Архив версий" — every announced build since the device
// whitelist (ShadowVersionArchive), like GitHub releases: tap a version to read
// its notes and download its IPA (to roll back). Read from shadow-changelog.json
// each time the screen opens.

private enum ShadowVersionArchiveState: Equatable {
    case loading
    case failed
    case loaded([ShadowVersionArchive.Row])
}

private enum ShadowVersionArchiveSection: Int32 {
    case versions
    case info
}

private final class ShadowVersionArchiveArguments {
    let open: (ShadowVersionArchive.Row) -> Void
    let reload: () -> Void

    init(open: @escaping (ShadowVersionArchive.Row) -> Void, reload: @escaping () -> Void) {
        self.open = open
        self.reload = reload
    }
}

private enum ShadowVersionArchiveEntry: ItemListNodeEntry {
    case header
    case loading
    case failed
    case version(Int, ShadowVersionArchive.Row)
    case footer

    var section: ItemListSectionId {
        switch self {
        case .footer:
            return ShadowVersionArchiveSection.info.rawValue
        default:
            return ShadowVersionArchiveSection.versions.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .header: return 0
        case .loading: return 1
        case .failed: return 2
        case let .version(index, _): return 100 + Int32(index)
        case .footer: return 10_000
        }
    }

    static func <(lhs: ShadowVersionArchiveEntry, rhs: ShadowVersionArchiveEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ShadowVersionArchiveArguments
        switch self {
        case .header:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ВЕРСИИ", sectionId: self.section)
        case .loading:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Загружаю список…"), sectionId: self.section)
        case .failed:
            return ItemListActionItem(presentationData: presentationData, title: "Не удалось загрузить. Повторить", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.reload()
            })
        case let .version(_, row):
            var label = ShadowVersionArchive.dateText(row.entry.date)
            if row.isInstalled {
                label = "установлена · " + label
            }
            return ItemListDisclosureItem(presentationData: presentationData, title: row.title, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.open(row)
            })
        case .footer:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Все объявленные сборки, начиная с той, где появился вход по вайтлисту устройств. Откройте версию, чтобы прочитать, что в ней изменилось, или скачать её IPA и откатиться. Старая сборка ставится поверх новой; если она не запустится с данными новой версии, поставьте свежую обратно."), sectionId: self.section)
        }
    }
}

func shadowVersionArchiveController(context: AccountContext) -> ViewController {
    let state = ValuePromise<ShadowVersionArchiveState>(.loading, ignoreRepeated: true)
    var pushControllerImpl: ((ViewController) -> Void)?

    let load: () -> Void = {
        state.set(.loading)
        ShadowVersionArchive.fetch { entries in
            if let entries {
                state.set(.loaded(ShadowVersionArchive.rows(entries: entries, installedBuild: ShadowUpdateCheck.installedBuild)))
            } else {
                state.set(.failed)
            }
        }
    }

    let arguments = ShadowVersionArchiveArguments(open: { row in
        pushControllerImpl?(shadowVersionDetailsController(context: context, row: row))
    }, reload: {
        load()
    })

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, state.get())
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [ShadowVersionArchiveEntry] = [.header]
        switch state {
        case .loading:
            entries.append(.loading)
        case .failed:
            entries.append(.failed)
        case let .loaded(rows):
            for (index, row) in rows.enumerated() {
                entries.append(.version(index, row))
            }
        }
        entries.append(.footer)
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Архив версий"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    load()
    return controller
}

// MARK: - One version

private enum ShadowVersionDetailsSection: Int32 {
    case info
    case notes
    case download
}

private final class ShadowVersionDetailsArguments {
    let download: () -> Void

    init(download: @escaping () -> Void) {
        self.download = download
    }
}

private enum ShadowVersionDetailsEntry: ItemListNodeEntry {
    case info(String)
    case notesHeader
    case note(Int, String)
    case download(String)
    case downloadFooter(String)

    var section: ItemListSectionId {
        switch self {
        case .info:
            return ShadowVersionDetailsSection.info.rawValue
        case .notesHeader, .note:
            return ShadowVersionDetailsSection.notes.rawValue
        case .download, .downloadFooter:
            return ShadowVersionDetailsSection.download.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .info: return 0
        case .notesHeader: return 1
        case let .note(index, _): return 100 + Int32(index)
        case .download: return 10_000
        case .downloadFooter: return 10_001
        }
    }

    static func <(lhs: ShadowVersionDetailsEntry, rhs: ShadowVersionDetailsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ShadowVersionDetailsArguments
        switch self {
        case let .info(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case .notesHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ЧТО НОВОГО", sectionId: self.section)
        case let .note(_, text):
            return ItemListMultilineTextItem(presentationData: presentationData, text: "• " + text, enabledEntityTypes: [], sectionId: self.section, style: .blocks)
        case let .download(title):
            return ItemListActionItem(presentationData: presentationData, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.download()
            })
        case let .downloadFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func shadowVersionDetailsController(context: AccountContext, row: ShadowVersionArchive.Row) -> ViewController {
    let entry = row.entry
    let ipaURL = ShadowVersionArchive.ipaURL(entry)
    let arguments = ShadowVersionDetailsArguments(download: {
        context.sharedContext.applicationBindings.openUrl(ipaURL.absoluteString)
    })

    var info = "Сборка \(entry.build) · \(ShadowVersionArchive.dateText(entry.date))"
    if row.isInstalled {
        info += " · установлена"
    }
    var entries: [ShadowVersionDetailsEntry] = [.info(info), .notesHeader]
    for (index, item) in entry.items.enumerated() {
        entries.append(.note(index, item))
    }
    entries.append(.download("Скачать IPA (build \(entry.build))"))
    entries.append(.downloadFooter(row.isInstalled ? "Эта сборка сейчас установлена." : "IPA ставится поверх установленной сборки тем же способом, что и обычное обновление."))

    let signal = context.sharedContext.presentationData
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(row.title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }
    return ItemListController(context: context, state: signal)
}

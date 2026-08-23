import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import TelegramStringFormatting
import ItemListUI
import PresentationDataUtils
import AccountContext
import AlertUI

// AyuGram fork: "Fork storage usage" screen (3d). Shows how much space the
// fork's own data takes, by category, and lets the user clear each category:
//   • Saved-media gallery  — the private, fork-local media copies (real bytes on
//     disk), broken down by chat. This is the fork's cache diagram.
//   • Anti-delete messages — kept messages the server asked to delete (count).
//   • Edit history         — messages with stored previous versions (count).
// The two count-based categories are tracked via a lightweight forward index
// (see AyuForkStore) so they can be cleared without scanning the whole database.

private final class AyuForkStorageArguments {
    let clearGallery: () -> Void
    let clearAntiDelete: () -> Void
    let clearEditHistory: () -> Void
    let runCleanupNow: () -> Void
    let openArchive: () -> Void

    init(clearGallery: @escaping () -> Void, runCleanupNow: @escaping () -> Void, clearAntiDelete: @escaping () -> Void, clearEditHistory: @escaping () -> Void, openArchive: @escaping () -> Void) {
        self.clearGallery = clearGallery
        self.runCleanupNow = runCleanupNow
        self.clearAntiDelete = clearAntiDelete
        self.clearEditHistory = clearEditHistory
        self.openArchive = openArchive
    }
}

private enum AyuForkStorageSection: Int32 {
    case overview
    case gallery
    case other
}

private struct AyuForkChatUsage: Equatable {
    let title: String
    let sizeText: String
}

private enum AyuForkStorageEntry: ItemListNodeEntry {
    case overviewHeader
    case totalSize(String)
    case overviewFooter

    case galleryHeader
    case galleryEmpty
    case chatRow(index: Int, title: String, sizeText: String)
    case clearGallery(enabled: Bool)
    case runCleanupNow

    case otherHeader
    case antiDelete(count: Int)
    case clearAntiDelete(enabled: Bool)
    case editHistory(count: Int)
    case clearEditHistory(enabled: Bool)
    case openArchive(enabled: Bool)
    case otherFooter

    var section: ItemListSectionId {
        switch self {
        case .overviewHeader, .totalSize, .overviewFooter:
            return AyuForkStorageSection.overview.rawValue
        case .galleryHeader, .galleryEmpty, .chatRow, .clearGallery, .runCleanupNow:
            return AyuForkStorageSection.gallery.rawValue
        case .otherHeader, .antiDelete, .clearAntiDelete, .editHistory, .clearEditHistory, .openArchive, .otherFooter:
            return AyuForkStorageSection.other.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .overviewHeader:
            return 0
        case .totalSize:
            return 1
        case .overviewFooter:
            return 2
        case .galleryHeader:
            return 3
        case .galleryEmpty:
            return 4
        case let .chatRow(index, _, _):
            return 100 + Int32(index)
        case .runCleanupNow:
            return 999
        case .clearGallery:
            return 1000
        case .otherHeader:
            return 1001
        case .antiDelete:
            return 1002
        case .clearAntiDelete:
            return 1003
        case .editHistory:
            return 1004
        case .clearEditHistory:
            return 1005
        case .openArchive:
            return 1006
        case .otherFooter:
            return 1007
        }
    }

    static func <(lhs: AyuForkStorageEntry, rhs: AyuForkStorageEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AyuForkStorageArguments
        switch self {
        case .overviewHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ХРАНИЛИЩЕ", sectionId: self.section)
        case let .totalSize(text):
            return ItemListDisclosureItem(presentationData: presentationData, title: "Сохранённые медиа на диске", label: text, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil)
        case .overviewFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Место, занятое приватной папкой сохранённых медиа. Медиа удалённых сообщений и история правок хранятся в общем кэше Telegram и показаны ниже как количество."), sectionId: self.section)
        case .galleryHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "СОХРАНЁННЫЕ МЕДИА ПО ЧАТАМ", sectionId: self.section)
        case .galleryEmpty:
            return ItemListDisclosureItem(presentationData: presentationData, title: "Нет сохранённых медиа", label: "", sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil)
        case let .chatRow(_, title, sizeText):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: sizeText, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil)
        case .runCleanupNow:
            return ItemListActionItem(presentationData: presentationData, title: "Запустить очистку сейчас", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.runCleanupNow()
            })
        case let .clearGallery(enabled):
            return ItemListActionItem(presentationData: presentationData, title: "Очистить сохранённые медиа", kind: enabled ? .destructive : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                if enabled {
                    arguments.clearGallery()
                }
            })
        case .otherHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ДРУГИЕ ДАННЫЕ", sectionId: self.section)
        case let .antiDelete(count):
            return ItemListDisclosureItem(presentationData: presentationData, title: "Удалённые сообщения", label: "\(count)", sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil)
        case let .clearAntiDelete(enabled):
            return ItemListActionItem(presentationData: presentationData, title: "Удалить сохранённые сообщения", kind: enabled ? .destructive : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                if enabled {
                    arguments.clearAntiDelete()
                }
            })
        case let .editHistory(count):
            return ItemListDisclosureItem(presentationData: presentationData, title: "Сообщения с историей правок", label: "\(count)", sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil)
        case let .clearEditHistory(enabled):
            return ItemListActionItem(presentationData: presentationData, title: "Очистить историю правок", kind: enabled ? .destructive : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                if enabled {
                    arguments.clearEditHistory()
                }
            })
        case let .openArchive(enabled):
            return ItemListActionItem(presentationData: presentationData, title: "Открыть архив", kind: enabled ? .generic : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                if enabled {
                    arguments.openArchive()
                }
            })
        case .otherFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("«Открыть архив» показывает все сохранённые сообщения одним списком, как обычный чат: удалённые собеседником и отредактированные, вместе с медиа. «Удалить сохранённые сообщения» убирает все сообщения, оставленные форком после удаления собеседником (освобождает и связанные медиа). «Очистить историю правок» удаляет сохранённые прежние версии из всех сообщений."), sectionId: self.section)
        }
    }
}

private struct AyuForkStorageData: Equatable {
    let totalText: String
    let chats: [AyuForkChatUsage]
    let antiDeleteCount: Int
    let editHistoryCount: Int
}

private func ayuForkStorageEntries(data: AyuForkStorageData) -> [AyuForkStorageEntry] {
    var entries: [AyuForkStorageEntry] = []

    entries.append(.overviewHeader)
    entries.append(.totalSize(data.totalText))
    entries.append(.overviewFooter)

    entries.append(.galleryHeader)
    if data.chats.isEmpty {
        entries.append(.galleryEmpty)
    } else {
        for (index, chat) in data.chats.enumerated() {
            entries.append(.chatRow(index: index, title: chat.title, sizeText: chat.sizeText))
        }
    }
    entries.append(.runCleanupNow)
    entries.append(.clearGallery(enabled: !data.chats.isEmpty))

    entries.append(.otherHeader)
    entries.append(.antiDelete(count: data.antiDeleteCount))
    entries.append(.clearAntiDelete(enabled: data.antiDeleteCount > 0))
    entries.append(.editHistory(count: data.editHistoryCount))
    entries.append(.clearEditHistory(enabled: data.editHistoryCount > 0))
    entries.append(.openArchive(enabled: data.antiDeleteCount > 0 || data.editHistoryCount > 0))
    entries.append(.otherFooter)

    return entries
}

public func ayuForkStorageController(context: AccountContext) -> ViewController {
    let refreshPromise = ValuePromise<Int>(0, ignoreRepeated: false)
    var refreshValue = 0
    let refresh: () -> Void = {
        refreshValue += 1
        refreshPromise.set(refreshValue)
    }

    var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?

    let arguments = AyuForkStorageArguments(
        clearGallery: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            presentControllerImpl?(textAlertController(context: context, title: nil, text: "Удалить все сохранённые медиа из папки форка?", actions: [
                TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                TextAlertAction(type: .destructiveAction, title: presentationData.strings.Common_Delete, action: {
                    let basePath = context.account.postbox.mediaBox.basePath
                    let signal = Signal<Never, NoError> { subscriber in
                        let _ = AyuSavedMedia.clearAll(basePath: basePath)
                        subscriber.putCompletion()
                        return EmptyDisposable
                    }
                    |> runOn(Queue.concurrentDefaultQueue())
                    |> deliverOnMainQueue
                    let _ = signal.start(completed: {
                        refresh()
                    })
                })
            ]), nil)
        },
        runCleanupNow: {
            let _ = (ayuRunMediaCleanupNow(postbox: context.account.postbox)
            |> deliverOnMainQueue).start(next: { result in
                var lines: [String] = []
                if result.maxAge <= 0 {
                    lines.append("Срок хранения: отключён")
                } else {
                    lines.append("По сроку удалено: \(result.ageRemoved)")
                }
                if result.maxBytes <= 0 {
                    lines.append("Лимит размера: отключён")
                } else {
                    lines.append("По размеру удалено: \(result.sizeRemoved)")
                }
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                presentControllerImpl?(textAlertController(context: context, title: nil, text: lines.joined(separator: "\n"), actions: [
                    TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})
                ]), nil)
                refresh()
            })
        },
        clearAntiDelete: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            presentControllerImpl?(textAlertController(context: context, title: nil, text: "Навсегда удалить все сохранённые (удалённые собеседником) сообщения?", actions: [
                TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                TextAlertAction(type: .destructiveAction, title: presentationData.strings.Common_Delete, action: {
                    let _ = (ayuForkStoreClearKeptDeleted(postbox: context.account.postbox)
                    |> deliverOnMainQueue).start(completed: {
                        refresh()
                    })
                })
            ]), nil)
        },
        clearEditHistory: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            presentControllerImpl?(textAlertController(context: context, title: nil, text: "Очистить сохранённую историю правок из всех сообщений?", actions: [
                TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                TextAlertAction(type: .destructiveAction, title: presentationData.strings.Common_Delete, action: {
                    let _ = (ayuForkStoreClearEditHistory(postbox: context.account.postbox)
                    |> deliverOnMainQueue).start(completed: {
                        refresh()
                    })
                })
            ]), nil)
        },
        openArchive: {
            pushControllerImpl?(ayuArchiveChatController(context: context))
        }
    )

    let dataSignal: Signal<AyuForkStorageData, NoError> = combineLatest(
        context.sharedContext.presentationData,
        refreshPromise.get()
    )
    |> mapToSignal { presentationData, _ -> Signal<AyuForkStorageData, NoError> in
        let basePath = context.account.postbox.mediaBox.basePath
        let scan = Signal<[AyuSavedMedia.Entry], NoError> { subscriber in
            subscriber.putNext(AyuSavedMedia.entries(basePath: basePath))
            subscriber.putCompletion()
            return EmptyDisposable
        }
        |> runOn(Queue.concurrentDefaultQueue())

        return scan
        |> mapToSignal { fileEntries -> Signal<AyuForkStorageData, NoError> in
            return context.account.postbox.transaction { transaction -> AyuForkStorageData in
                var byPeer: [Int64: Int64] = [:]
                var unknown: Int64 = 0
                var total: Int64 = 0
                for entry in fileEntries {
                    total += entry.size
                    if let peerId = entry.peerId {
                        byPeer[peerId, default: 0] += entry.size
                    } else {
                        unknown += entry.size
                    }
                }

                let formatting = DataSizeStringFormatting(presentationData: presentationData)
                var sortable: [(size: Int64, usage: AyuForkChatUsage)] = []
                for (peerIdValue, size) in byPeer {
                    let peerId = PeerId(peerIdValue)
                    let title: String
                    if let peer = transaction.getPeer(peerId) {
                        title = EnginePeer(peer).displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
                    } else {
                        title = "Чат \(peerIdValue)"
                    }
                    sortable.append((size: size, usage: AyuForkChatUsage(title: title, sizeText: dataSizeString(size, formatting: formatting))))
                }
                if unknown > 0 {
                    sortable.append((size: unknown, usage: AyuForkChatUsage(title: "Прочее", sizeText: dataSizeString(unknown, formatting: formatting))))
                }
                sortable.sort { $0.size > $1.size }

                let store = ayuForkStore(transaction: transaction)
                return AyuForkStorageData(
                    totalText: dataSizeString(total, formatting: formatting),
                    chats: sortable.map { $0.usage },
                    antiDeleteCount: store.keptDeleted.count,
                    editHistoryCount: store.editHistory.count
                )
            }
        }
    }

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        dataSignal
    )
    |> deliverOnMainQueue
    |> map { presentationData, data -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Хранилище"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: ayuForkStorageEntries(data: data), style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c, a in
        controller?.present(c, in: .window(.root), with: a)
    }
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    return controller
}

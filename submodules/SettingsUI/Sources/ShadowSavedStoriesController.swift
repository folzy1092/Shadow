import Foundation
import UIKit
import QuickLook
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext

// Shadow: «Сохранённые истории» (spec 7.5) — viewed stories kept by
// ShadowStoryArchive, grouped by author, opened with Quick Look.

private enum ShadowSavedStoriesEntry: ItemListNodeEntry {
    case info(String)
    case peerHeader(index: Int, title: String)
    case story(index: Int, peerIndex: Int, title: String, label: String)
    case clear

    var section: ItemListSectionId {
        switch self {
        case .info:
            return 0
        case let .peerHeader(index, _):
            return 1 + Int32(index)
        case let .story(_, peerIndex, _, _):
            return 1 + Int32(peerIndex)
        case .clear:
            return 100_000
        }
    }

    var stableId: Int32 {
        switch self {
        case .info: return 0
        case let .peerHeader(index, _): return 10 + Int32(index) * 10_000
        case let .story(index, peerIndex, _, _): return 11 + Int32(peerIndex) * 10_000 + Int32(index)
        case .clear: return Int32.max
        }
    }

    static func <(lhs: ShadowSavedStoriesEntry, rhs: ShadowSavedStoriesEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ShadowSavedStoriesArguments
        switch self {
        case let .info(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .peerHeader(_, title):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: title.uppercased(), sectionId: self.section)
        case let .story(index, peerIndex, title, label):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.open(peerIndex, index)
            })
        case .clear:
            return ItemListActionItem(presentationData: presentationData, title: "Удалить все сохранённые истории", kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: arguments.clear)
        }
    }
}

private final class ShadowSavedStoriesArguments {
    let open: (Int, Int) -> Void
    let clear: () -> Void

    init(open: @escaping (Int, Int) -> Void, clear: @escaping () -> Void) {
        self.open = open
        self.clear = clear
    }
}

private final class ShadowQuickLookSource: NSObject, QLPreviewControllerDataSource {
    static var active: ShadowQuickLookSource?
    let urls: [URL]

    init(urls: [URL]) {
        self.urls = urls
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return self.urls.count
    }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        return self.urls[index] as NSURL
    }
}

func shadowSavedStoriesController(context: AccountContext) -> ViewController {
    let archive = ShadowStoryArchive.shared
    let accountPeerId = context.account.peerId.toInt64()
    let revision = ValuePromise<Int>(0, ignoreRepeated: false)
    var revisionValue = 0
    var groups: [(EnginePeer.Id, [ShadowStoryArchive.Item])] = []

    let arguments = ShadowSavedStoriesArguments(open: { peerIndex, index in
        guard peerIndex < groups.count else {
            return
        }
        let items = groups[peerIndex].1
        let source = ShadowQuickLookSource(urls: items.map(\.url))
        ShadowQuickLookSource.active = source
        let preview = QLPreviewController()
        preview.dataSource = source
        preview.currentPreviewItemIndex = min(index, max(0, items.count - 1))
        context.sharedContext.mainWindow?.presentNative(preview)
    }, clear: {
        for item in archive.items(accountPeerId: accountPeerId) {
            archive.remove(item)
        }
        revisionValue += 1
        revision.set(revisionValue)
    })

    let data: Signal<[(EnginePeer.Id, String, [ShadowStoryArchive.Item])], NoError> = revision.get()
    |> mapToSignal { _ -> Signal<[(EnginePeer.Id, String, [ShadowStoryArchive.Item])], NoError> in
        var byPeer: [Int64: [ShadowStoryArchive.Item]] = [:]
        for item in archive.items(accountPeerId: accountPeerId) {
            byPeer[item.peerId, default: []].append(item)
        }
        let peerIds = byPeer.keys.sorted(by: { (byPeer[$0]?.first?.date ?? Date()) > (byPeer[$1]?.first?.date ?? Date()) }).map { EnginePeer.Id($0) }
        return context.engine.data.get(EngineDataMap(peerIds.map(TelegramEngine.EngineData.Item.Peer.Peer.init(id:))))
        |> map { peers -> [(EnginePeer.Id, String, [ShadowStoryArchive.Item])] in
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            return peerIds.map { peerId in
                let title = peers[peerId].flatMap { $0 }?.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder) ?? "\(peerId.id._internalGetInt64Value())"
                return (peerId, title, byPeer[peerId.toInt64()] ?? [])
            }
        }
    }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ru_RU")
    formatter.dateFormat = "d MMM, HH:mm"

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, data)
    |> map { presentationData, data -> (ItemListControllerState, (ItemListNodeState, Any)) in
        groups = data.map { ($0.0, $0.2) }
        var entries: [ShadowSavedStoriesEntry] = [.info(data.isEmpty ? "Пока пусто. Включите «Сохранять просмотренные истории» в Shadow → Сохранение: каждая открытая вами история сохранится здесь и останется, даже если автор её удалит." : "Истории, которые вы смотрели. Хранятся только на этом устройстве.")]
        let now = Date()
        for (peerIndex, group) in data.enumerated() {
            entries.append(.peerHeader(index: peerIndex, title: group.1))
            for (index, item) in group.2.enumerated() {
                let expired = now.timeIntervalSince(item.date) > 24 * 60 * 60
                entries.append(.story(index: index, peerIndex: peerIndex, title: (item.isVideo ? "Видео · " : "Фото · ") + formatter.string(from: item.date), label: expired ? "истекла" : ""))
            }
        }
        if !data.isEmpty {
            entries.append(.clear)
        }
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Сохранённые истории"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }
    return ItemListController(context: context, state: signal)
}

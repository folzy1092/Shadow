import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext

// Shadow: «Чаты со своей скоростью» — chats whose voice messages play at their
// own speed (ShadowChatVoiceSpeed), reset one by one or all at once.

// Chats with their own speed on this account, live.
func shadowChatVoiceSpeedEntries(context: AccountContext) -> Signal<[ShadowChatVoiceSpeed.Entry], NoError> {
    let accountPeerId = context.account.peerId.toInt64()
    return Signal { subscriber in
        subscriber.putNext(ShadowChatVoiceSpeed.shared.entries(accountPeerId: accountPeerId))
        let observer = NotificationCenter.default.addObserver(forName: ShadowChatVoiceSpeed.didChangeNotification, object: nil, queue: .main, using: { _ in
            subscriber.putNext(ShadowChatVoiceSpeed.shared.entries(accountPeerId: accountPeerId))
        })
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

func shadowChatVoiceSpeedCount(context: AccountContext) -> Signal<Int, NoError> {
    return shadowChatVoiceSpeedEntries(context: context)
    |> map { $0.count }
    |> distinctUntilChanged
}

private final class ShadowChatVoiceSpeedArguments {
    let reset: (Int64, String) -> Void
    let resetAll: () -> Void

    init(reset: @escaping (Int64, String) -> Void, resetAll: @escaping () -> Void) {
        self.reset = reset
        self.resetAll = resetAll
    }
}

private enum ShadowChatVoiceSpeedEntry: ItemListNodeEntry {
    case info
    case chat(index: Int, peerId: Int64, title: String, rate: Int32)
    case resetAll
    case empty

    var section: ItemListSectionId {
        switch self {
        case .info, .empty:
            return 0
        case .chat:
            return 1
        case .resetAll:
            return 2
        }
    }

    var stableId: Int64 {
        switch self {
        case .info: return -3
        case .empty: return -2
        case .resetAll: return -1
        case let .chat(_, peerId, _, _): return peerId
        }
    }

    private var sortIndex: Int {
        switch self {
        case .info, .empty: return 0
        case let .chat(index, _, _, _): return 1 + index
        case .resetAll: return Int.max
        }
    }

    static func <(lhs: ShadowChatVoiceSpeedEntry, rhs: ShadowChatVoiceSpeedEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ShadowChatVoiceSpeedArguments
        switch self {
        case .info:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Голосовые из этих чатов играют со своей скоростью. Она запоминается, когда вы меняете скорость в полоске плеера, пока играет голосовое из чата. Нажмите на чат, чтобы вернуть ему общую скорость."), sectionId: self.section)
        case .empty:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Пока нет чатов со своей скоростью. Включите голосовое в чате и поменяйте скорость кнопкой в полоске плеера."), sectionId: self.section)
        case let .chat(_, peerId, title, rate):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: ShadowChatVoiceSpeed.title(rate: rate), labelStyle: .detailText, sectionId: self.section, style: .blocks, action: {
                arguments.reset(peerId, title)
            })
        case .resetAll:
            return ItemListActionItem(presentationData: presentationData, title: "Сбросить все", kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.resetAll()
            })
        }
    }
}

public func shadowChatVoiceSpeedController(context: AccountContext) -> ViewController {
    let accountPeerId = context.account.peerId.toInt64()
    var presentControllerImpl: ((ViewController) -> Void)?

    let confirm: (String, String, @escaping () -> Void) -> Void = { title, actionTitle, action in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let sheet = ActionSheetController(presentationData: presentationData)
        sheet.setItemGroups([
            ActionSheetItemGroup(items: [
                ActionSheetTextItem(title: title, parseMarkdown: false),
                ActionSheetButtonItem(title: actionTitle, color: .destructive, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                    action()
                })
            ]),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, action: { [weak sheet] in
                sheet?.dismissAnimated()
            })])
        ])
        presentControllerImpl?(sheet)
    }

    let arguments = ShadowChatVoiceSpeedArguments(reset: { peerId, title in
        confirm("«\(title)»: голосовые будут играть с общей скоростью.", "Сбросить скорость", {
            ShadowChatVoiceSpeed.shared.remove(chat: ShadowChatVoiceSpeed.chatKey(accountPeerId: accountPeerId, peerId: peerId))
        })
    }, resetAll: {
        confirm("Все чаты будут играть голосовые с общей скоростью.", "Сбросить все", {
            ShadowChatVoiceSpeed.shared.removeAll(accountPeerId: accountPeerId)
        })
    })

    let chats: Signal<([ShadowChatVoiceSpeed.Entry], [EnginePeer.Id: EnginePeer]), NoError> = shadowChatVoiceSpeedEntries(context: context)
    |> mapToSignal { list -> Signal<([ShadowChatVoiceSpeed.Entry], [EnginePeer.Id: EnginePeer]), NoError> in
        let ids = list.map { EnginePeer.Id($0.peerId) }
        return context.engine.data.get(EngineDataMap(ids.map(TelegramEngine.EngineData.Item.Peer.Peer.init)))
        |> map { peers -> ([ShadowChatVoiceSpeed.Entry], [EnginePeer.Id: EnginePeer]) in
            var result: [EnginePeer.Id: EnginePeer] = [:]
            for (id, peer) in peers {
                if let peer {
                    result[id] = peer
                }
            }
            return (list, result)
        }
    }

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, chats)
    |> map { presentationData, chats -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let (list, peers) = chats
        var entries: [ShadowChatVoiceSpeedEntry] = []
        if list.isEmpty {
            entries.append(.empty)
        } else {
            entries.append(.info)
            let named = list.map { entry -> (ShadowChatVoiceSpeed.Entry, String) in
                let title = peers[EnginePeer.Id(entry.peerId)]?.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder) ?? "Чат \(entry.peerId)"
                return (entry, title)
            }.sorted(by: { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending })
            for (index, item) in named.enumerated() {
                entries.append(.chat(index: index, peerId: item.0.peerId, title: item.1, rate: item.0.rate))
            }
            entries.append(.resetAll)
        }
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Своя скорость"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}

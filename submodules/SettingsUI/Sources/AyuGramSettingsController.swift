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

private final class AyuGramSettingsArguments {
    let updateKeepDeleted: (Bool) -> Void
    let updateHideOnline: (Bool) -> Void
    let updateHideTyping: (Bool) -> Void

    init(updateKeepDeleted: @escaping (Bool) -> Void, updateHideOnline: @escaping (Bool) -> Void, updateHideTyping: @escaping (Bool) -> Void) {
        self.updateKeepDeleted = updateKeepDeleted
        self.updateHideOnline = updateHideOnline
        self.updateHideTyping = updateHideTyping
    }
}

private enum AyuGramSettingsSection: Int32 {
    case antiDelete
    case presence
    case info
}

private enum AyuGramSettingsEntry: ItemListNodeEntry {
    case antiDeleteHeader
    case keepDeleted(Bool)
    case antiDeleteFooter

    case presenceHeader
    case hideOnline(Bool)
    case hideTyping(Bool)
    case presenceFooter

    case infoFooter

    var section: ItemListSectionId {
        switch self {
        case .antiDeleteHeader, .keepDeleted, .antiDeleteFooter:
            return AyuGramSettingsSection.antiDelete.rawValue
        case .presenceHeader, .hideOnline, .hideTyping, .presenceFooter:
            return AyuGramSettingsSection.presence.rawValue
        case .infoFooter:
            return AyuGramSettingsSection.info.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .antiDeleteHeader:
            return 0
        case .keepDeleted:
            return 1
        case .antiDeleteFooter:
            return 2
        case .presenceHeader:
            return 3
        case .hideOnline:
            return 4
        case .hideTyping:
            return 5
        case .presenceFooter:
            return 6
        case .infoFooter:
            return 7
        }
    }

    static func <(lhs: AyuGramSettingsEntry, rhs: AyuGramSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AyuGramSettingsArguments
        switch self {
        case .antiDeleteHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ANTI-DELETE", sectionId: self.section)
        case let .keepDeleted(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Keep deleted messages", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateKeepDeleted(value)
            })
        case .antiDeleteFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Messages and media that other people delete stay in the chat instead of disappearing. Your own deletions are unaffected."), sectionId: self.section)
        case .presenceHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "PRIVACY", sectionId: self.section)
        case let .hideOnline(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Hide online status", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateHideOnline(value)
            })
        case let .hideTyping(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Hide typing / recording", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateHideTyping(value)
            })
        case .presenceFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("When enabled, your \"online\" and \"typing…\" status are not sent to the server. You still receive other people's status normally."), sectionId: self.section)
        case .infoFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("This build reports itself to Telegram as Telegram Desktop / Windows (see Settings → Devices)."), sectionId: self.section)
        }
    }
}

private func ayuGramSettingsControllerEntries(settings: AyuGramSettings) -> [AyuGramSettingsEntry] {
    var entries: [AyuGramSettingsEntry] = []

    entries.append(.antiDeleteHeader)
    entries.append(.keepDeleted(settings.keepDeletedMessages))
    entries.append(.antiDeleteFooter)

    entries.append(.presenceHeader)
    entries.append(.hideOnline(settings.hideOnlineStatus))
    entries.append(.hideTyping(settings.hideTyping))
    entries.append(.presenceFooter)

    entries.append(.infoFooter)

    return entries
}

public func ayuGramSettingsController(context: AccountContext) -> ViewController {
    let arguments = AyuGramSettingsArguments(
        updateKeepDeleted: { value in
            let _ = updateAyuGramSettings(postbox: context.account.postbox, { current in
                var settings = current
                settings.keepDeletedMessages = value
                return settings
            }).start()
        },
        updateHideOnline: { value in
            let _ = updateAyuGramSettings(postbox: context.account.postbox, { current in
                var settings = current
                settings.hideOnlineStatus = value
                return settings
            }).start()
        },
        updateHideTyping: { value in
            let _ = updateAyuGramSettings(postbox: context.account.postbox, { current in
                var settings = current
                settings.hideTyping = value
                return settings
            }).start()
        }
    )

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        ayuGramSettings(postbox: context.account.postbox)
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("AyuGram"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: ayuGramSettingsControllerEntries(settings: settings), style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    return controller
}

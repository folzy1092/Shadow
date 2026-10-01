import Foundation
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext

// Shadow: "Чистый интерфейс" — independent switches that hide parts of the
// stock UI, plus the on-device voice transcription switch.

private enum ShadowCleanInterfaceSection: Int32 {
    case interface
    case messages
}

private enum ShadowCleanInterfaceEntry: ItemListNodeEntry {
    case interfaceHeader
    case hideStoriesBar(Bool)
    case hideGiftButton(Bool)
    case hidePremiumBadges(Bool)
    case hideSponsoredMessages(Bool)
    case interfaceFooter
    case messagesHeader
    case localVoiceTranscription(Bool)
    case messagesFooter

    var section: ItemListSectionId {
        switch self {
        case .interfaceHeader, .hideStoriesBar, .hideGiftButton, .hidePremiumBadges, .hideSponsoredMessages, .interfaceFooter:
            return ShadowCleanInterfaceSection.interface.rawValue
        case .messagesHeader, .localVoiceTranscription, .messagesFooter:
            return ShadowCleanInterfaceSection.messages.rawValue
        }
    }

    // Stable ids double as search entry ids (ShadowSettingsSearchIndex, destination .cleanInterface).
    var stableId: Int32 {
        switch self {
        case .interfaceHeader: return 100
        case .hideStoriesBar: return 0
        case .hideGiftButton: return 1
        case .hidePremiumBadges: return 2
        case .hideSponsoredMessages: return 3
        case .interfaceFooter: return 101
        case .messagesHeader: return 102
        case .localVoiceTranscription: return 4
        case .messagesFooter: return 103
        }
    }

    private var sortIndex: Int32 {
        switch self {
        case .interfaceHeader: return 0
        case .hideStoriesBar: return 1
        case .hideGiftButton: return 2
        case .hidePremiumBadges: return 3
        case .hideSponsoredMessages: return 4
        case .interfaceFooter: return 5
        case .messagesHeader: return 6
        case .localVoiceTranscription: return 7
        case .messagesFooter: return 8
        }
    }

    static func <(lhs: ShadowCleanInterfaceEntry, rhs: ShadowCleanInterfaceEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ShadowCleanInterfaceArguments
        switch self {
        case .interfaceHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ИНТЕРФЕЙС", sectionId: self.section)
        case let .hideStoriesBar(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Скрыть истории", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { $0.hideStoriesBar = value }
            })
        case let .hideGiftButton(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Скрыть кнопку подарка", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { $0.hideGiftButton = value }
            })
        case let .hidePremiumBadges(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Скрыть значки Premium у имён", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { $0.hidePremiumBadges = value }
            })
        case let .hideSponsoredMessages(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Скрыть рекламу в каналах", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { $0.hideSponsoredMessages = value }
            })
        case .interfaceFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Истории — лента над списком чатов. Подарок — кнопка в поле ввода. Значки Premium — звёздочка и эмодзи-статус рядом с именем; значки верификации остаются. Реклама применяется при следующем открытии канала."), sectionId: self.section)
        case .messagesHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ГОЛОСОВЫЕ", sectionId: self.section)
        case let .localVoiceTranscription(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Расшифровка на устройстве", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { $0.localVoiceTranscription = value }
            })
        case .messagesFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Без Premium голосовые сообщения расшифровываются распознаванием речи iOS прямо на телефоне — аудио никуда не отправляется. Язык распознавания совпадает с языком Telegram."), sectionId: self.section)
        }
    }
}

private final class ShadowCleanInterfaceArguments {
    let update: (@escaping (inout AyuGramSettings) -> Void) -> Void

    init(update: @escaping (@escaping (inout AyuGramSettings) -> Void) -> Void) {
        self.update = update
    }
}

private func shadowCleanInterfaceEntries(settings: AyuGramSettings) -> [ShadowCleanInterfaceEntry] {
    return [
        .interfaceHeader,
        .hideStoriesBar(settings.hideStoriesBar),
        .hideGiftButton(settings.hideGiftButton),
        .hidePremiumBadges(settings.hidePremiumBadges),
        .hideSponsoredMessages(settings.hideSponsoredMessages),
        .interfaceFooter,
        .messagesHeader,
        .localVoiceTranscription(settings.localVoiceTranscription),
        .messagesFooter
    ]
}

func shadowCleanInterfaceController(context: AccountContext, focus: ShadowSettingsSearchItem? = nil) -> ViewController {
    var focusedIndex: Int?
    let arguments = ShadowCleanInterfaceArguments(update: { f in
        let _ = updateAyuGramSettings(postbox: context.account.postbox, { current in
            var current = current
            f(&current)
            return current
        }).startStandalone()
    })

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, ayuGramSettings(postbox: context.account.postbox))
    |> deliverOnMainQueue
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let entries = shadowCleanInterfaceEntries(settings: settings)
        focusedIndex = shadowSettingsFocusIndex(stableIds: entries.map { $0.stableId }, target: focus)
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Чистый интерфейс"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, initialScrollToItem: shadowSettingsInitialScroll(index: focusedIndex), animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    if focus != nil {
        shadowSettingsInstallFocus(controller: controller, index: { focusedIndex }, color: context.sharedContext.currentPresentationData.with { $0 }.theme.list.itemAccentColor)
    }
    return controller
}

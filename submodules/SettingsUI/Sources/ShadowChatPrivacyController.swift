import Foundation
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext

private enum ShadowChatPrivacySection: Int32 {
    case rules
    case reset
}

private enum ShadowChatPrivacyEntry: ItemListNodeEntry {
    case read(ShadowChatPrivacyValue)
    case activity(ShadowChatPrivacyValue)
    case explanation
    case reset

    var section: ItemListSectionId {
        switch self {
        case .read, .activity, .explanation: return ShadowChatPrivacySection.rules.rawValue
        case .reset: return ShadowChatPrivacySection.reset.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .read: return 0
        case .activity: return 1
        case .explanation: return 2
        case .reset: return 3
        }
    }

    static func < (lhs: ShadowChatPrivacyEntry, rhs: ShadowChatPrivacyEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ShadowChatPrivacyArguments
        switch self {
        case let .read(value):
            return ItemListDisclosureItem(presentationData: presentationData, title: "Прочтения", label: shadowPrivacyLabel(value), sectionId: self.section, style: .blocks, action: { arguments.updateRead(shadowPrivacyNext(value)) })
        case let .activity(value):
            return ItemListDisclosureItem(presentationData: presentationData, title: "Набор текста и отправка", label: shadowPrivacyLabel(value), sectionId: self.section, style: .blocks, action: { arguments.updateActivity(shadowPrivacyNext(value)) })
        case .explanation:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Нажмите на строку, чтобы выбрать: как в общих настройках, разрешать или скрывать. Явная команда «Прочитать» в меню сообщения всё равно отправляет только выбранную границу."), sectionId: self.section)
        case .reset:
            return ItemListActionItem(presentationData: presentationData, title: "Сбросить к общим настройкам", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: arguments.reset)
        }
    }
}

private final class ShadowChatPrivacyArguments {
    let updateRead: (ShadowChatPrivacyValue) -> Void
    let updateActivity: (ShadowChatPrivacyValue) -> Void
    let reset: () -> Void

    init(updateRead: @escaping (ShadowChatPrivacyValue) -> Void, updateActivity: @escaping (ShadowChatPrivacyValue) -> Void, reset: @escaping () -> Void) {
        self.updateRead = updateRead
        self.updateActivity = updateActivity
        self.reset = reset
    }
}

private func shadowPrivacyLabel(_ value: ShadowChatPrivacyValue) -> String {
    switch value {
    case .inherit: return "Как в общих настройках"
    case .allow: return "Разрешать"
    case .hide: return "Скрывать"
    }
}

private func shadowPrivacyNext(_ value: ShadowChatPrivacyValue) -> ShadowChatPrivacyValue {
    switch value {
    case .inherit: return .allow
    case .allow: return .hide
    case .hide: return .inherit
    }
}

public func shadowChatPrivacyController(context: AccountContext, peerId: EnginePeer.Id, title: String) -> ViewController {
    let key = String(peerId.toInt64())
    let update: (@escaping (inout ShadowChatPrivacyRule) -> Void) -> Void = { f in
        let _ = updateAyuGramSettings(postbox: context.account.postbox) { current in
            var current = current
            var rule = current.chatPrivacyRules[key] ?? ShadowChatPrivacyRule()
            f(&rule)
            if rule.isDefault {
                current.chatPrivacyRules.removeValue(forKey: key)
            } else {
                current.chatPrivacyRules[key] = rule
            }
            return current
        }.startStandalone()
    }
    let arguments = ShadowChatPrivacyArguments(updateRead: { value in
        update { $0.readReceipts = value }
    }, updateActivity: { value in
        update { $0.inputActivity = value }
    }, reset: {
        let _ = updateAyuGramSettings(postbox: context.account.postbox) { current in
            var current = current
            current.chatPrivacyRules.removeValue(forKey: key)
            return current
        }.startStandalone()
    })

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, ayuGramSettings(postbox: context.account.postbox))
    |> deliverOnMainQueue
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let rule = settings.chatPrivacyRules[key] ?? ShadowChatPrivacyRule()
        let entries: [ShadowChatPrivacyEntry] = [.read(rule.readReceipts), .activity(rule.inputActivity), .explanation, .reset]
        let state = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Правила Shadow"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (state, (ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true), arguments))
    }
    return ItemListController(context: context, state: signal)
}

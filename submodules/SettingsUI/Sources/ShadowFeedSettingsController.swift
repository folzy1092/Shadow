import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

// Shadow: «Лента (бета)» settings — the tab on/off, where it goes in the
// bottom bar (ShadowFeed.Position) and what it shows. The same switches are in
// the feed's own «⋯» sheet. Subscriptions to feed-only collections are edited
// in the feed (TelegramUI/ShadowFeedController).

private enum ShadowFeedSettingsEntry: ItemListNodeEntry {
    case enabled(Bool)
    case enabledInfo
    case positionHeader
    case position(Int32, String, Bool)
    case optionsHeader
    case autoplay(Bool)
    case folders(Bool)
    case muted(Bool)
    case archived(Bool)
    case markRead(Bool)
    case restoreHidden(Int)
    case info

    var section: ItemListSectionId {
        switch self {
        case .enabled, .enabledInfo:
            return 0
        case .positionHeader, .position:
            return 1
        case .optionsHeader, .autoplay, .folders, .muted, .archived, .markRead, .restoreHidden, .info:
            return 2
        }
    }

    // Also the setting links' entryId (ShadowSettingLinks, screen "feed").
    var stableId: Int32 {
        switch self {
        case .enabled: return 1
        case .enabledInfo: return 2
        case .positionHeader: return 20
        case let .position(value, _, _):
            if value == 0 {
                return 3
            }
            return value == 1 ? 5 : 6
        case .optionsHeader: return 30
        case .autoplay: return 7
        case .folders: return 8
        case .muted: return 9
        case .archived: return 10
        case .markRead: return 11
        case .restoreHidden: return 12
        case .info: return 40
        }
    }

    // Display order (stable ids are link ids, not positions).
    private var sortKey: Int {
        switch self {
        case .enabled: return 0
        case .enabledInfo: return 1
        case .positionHeader: return 2
        case let .position(value, _, _): return 3 + Int(value)
        case .optionsHeader: return 10
        case .autoplay: return 11
        case .folders: return 12
        case .muted: return 13
        case .archived: return 14
        case .markRead: return 15
        case .restoreHidden: return 16
        case .info: return 17
        }
    }

    static func < (lhs: ShadowFeedSettingsEntry, rhs: ShadowFeedSettingsEntry) -> Bool {
        return lhs.sortKey < rhs.sortKey
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ShadowFeedSettingsArguments
        switch self {
        case let .enabled(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Лента (бета)", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { $0.feedEnabled = value }
            })
        case .enabledInfo:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Вкладка внизу с постами всех ваших каналов одной лентой, новые сверху, как в Twitter. Только то, что уже загружено на телефоне, реклама не попадает никогда. Нажмите на пост — откроется канал, «назад» вернёт в ленту."), sectionId: self.section)
        case .positionHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ГДЕ КНОПКА", sectionId: self.section)
        case let .position(value, title, checked):
            return ItemListCheckboxItem(presentationData: presentationData, title: title, style: .left, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.update { $0.feedPosition = value }
            })
        case .optionsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ЧТО ПОКАЗЫВАТЬ", sectionId: self.section)
        case let .autoplay(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Автозапуск видео без звука", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { $0.feedAutoplay = value }
            })
        case let .folders(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Папки Telegram как вкладки", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { $0.feedShowFolders = value }
            })
        case let .muted(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Каналы без звука", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { $0.feedIncludeMuted = value }
            })
        case let .archived(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Каналы из архива", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { $0.feedIncludeArchived = value }
            })
        case let .markRead(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Отмечать прочитанным в канале", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { $0.feedMarkRead = value }
            })
        case let .restoreHidden(count):
            return ItemListActionItem(presentationData: presentationData, title: "Вернуть убранные каналы (\(count))", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.restoreHidden()
            })
        case .info:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Видео запускается само, когда секунду стоит в середине экрана. Свои подборки каналов («СМИ», «Игры») и порядок вкладок над лентой — в самой ленте: «⋯» → «Подборки и порядок вкладок»."), sectionId: self.section)
        }
    }
}

private final class ShadowFeedSettingsArguments {
    let update: (@escaping (inout AyuGramSettings) -> Void) -> Void
    let restoreHidden: () -> Void

    init(update: @escaping (@escaping (inout AyuGramSettings) -> Void) -> Void, restoreHidden: @escaping () -> Void) {
        self.update = update
        self.restoreHidden = restoreHidden
    }
}

public func shadowFeedSettingsController(context: AccountContext) -> ViewController {
    return shadowFeedSettingsController(context: context, focus: nil)
}

func shadowFeedSettingsController(context: AccountContext, focus: ShadowSettingsSearchItem?) -> ViewController {
    let linkRows = ShadowSettingsLinkRows()
    var focusedIndex: Int?
    let accountPeerId = context.account.peerId.toInt64()
    let hiddenRevision = ValuePromise<Int>(0, ignoreRepeated: false)
    var hiddenRevisionValue = 0
    let arguments = ShadowFeedSettingsArguments(update: { f in
        let _ = updateAyuGramSettings(postbox: context.account.postbox) { current in
            var current = current
            f(&current)
            return current
        }.startStandalone()
    }, restoreHidden: {
        ShadowFeedStore.shared.clearHiddenChannels(accountPeerId: accountPeerId)
        hiddenRevisionValue += 1
        hiddenRevision.set(hiddenRevisionValue)
    })

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, ayuGramSettings(postbox: context.account.postbox), hiddenRevision.get())
    |> map { presentationData, settings, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [ShadowFeedSettingsEntry] = [.enabled(settings.feedEnabled), .enabledInfo, .positionHeader]
        let position = ShadowFeed.Position.normalized(settings.feedPosition)
        for item in ShadowFeed.Position.allCases {
            entries.append(.position(item.rawValue, item.title, item == position))
        }
        entries += [.optionsHeader, .autoplay(settings.feedAutoplay), .folders(settings.feedShowFolders), .muted(settings.feedIncludeMuted), .archived(settings.feedIncludeArchived), .markRead(settings.feedMarkRead)]
        let hiddenCount = ShadowFeedStore.shared.hiddenChannels(accountPeerId: accountPeerId).count
        if hiddenCount > 0 {
            entries.append(.restoreHidden(hiddenCount))
        }
        entries.append(.info)
        linkRows.stableIds = entries.map { $0.stableId }
        focusedIndex = shadowSettingsFocusIndex(stableIds: entries.map { $0.stableId }, target: focus)
        let state = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Лента"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (state, (ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true), arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    shadowSettingsInstallLinkMenu(controller: controller, context: context, screen: "feed", rows: linkRows)
    if focus != nil {
        shadowSettingsInstallFocus(controller: controller, index: { focusedIndex }, color: shadowSettingsPulseColor(context.sharedContext.currentPresentationData.with { $0 }.theme))
    }
    return controller
}

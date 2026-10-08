import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext
import PresentationDataUtils
import UndoUI

// Shadow: links to settings toggles (ShadowSettingLinks) — opening one with
// focus, changing one from a link, and the long-press menu of every toggle.

// The rows currently shown by a settings screen, by index (for the long-press
// menu). Each screen writes it in its state signal.
final class ShadowSettingsLinkRows {
    var stableIds: [Int32] = []
}

func shadowSettingLinkFocusItem(_ setting: ShadowSettingLink) -> ShadowSettingsSearchItem {
    return ShadowSettingsSearchItem(destination: .customization, entryId: setting.entryId, title: setting.title, description: "", keywords: "", parentEntryId: setting.parentEntryId)
}

// The settings screen of a toggle, scrolled to it with a pulse.
func shadowSettingLinkController(context: AccountContext, setting: ShadowSettingLink) -> ViewController? {
    let focus = shadowSettingLinkFocusItem(setting)
    switch setting.screen {
    case "ghost": return shadowSettingsSearchDestinationController(context: context, item: ShadowSettingsSearchItem(destination: .ghost, entryId: setting.entryId, title: setting.title, description: "", keywords: "", parentEntryId: setting.parentEntryId))
    case "spy": return ayuSpyController(context: context, focus: focus)
    case "customization": return ayuCustomizationController(context: context, focus: focus)
    case "profile": return ayuMiscController(context: context, focus: focus)
    case "misc": return shadowMiscController(context: context, focus: focus)
    case "filters": return shadowMessageFiltersController(context: context, focus: focus)
    case "screenshot": return shadowMessageScreenshotSettingsController(context: context, focus: focus)
    case "locks": return shadowChatLocksController(context: context, focus: focus)
    case "space": return shadowSecondSpaceController(context: context, focus: focus)
    case "stats": return shadowChatStatsListController(context: context)
    case "feed": return shadowFeedSettingsController(context: context, focus: ShadowSettingsSearchItem(destination: .feed, entryId: setting.entryId, title: setting.title, description: "", keywords: ""))
    default: return nil
    }
}

private func shadowSettingLinkToast(context: AccountContext, text: String) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    context.sharedContext.mainWindow?.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), on: .root)
}

// Opened from a message, a browser or another app (ShadowLinkRouter): a link
// that changes a toggle asks first. Protected toggles only open.
func shadowOpenSettingLink(context: AccountContext, setting: ShadowSettingLink, mode: ShadowSettingLinks.Mode, navigationController: NavigationController) {
    let open: () -> Void = {
        if let controller = shadowSettingLinkController(context: context, setting: setting) {
            navigationController.pushViewController(controller)
        }
    }
    if mode == .open {
        open()
        return
    }
    if case let .value(value) = mode {
        guard setting.isChoice, let key = setting.key, let valueTitle = setting.choiceTitle(value) else {
            open()
            return
        }
        let current = ShadowSettingsTransfer.intValue(key, in: currentAyuGramSettings(accountId: context.account.id)) ?? 0
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let text = "«\(setting.title)»: \(setting.choiceTitle(current) ?? "\(current)") → \(valueTitle)\n\nСсылка: \(setting.link(mode))"
        let alert = textAlertController(context: context, title: "Изменить настройку?", text: text, actions: [
            TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
            TextAlertAction(type: .defaultAction, title: "Изменить", action: {
                let _ = (updateAyuGramSettings(postbox: context.account.postbox, { settings in
                    var settings = settings
                    ShadowSettingsTransfer.setInt(key, value, in: &settings)
                    return settings
                })
                |> deliverOnMainQueue).startStandalone(completed: {
                    open()
                })
            })
        ])
        context.sharedContext.mainWindow?.present(alert, on: .root)
        return
    }
    guard setting.isSwitchable, let key = setting.key else {
        open()
        shadowSettingLinkToast(context: context, text: "«\(setting.title)» по ссылке не меняется — только вручную.")
        return
    }
    let current = ShadowSettingsTransfer.boolValue(key, in: currentAyuGramSettings(accountId: context.account.id)) ?? false
    let target: Bool
    switch mode {
    case .on: target = true
    case .off: target = false
    default: target = !current
    }
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let text = "«\(setting.title)»: \(current ? "вкл" : "выкл") → \(target ? "вкл" : "выкл")\n\nСсылка: \(setting.link(mode))"
    let alert = textAlertController(context: context, title: "Изменить настройку?", text: text, actions: [
        TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
        TextAlertAction(type: .defaultAction, title: target ? "Включить" : "Выключить", action: {
            let _ = (updateAyuGramSettings(postbox: context.account.postbox, { settings in
                var settings = settings
                ShadowSettingsTransfer.setBool(key, target, in: &settings)
                return settings
            })
            |> deliverOnMainQueue).startStandalone(completed: {
                open()
            })
        })
    ])
    context.sharedContext.mainWindow?.present(alert, on: .root)
}

// Long press on a toggle row: copy its links.
private final class ShadowSettingsLinkMenuGesture: NSObject, UIGestureRecognizerDelegate {
    let shouldBegin: (CGPoint) -> Bool
    let began: (CGPoint) -> Void

    init(shouldBegin: @escaping (CGPoint) -> Bool, began: @escaping (CGPoint) -> Void) {
        self.shouldBegin = shouldBegin
        self.began = began
    }

    @objc func handle(_ recognizer: UILongPressGestureRecognizer) {
        if recognizer.state == .began {
            self.began(recognizer.location(in: recognizer.view))
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return self.shouldBegin(gestureRecognizer.location(in: gestureRecognizer.view))
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}

private var shadowSettingsLinkMenuKey: UInt8 = 0

func shadowSettingsInstallLinkMenu(controller: ItemListController, context: AccountContext, screen: String, rows: ShadowSettingsLinkRows) {
    let findSetting: (CGPoint) -> ShadowSettingLink? = { [weak controller] point in
        guard let controller, controller.isNodeLoaded else {
            return nil
        }
        let view = controller.displayNode.view
        var result: ShadowSettingLink?
        controller.forEachItemNode { node in
            guard result == nil, let index = node.index, index < rows.stableIds.count else {
                return
            }
            let frame = node.view.convert(node.view.bounds, to: view)
            if frame.contains(point) {
                result = ShadowSettingLinks.find(screen: screen, entryId: rows.stableIds[index])
            }
        }
        return result
    }

    let showMenu: (ShadowSettingLink) -> Void = { [weak controller] setting in
        guard let controller else {
            return
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let actionSheet = ActionSheetController(presentationData: presentationData)
        let copy: (String, String) -> Void = { link, text in
            UIPasteboard.general.string = link
            shadowSettingLinkToast(context: context, text: text)
        }
        // Shadow: the long press doubles as the short help of the setting
        // (its search-index description).
        let destinations: [String: ShadowSettingsSearchDestination] = ["customization": .customization, "spy": .spy, "ghost": .ghost, "profile": .misc, "misc": .pushDiagnostics, "filters": .filters, "locks": .chatLocks, "space": .secondSpace, "feed": .feed, "stats": .chatStats]
        let help = destinations[screen].flatMap { destination in ShadowSettingsSearchIndex.items.first(where: { $0.destination == destination && $0.entryId == setting.entryId }) }?.description ?? ""
        var items: [ActionSheetItem] = [ActionSheetTextItem(title: setting.title + (help.isEmpty ? "" : "\n\n" + help) + "\n\n" + setting.link(.open), parseMarkdown: false)]
        if setting.isSwitchable, let key = setting.key {
            items.append(ActionSheetButtonItem(title: "Скопировать ссылку-переключатель", color: .accent, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                copy(setting.link(.toggle), "Ссылка-переключатель скопирована")
            }))
            items.append(ActionSheetButtonItem(title: "Скопировать путь к настройке", color: .accent, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                copy(setting.link(.open), "Путь к настройке скопирован")
            }))
            let value = ShadowSettingsTransfer.boolValue(key, in: currentAyuGramSettings(accountId: context.account.id)) ?? false
            items.append(ActionSheetButtonItem(title: "Скопировать с текущим значением (\(value ? "вкл" : "выкл"))", color: .accent, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                copy(setting.link(value ? .on : .off), "Ссылка со значением «\(value ? "вкл" : "выкл")» скопирована")
            }))
        } else if setting.isChoice, let key = setting.key {
            items.append(ActionSheetButtonItem(title: "Скопировать путь к настройке", color: .accent, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                copy(setting.link(.open), "Путь к настройке скопирован")
            }))
            let value = ShadowSettingsTransfer.intValue(key, in: currentAyuGramSettings(accountId: context.account.id)) ?? 0
            let valueTitle = setting.choiceTitle(value) ?? "\(value)"
            items.append(ActionSheetButtonItem(title: "Скопировать с текущим значением (\(valueTitle))", color: .accent, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                copy(setting.link(.value(value)), "Ссылка со значением «\(valueTitle)» скопирована")
            }))
        } else {
            items.append(ActionSheetButtonItem(title: "Скопировать путь к настройке", color: .accent, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                copy(setting.link(.open), "Путь к настройке скопирован")
            }))
            if setting.isProtected {
                items.append(ActionSheetTextItem(title: "Эта настройка защищает данные, поэтому ссылкой её не переключить.", parseMarkdown: false))
            } else {
                items.append(ActionSheetTextItem(title: "Ссылка открывает эту настройку; меняется она только вручную.", parseMarkdown: false))
            }
        }
        actionSheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                })
            ])
        ])
        controller.present(actionSheet, in: .window(.root))
    }

    let install: () -> Void = { [weak controller] in
        guard let controller, controller.isNodeLoaded else {
            return
        }
        let view = controller.displayNode.view
        if objc_getAssociatedObject(view, &shadowSettingsLinkMenuKey) != nil {
            return
        }
        let handler = ShadowSettingsLinkMenuGesture(shouldBegin: { point in
            return findSetting(point) != nil
        }, began: { point in
            if let setting = findSetting(point) {
                showMenu(setting)
            }
        })
        let recognizer = UILongPressGestureRecognizer(target: handler, action: #selector(ShadowSettingsLinkMenuGesture.handle(_:)))
        recognizer.minimumPressDuration = 0.45
        recognizer.cancelsTouchesInView = true
        recognizer.delegate = handler
        view.addGestureRecognizer(recognizer)
        // The recognizer does not retain its target.
        objc_setAssociatedObject(view, &shadowSettingsLinkMenuKey, handler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    let previous = controller.didAppear
    controller.didAppear = { animated in
        previous?(animated)
        install()
    }
}

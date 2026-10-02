import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import UndoUI

// Shadow: admin-only editor for shadow-whitelist.json (ShadowDeviceAccess).
// Edits are a local draft; the admin copies the JSON and commits it on GitHub,
// so no token lives in the app.

private struct ShadowDeviceAccessState: Equatable {
    var remote: ShadowDeviceAccess.Whitelist?
    var loading: Bool = true
    var loadFailed: Bool = false
    var draft: [ShadowDeviceAccess.Device]?
    var enabled: Bool?
    var newId: String = ""
    var newNote: String = ""
    var inputRevision: Int = 0

    var devices: [ShadowDeviceAccess.Device] {
        return self.draft ?? self.remote?.devices ?? []
    }

    var isEnabled: Bool {
        return self.enabled ?? self.remote?.enabled ?? true
    }

    var whitelist: ShadowDeviceAccess.Whitelist {
        return ShadowDeviceAccess.Whitelist(enabled: self.isEnabled, devices: self.devices)
    }
}

private final class ShadowDeviceAccessArguments {
    let copyDeviceId: () -> Void
    let setEnabled: (Bool) -> Void
    let openDevice: (ShadowDeviceAccess.Device) -> Void
    let updateNewId: (String) -> Void
    let updateNewNote: (String) -> Void
    let add: () -> Void
    let copyJSON: () -> Void
    let openGitHub: () -> Void

    init(copyDeviceId: @escaping () -> Void, setEnabled: @escaping (Bool) -> Void, openDevice: @escaping (ShadowDeviceAccess.Device) -> Void, updateNewId: @escaping (String) -> Void, updateNewNote: @escaping (String) -> Void, add: @escaping () -> Void, copyJSON: @escaping () -> Void, openGitHub: @escaping () -> Void) {
        self.copyDeviceId = copyDeviceId
        self.setEnabled = setEnabled
        self.openDevice = openDevice
        self.updateNewId = updateNewId
        self.updateNewNote = updateNewNote
        self.add = add
        self.copyJSON = copyJSON
        self.openGitHub = openGitHub
    }
}

private enum ShadowDeviceAccessEntry: ItemListNodeEntry {
    case thisDevice(String)
    case thisDeviceInfo
    case enabled(Bool)
    case status(String)
    case device(Int32, ShadowDeviceAccess.Device)
    case newId(String, Int)
    case newNote(String, Int)
    case add
    case copyJSON
    case openGitHub
    case saveInfo

    var section: ItemListSectionId {
        switch self {
        case .thisDevice, .thisDeviceInfo:
            return 0
        case .enabled, .status, .device:
            return 1
        case .newId, .newNote, .add:
            return 2
        case .copyJSON, .openGitHub, .saveInfo:
            return 3
        }
    }

    var stableId: Int32 {
        switch self {
        case .thisDevice: return 0
        case .thisDeviceInfo: return 1
        case .enabled: return 2
        case .status: return 3
        case let .device(index, _): return 100 + index
        case .newId: return 10000
        case .newNote: return 10001
        case .add: return 10002
        case .copyJSON: return 10003
        case .openGitHub: return 10004
        case .saveInfo: return 10005
        }
    }

    static func < (lhs: ShadowDeviceAccessEntry, rhs: ShadowDeviceAccessEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ShadowDeviceAccessArguments
        switch self {
        case let .thisDevice(id):
            return ItemListDisclosureItem(presentationData: presentationData, title: id, label: "Скопировать", sectionId: self.section, style: .blocks, action: {
                arguments.copyDeviceId()
            })
        case .thisDeviceInfo:
            return ItemListTextItem(presentationData: presentationData, text: .plain("ID этого устройства. Хранится в Keychain и не меняется при переустановке, пока подпись та же."), sectionId: self.section)
        case let .enabled(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Проверка включена", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.setEnabled(value)
            })
        case let .status(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .device(_, device):
            return ItemListDisclosureItem(presentationData: presentationData, title: device.id, label: device.note.isEmpty ? "без заметки" : device.note, sectionId: self.section, style: .blocks, action: {
                arguments.openDevice(device)
            })
        case let .newId(value, _):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(string: ""), text: value, placeholder: "ID устройства", type: .regular(capitalization: false, autocorrection: false), clearType: .always, sectionId: self.section, textUpdated: { value in
                arguments.updateNewId(value)
            }, action: {})
        case let .newNote(value, _):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(string: ""), text: value, placeholder: "Заметка (кто это)", type: .regular(capitalization: true, autocorrection: false), clearType: .always, sectionId: self.section, textUpdated: { value in
                arguments.updateNewNote(value)
            }, action: {})
        case .add:
            return ItemListActionItem(presentationData: presentationData, title: "Добавить в список", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.add()
            })
        case .copyJSON:
            return ItemListActionItem(presentationData: presentationData, title: "Скопировать JSON", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.copyJSON()
            })
        case .openGitHub:
            return ItemListActionItem(presentationData: presentationData, title: "Открыть файл на GitHub", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.openGitHub()
            })
        case .saveInfo:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Изменения здесь — черновик. Скопируй JSON, открой файл на GitHub, замени содержимое и нажми Commit. Приложения подхватят список в течение 5–10 минут."), sectionId: self.section)
        }
    }
}

// prefillDeviceId: an id from an access request (shadow://access?id=…) put
// into the "add" field, so adding it is one tap.
public func shadowDeviceAccessController(context: AccountContext, prefillDeviceId: String? = nil) -> ViewController {
    var initialState = ShadowDeviceAccessState()
    if let prefillDeviceId {
        initialState.newId = ShadowDeviceAccess.normalize(prefillDeviceId)
    }
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((ShadowDeviceAccessState) -> ShadowDeviceAccessState) -> Void = { f in
        statePromise.set(stateValue.modify { f($0) })
    }

    var presentControllerImpl: ((ViewController) -> Void)?

    let showToast: (String) -> Void = { text in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        presentControllerImpl?(UndoOverlayController(presentationData: presentationData, content: .copy(text: text), elevatedLayout: false, animateInAsReplacement: false, action: { _ in return false }))
    }

    ShadowDeviceAccess.refresh { whitelist in
        updateState { state in
            var state = state
            state.loading = false
            if let whitelist {
                state.remote = whitelist
            } else {
                state.loadFailed = true
                state.remote = ShadowDeviceAccess.cachedWhitelist
            }
            return state
        }
    }

    let arguments = ShadowDeviceAccessArguments(copyDeviceId: {
        UIPasteboard.general.string = ShadowDeviceAccess.deviceId
        showToast("ID скопирован")
    }, setEnabled: { value in
        updateState { state in
            var state = state
            state.enabled = value
            return state
        }
    }, openDevice: { device in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let actionSheet = ActionSheetController(presentationData: presentationData)
        actionSheet.setItemGroups([
            ActionSheetItemGroup(items: [
                ActionSheetTextItem(title: device.note.isEmpty ? device.id : "\(device.note)\n\(device.id)", parseMarkdown: false),
                ActionSheetButtonItem(title: "Скопировать ID", color: .accent, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    UIPasteboard.general.string = device.id
                    showToast("ID скопирован")
                }),
                ActionSheetButtonItem(title: "Удалить из списка", color: .destructive, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    updateState { state in
                        var state = state
                        state.draft = state.devices.filter { $0.id != device.id }
                        return state
                    }
                })
            ]),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
            })])
        ])
        presentControllerImpl?(actionSheet)
    }, updateNewId: { value in
        updateState { state in
            var state = state
            state.newId = value
            return state
        }
    }, updateNewNote: { value in
        updateState { state in
            var state = state
            state.newNote = value
            return state
        }
    }, add: {
        var message: String?
        updateState { state in
            var state = state
            let device = ShadowDeviceAccess.Device(id: state.newId, note: state.newNote)
            if device.id.isEmpty {
                message = "Вставь ID устройства"
                return state
            }
            if state.devices.contains(where: { $0.id == device.id }) {
                message = "Это устройство уже в списке"
                return state
            }
            state.draft = state.devices + [device]
            state.newId = ""
            state.newNote = ""
            state.inputRevision += 1
            message = "Добавлено. Не забудь сохранить JSON на GitHub"
            return state
        }
        if let message {
            showToast(message)
        }
    }, copyJSON: {
        let whitelist = stateValue.with { $0.whitelist }
        UIPasteboard.general.string = ShadowDeviceAccess.encode(whitelist)
        showToast("JSON скопирован")
    }, openGitHub: {
        context.sharedContext.applicationBindings.openUrl(ShadowDeviceAccess.editURL.absoluteString)
    })

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, statePromise.get())
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [ShadowDeviceAccessEntry] = [.thisDevice(ShadowDeviceAccess.deviceId), .thisDeviceInfo, .enabled(state.isEnabled)]
        let changed = state.draft != nil || state.enabled != nil
        if state.loading {
            entries.append(.status("Загружаю список с GitHub…"))
        } else if state.loadFailed {
            entries.append(.status(state.remote == nil ? "Не удалось загрузить список." : "Не удалось загрузить список, показан кэш."))
        } else if changed {
            entries.append(.status("Есть несохранённые изменения. Устройств: \(state.devices.count)."))
        } else {
            entries.append(.status(state.isEnabled ? "Устройств в списке: \(state.devices.count). Остальных не пустит." : "Проверка выключена — пускает всех."))
        }
        for (index, device) in state.devices.enumerated() {
            entries.append(.device(Int32(index), device))
        }
        entries.append(.newId(state.newId, state.inputRevision))
        entries.append(.newNote(state.newNote, state.inputRevision))
        entries += [.add, .copyJSON, .openGitHub, .saveInfo]

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Доступ устройств"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}

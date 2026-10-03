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

// Shadow: admin editor for shadow-whitelist.json and release announcements
// (ShadowDeviceAccess). When the whitelist carries an `admin_url` (the worker)
// and the admin secret is stored, "Сохранить" commits straight to the repo via
// the worker; otherwise it falls back to copy-JSON + open-on-GitHub by hand.

private struct ShadowDeviceAccessState: Equatable {
    var remote: ShadowDeviceAccess.Whitelist?
    var loading: Bool = true
    var loadFailed: Bool = false
    var draft: [ShadowDeviceAccess.Device]?
    var enabled: Bool?
    var newId: String = ""
    var newNote: String = ""
    var inputRevision: Int = 0
    var saving: Bool = false
    var hasSecret: Bool = ShadowDeviceAccess.hasAdminSecret
    var secretDraft: String = ""
    // Release announce draft.
    var announceBuild: String = ""
    var announceVersion: String = ""
    var announceTitle: String = ""
    var announceNotes: String = ""
    var announceBeta: Bool = false
    var announcing: Bool = false

    var devices: [ShadowDeviceAccess.Device] {
        return self.draft ?? self.remote?.devices ?? []
    }

    var isEnabled: Bool {
        return self.enabled ?? self.remote?.enabled ?? true
    }

    var adminURL: URL? {
        return self.remote?.adminURL
    }

    var whitelist: ShadowDeviceAccess.Whitelist {
        return ShadowDeviceAccess.Whitelist(enabled: self.isEnabled, devices: self.devices, requestURL: self.remote?.requestURL, adminURL: self.remote?.adminURL)
    }
}

private final class ShadowDeviceAccessArguments {
    let copyDeviceId: () -> Void
    let setEnabled: (Bool) -> Void
    let openDevice: (ShadowDeviceAccess.Device) -> Void
    let updateNewId: (String) -> Void
    let updateNewNote: (String) -> Void
    let add: () -> Void
    let save: () -> Void
    let copyJSON: () -> Void
    let openGitHub: () -> Void
    let updateSecretDraft: (String) -> Void
    let saveSecret: () -> Void
    let clearSecret: () -> Void
    let updateAnnounce: (String, String) -> Void
    let setAnnounceBeta: (Bool) -> Void
    let announce: () -> Void

    init(copyDeviceId: @escaping () -> Void, setEnabled: @escaping (Bool) -> Void, openDevice: @escaping (ShadowDeviceAccess.Device) -> Void, updateNewId: @escaping (String) -> Void, updateNewNote: @escaping (String) -> Void, add: @escaping () -> Void, save: @escaping () -> Void, copyJSON: @escaping () -> Void, openGitHub: @escaping () -> Void, updateSecretDraft: @escaping (String) -> Void, saveSecret: @escaping () -> Void, clearSecret: @escaping () -> Void, updateAnnounce: @escaping (String, String) -> Void, setAnnounceBeta: @escaping (Bool) -> Void, announce: @escaping () -> Void) {
        self.copyDeviceId = copyDeviceId
        self.setEnabled = setEnabled
        self.openDevice = openDevice
        self.updateNewId = updateNewId
        self.updateNewNote = updateNewNote
        self.add = add
        self.save = save
        self.copyJSON = copyJSON
        self.openGitHub = openGitHub
        self.updateSecretDraft = updateSecretDraft
        self.saveSecret = saveSecret
        self.clearSecret = clearSecret
        self.updateAnnounce = updateAnnounce
        self.setAnnounceBeta = setAnnounceBeta
        self.announce = announce
    }
}

private enum ShadowDeviceAccessSection: Int32 {
    case thisDevice
    case list
    case add
    case save
    case secret
    case announce
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
    case save(Bool, Bool)
    case copyJSON
    case openGitHub
    case saveInfo
    case secretField(String, Int)
    case secretAction(Bool)
    case secretInfo
    case announceHeader
    case announceBuild(String, Int)
    case announceVersion(String, Int)
    case announceTitle(String, Int)
    case announceNotes(String, Int)
    case announceBeta(Bool)
    case announceAction(Bool)
    case announceInfo

    var section: ItemListSectionId {
        switch self {
        case .thisDevice, .thisDeviceInfo:
            return ShadowDeviceAccessSection.thisDevice.rawValue
        case .enabled, .status, .device:
            return ShadowDeviceAccessSection.list.rawValue
        case .newId, .newNote, .add:
            return ShadowDeviceAccessSection.add.rawValue
        case .save, .copyJSON, .openGitHub, .saveInfo:
            return ShadowDeviceAccessSection.save.rawValue
        case .secretField, .secretAction, .secretInfo:
            return ShadowDeviceAccessSection.secret.rawValue
        case .announceHeader, .announceBuild, .announceVersion, .announceTitle, .announceNotes, .announceBeta, .announceAction, .announceInfo:
            return ShadowDeviceAccessSection.announce.rawValue
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
        case .save: return 10003
        case .copyJSON: return 10004
        case .openGitHub: return 10005
        case .saveInfo: return 10006
        case .secretField: return 10007
        case .secretAction: return 10008
        case .secretInfo: return 10009
        case .announceHeader: return 10010
        case .announceBuild: return 10011
        case .announceVersion: return 10012
        case .announceTitle: return 10013
        case .announceNotes: return 10014
        case .announceBeta: return 10015
        case .announceAction: return 10016
        case .announceInfo: return 10017
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
            let label = (device.admin ? "админ · " : "") + (device.note.isEmpty ? "без заметки" : device.note)
            return ItemListDisclosureItem(presentationData: presentationData, title: device.id, label: label, sectionId: self.section, style: .blocks, action: {
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
        case let .save(enabled, saving):
            return ItemListActionItem(presentationData: presentationData, title: saving ? "Сохраняю…" : "Сохранить", kind: enabled ? .generic : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                if enabled {
                    arguments.save()
                }
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
            return ItemListTextItem(presentationData: presentationData, text: .plain("«Сохранить» коммитит список в репозиторий через бота, если задан ключ администратора. Иначе скопируй JSON, открой файл на GitHub, вставь и нажми Commit. Приложения подхватят список за 5–10 минут."), sectionId: self.section)
        case let .secretField(value, _):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(string: ""), text: value, placeholder: "Ключ администратора", type: .regular(capitalization: false, autocorrection: false), clearType: .always, sectionId: self.section, textUpdated: { value in
                arguments.updateSecretDraft(value)
            }, action: {})
        case let .secretAction(hasSecret):
            return ItemListActionItem(presentationData: presentationData, title: hasSecret ? "Удалить ключ" : "Сохранить ключ", kind: hasSecret ? .destructive : .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                if hasSecret {
                    arguments.clearSecret()
                } else {
                    arguments.saveSecret()
                }
            })
        case .secretInfo:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Ключ бота для сохранения без GitHub. Вводится один раз, хранится в Keychain этого устройства."), sectionId: self.section)
        case .announceHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ОБЪЯВИТЬ СБОРКУ", sectionId: self.section)
        case let .announceBuild(value, _):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(string: "Сборка"), text: value, placeholder: "номер сборки", type: .number, clearType: .always, sectionId: self.section, textUpdated: { value in
                arguments.updateAnnounce("build", value)
            }, action: {})
        case let .announceVersion(value, _):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(string: "Версия"), text: value, placeholder: "12.9.2-1.0.0", type: .regular(capitalization: false, autocorrection: false), clearType: .always, sectionId: self.section, textUpdated: { value in
                arguments.updateAnnounce("version", value)
            }, action: {})
        case let .announceTitle(value, _):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(string: "Заголовок"), text: value, placeholder: "что нового", type: .regular(capitalization: true, autocorrection: true), clearType: .always, sectionId: self.section, textUpdated: { value in
                arguments.updateAnnounce("title", value)
            }, action: {})
        case let .announceNotes(value, _):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(string: "Заметки"), text: value, placeholder: "строки через \\n", type: .regular(capitalization: true, autocorrection: true), clearType: .always, sectionId: self.section, textUpdated: { value in
                arguments.updateAnnounce("notes", value)
            }, action: {})
        case let .announceBeta(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "В бету", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.setAnnounceBeta(value)
            })
        case let .announceAction(announcing):
            return ItemListActionItem(presentationData: presentationData, title: announcing ? "Объявляю…" : "Объявить", kind: announcing ? .disabled : .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                if !announcing {
                    arguments.announce()
                }
            })
        case .announceInfo:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Объявляет сборку в выбранной ветке (stable или бета) через бота. Друзьям покажется обновление. Номер сборки смотри в заголовке релиза."), sectionId: self.section)
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
    initialState.announceVersion = ShadowVersion.full
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((ShadowDeviceAccessState) -> ShadowDeviceAccessState) -> Void = { f in
        statePromise.set(stateValue.modify { f($0) })
    }

    var presentControllerImpl: ((ViewController) -> Void)?
    var dismissInputImpl: (() -> Void)?

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

    // Describe the result of a worker write to the user.
    let handleAdminResult: (ShadowDeviceAccess.AdminResult, String) -> Bool = { result, successText in
        switch result {
        case .success:
            showToast(successText)
            return true
        case .noEndpoint:
            showToast("Нет адреса бота. Сохрани через GitHub вручную.")
        case .noSecret:
            showToast("Сначала задай ключ администратора.")
        case .unauthorized:
            showToast("Неверный ключ администратора.")
        case let .failed(reason):
            showToast("Не удалось: \(reason)")
        }
        return false
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
                ActionSheetButtonItem(title: device.admin ? "Убрать из админов" : "Сделать админом", color: .accent, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    updateState { state in
                        var state = state
                        state.draft = state.devices.map { item in
                            item.id == device.id ? ShadowDeviceAccess.Device(id: item.id, note: item.note, admin: !device.admin) : item
                        }
                        return state
                    }
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
            message = "Добавлено. Нажми «Сохранить»"
            return state
        }
        if let message {
            showToast(message)
        }
    }, save: {
        dismissInputImpl?()
        let whitelist = stateValue.with { $0.whitelist }
        if whitelist.adminURL != nil && ShadowDeviceAccess.hasAdminSecret {
            updateState { state in var state = state; state.saving = true; return state }
            ShadowDeviceAccess.saveWhitelist(whitelist) { result in
                let ok = handleAdminResult(result, "Сохранено")
                updateState { state in
                    var state = state
                    state.saving = false
                    if ok {
                        state.remote = whitelist
                        state.draft = nil
                        state.enabled = nil
                    }
                    return state
                }
                if ok {
                    ShadowDeviceAccess.refresh { _ in }
                }
            }
        } else {
            UIPasteboard.general.string = ShadowDeviceAccess.encode(whitelist)
            context.sharedContext.applicationBindings.openUrl(ShadowDeviceAccess.editURL.absoluteString)
            showToast("JSON скопирован — вставь на GitHub и Commit")
        }
    }, copyJSON: {
        let whitelist = stateValue.with { $0.whitelist }
        UIPasteboard.general.string = ShadowDeviceAccess.encode(whitelist)
        showToast("JSON скопирован")
    }, openGitHub: {
        context.sharedContext.applicationBindings.openUrl(ShadowDeviceAccess.editURL.absoluteString)
    }, updateSecretDraft: { value in
        updateState { state in var state = state; state.secretDraft = value; return state }
    }, saveSecret: {
        dismissInputImpl?()
        let value = stateValue.with { $0.secretDraft }
        ShadowDeviceAccess.setAdminSecret(value)
        updateState { state in
            var state = state
            state.hasSecret = ShadowDeviceAccess.hasAdminSecret
            state.secretDraft = ""
            return state
        }
        showToast("Ключ сохранён")
    }, clearSecret: {
        ShadowDeviceAccess.setAdminSecret(nil)
        updateState { state in
            var state = state
            state.hasSecret = false
            return state
        }
        showToast("Ключ удалён")
    }, updateAnnounce: { field, value in
        updateState { state in
            var state = state
            switch field {
            case "build": state.announceBuild = value
            case "version": state.announceVersion = value
            case "title": state.announceTitle = value
            case "notes": state.announceNotes = value
            default: break
            }
            return state
        }
    }, setAnnounceBeta: { value in
        updateState { state in var state = state; state.announceBeta = value; return state }
    }, announce: {
        dismissInputImpl?()
        let snapshot = stateValue.with { $0 }
        guard let build = Int(snapshot.announceBuild.trimmingCharacters(in: .whitespaces)), build > 0 else {
            showToast("Укажи номер сборки")
            return
        }
        let title = snapshot.announceTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty {
            showToast("Укажи заголовок")
            return
        }
        let version = snapshot.announceVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = snapshot.announceNotes.replacingOccurrences(of: "\\n", with: "\n")
        let channel = snapshot.announceBeta ? "beta" : "stable"
        updateState { state in var state = state; state.announcing = true; return state }
        ShadowDeviceAccess.announce(adminURL: snapshot.adminURL, channel: channel, build: build, version: version, title: title, notes: notes) { result in
            let ok = handleAdminResult(result, snapshot.announceBeta ? "Бета объявлена" : "Сборка объявлена")
            updateState { state in
                var state = state
                state.announcing = false
                if ok {
                    state.announceTitle = ""
                    state.announceNotes = ""
                    state.inputRevision += 1
                }
                return state
            }
        }
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
        entries.append(.add)
        entries.append(.save(changed && !state.saving, state.saving))
        entries += [.copyJSON, .openGitHub, .saveInfo]

        // Admin secret and release announce only make sense with a worker endpoint.
        if state.adminURL != nil {
            entries.append(.secretField(state.secretDraft, state.inputRevision))
            entries.append(.secretAction(state.hasSecret))
            entries.append(.secretInfo)
            if state.hasSecret {
                entries.append(.announceHeader)
                entries.append(.announceBuild(state.announceBuild, state.inputRevision))
                entries.append(.announceVersion(state.announceVersion, state.inputRevision))
                entries.append(.announceTitle(state.announceTitle, state.inputRevision))
                entries.append(.announceNotes(state.announceNotes, state.inputRevision))
                entries.append(.announceBeta(state.announceBeta))
                entries.append(.announceAction(state.announcing))
                entries.append(.announceInfo)
            }
        }

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Доступ устройств"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    dismissInputImpl = { [weak controller] in
        controller?.view.endEditing(true)
    }
    return controller
}

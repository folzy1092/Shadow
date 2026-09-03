import Foundation
import UIKit
import Display
import AlertUI
import PresentationDataUtils
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext

private func screenshotBackgroundTitle(_ value: ShadowMessageScreenshotSettings.Background) -> String {
    switch value {
    case .chat: return "Фон чата / тема"
    case .customImage: return "Своя картинка"
    case .white: return "Белый"
    case .black: return "Чёрный"
    }
}

private enum ScreenshotSettingEntry: ItemListNodeEntry {
    case enabled(Bool), background(ShadowMessageScreenshotSettings.Background), image
    case avatars(Bool), names(Bool), badges(Bool), time(Bool), info

    var section: ItemListSectionId { return 0 }
    var stableId: Int32 {
        switch self {
        case .enabled: return 0
        case .background: return 1
        case .image: return 2
        case .avatars: return 3
        case .names: return 4
        case .badges: return 5
        case .time: return 6
        case .info: return 7
        }
    }
    static func < (lhs: Self, rhs: Self) -> Bool { return lhs.stableId < rhs.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let actions = arguments as! ScreenshotSettingsActions
        let title: String
        let value: Bool
        let path: WritableKeyPath<ShadowMessageScreenshotSettings, Bool>
        switch self {
        case let .enabled(flag): title = "Кнопка скриншота при выделении"; value = flag; path = \.enabled
        case let .avatars(flag): title = "Аватары"; value = flag; path = \.showAvatars
        case let .names(flag): title = "Имена авторов"; value = flag; path = \.showNames
        case let .badges(flag): title = "Значки рядом с именем"; value = flag; path = \.showBadges
        case let .time(flag): title = "Время и статус сообщения"; value = flag; path = \.showTime
        case let .background(background):
            return ItemListDisclosureItem(presentationData: presentationData, title: "Фон", label: screenshotBackgroundTitle(background), sectionId: 0, style: .blocks, action: actions.selectBackground)
        case .image:
            return ItemListActionItem(presentationData: presentationData, title: "Выбрать свою картинку", kind: .generic, alignment: .natural, sectionId: 0, style: .blocks, action: actions.selectImage)
        case .info:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Выдели сообщения и нажми камеру рядом с анонимной пересылкой. Откроется предпросмотр одного изображения. Видео и анимации попадут в него статичным кадром. Недоступное медиа останется заглушкой. Настройки отдельны для каждого аккаунта."), sectionId: 0)
        }
        return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, sectionId: 0, style: .blocks, updated: { flag in
            actions.update { $0[keyPath: path] = flag }
        })
    }
}

private final class ScreenshotSettingsActions: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    let context: AccountContext
    weak var controller: ViewController?
    private let updateDisposable = MetaDisposable()

    init(context: AccountContext) { self.context = context }
    deinit { self.updateDisposable.dispose() }

    func update(_ change: @escaping (inout ShadowMessageScreenshotSettings) -> Void) {
        self.updateDisposable.set(updateAyuGramSettings(postbox: self.context.account.postbox) { settings in
            var settings = settings
            change(&settings.messageScreenshot)
            return settings
        }.start())
    }

    func selectBackground() {
        let data = self.context.sharedContext.currentPresentationData.with { $0 }
        let sheet = ActionSheetController(presentationData: data)
        let options: [ActionSheetItem] = ShadowMessageScreenshotSettings.Background.allCases.map { background in
            ActionSheetButtonItem(title: screenshotBackgroundTitle(background), action: { [weak self, weak sheet] in
                sheet?.dismissAnimated()
                self?.update { $0.background = background }
            })
        }
        sheet.setItemGroups([ActionSheetItemGroup(items: options), ActionSheetItemGroup(items: [ActionSheetButtonItem(title: data.strings.Common_Cancel, action: { [weak sheet] in sheet?.dismissAnimated() })])])
        self.controller?.present(sheet, in: .window(.root))
    }

    func selectImage() {
        guard var presenter = self.controller?.view.window?.rootViewController else { return }
        while let next = presenter.presentedViewController { presenter = next }
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.mediaTypes = ["public.image"]
        picker.delegate = self
        presenter.present(picker, animated: true)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        guard let original = info[.originalImage] as? UIImage else { picker.dismiss(animated: true); return }
        // Bound the stored background's resolution, regardless of camera resolution.
        let ratio = min(1.0, 2048.0 / max(original.size.width, original.size.height))
        let size = CGSize(width: max(1, original.size.width * ratio), height: max(1, original.size.height * ratio))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in original.draw(in: CGRect(origin: .zero, size: size)) }
        let url = ShadowMessageScreenshotSettings.backgroundURL(mediaBoxPath: self.context.account.postbox.mediaBox.basePath)
        picker.dismiss(animated: true) { [weak self] in
            do {
                guard let data = image.jpegData(compressionQuality: 0.9) else { throw CocoaError(.fileWriteUnknown) }
                try data.write(to: url, options: .atomic)
                self?.update { $0.background = .customImage }
            } catch {
                guard let self else { return }
                self.controller?.present(textAlertController(context: self.context, title: "Фон скриншота", text: "Не удалось сохранить изображение. Предыдущий фон сохранён.", actions: [TextAlertAction(type: .defaultAction, title: "ОК", action: {})]), in: .window(.root))
            }
        }
    }
}

func shadowMessageScreenshotSettingsController(context: AccountContext) -> ViewController {
    let actions = ScreenshotSettingsActions(context: context)
    let state = combineLatest(context.sharedContext.presentationData, ayuGramSettings(postbox: context.account.postbox))
    |> deliverOnMainQueue
    |> map { data, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let options = settings.messageScreenshot
        let entries: [ScreenshotSettingEntry] = [.enabled(options.enabled), .background(options.background), .image, .avatars(options.showAvatars), .names(options.showNames), .badges(options.showBadges), .time(options.showTime), .info]
        let presentation = ItemListPresentationData(data)
        return (ItemListControllerState(presentationData: presentation, title: .text("Скриншоты сообщений"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: data.strings.Common_Back)), (ItemListNodeState(presentationData: presentation, entries: entries, style: .blocks, animateChanges: true), actions))
    }
    let controller = ItemListController(context: context, state: state)
    actions.controller = controller
    return controller
}

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
    case .chat:
        return "Фон чата / тема"
    case .customImage:
        return "Своя картинка"
    case .customColor:
        return "Свой цвет"
    }
}

private func screenshotUIColor(argb: Int32) -> UIColor {
    let value = UInt32(bitPattern: argb)
    let a = CGFloat((value >> 24) & 0xFF) / 255.0
    let r = CGFloat((value >> 16) & 0xFF) / 255.0
    let g = CGFloat((value >> 8) & 0xFF) / 255.0
    let b = CGFloat(value & 0xFF) / 255.0
    return UIColor(red: r, green: g, blue: b, alpha: a)
}

private func screenshotARGB(from color: UIColor) -> Int32 {
    var red: CGFloat = 0.0
    var green: CGFloat = 0.0
    var blue: CGFloat = 0.0
    var alpha: CGFloat = 1.0

    if !color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
        var white: CGFloat = 0.0
        if color.getWhite(&white, alpha: &alpha) {
            red = white
            green = white
            blue = white
        }
    }

    func component(_ value: CGFloat) -> UInt32 {
        return UInt32(round(max(0.0, min(1.0, value)) * 255.0))
    }

    // The picker has supportsAlpha = false. Persist an opaque ARGB value.
    let value = (UInt32(0xFF) << 24)
        | (component(red) << 16)
        | (component(green) << 8)
        | component(blue)
    return Int32(bitPattern: value)
}

private func screenshotColorHex(_ argb: Int32) -> String {
    let rgb = UInt32(bitPattern: argb) & 0x00FFFFFF
    return String(format: "#%06X", rgb)
}

private enum ScreenshotSettingEntry: ItemListNodeEntry {
    case enabled(Bool)
    case background(ShadowMessageScreenshotSettings.Background)
    case color(Int32)
    case image
    case avatars(Bool)
    case names(Bool)
    case badges(Bool)
    case time(Bool)
    case info

    var section: ItemListSectionId { return 0 }

    var stableId: Int32 {
        switch self {
        case .enabled: return 0
        case .background: return 1
        case .color: return 2
        case .image: return 3
        case .avatars: return 4
        case .names: return 5
        case .badges: return 6
        case .time: return 7
        case .info: return 8
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let actions = arguments as! ScreenshotSettingsActions
        let title: String
        let value: Bool
        let path: WritableKeyPath<ShadowMessageScreenshotSettings, Bool>

        switch self {
        case let .enabled(flag):
            title = "Кнопка скриншота при выделении"
            value = flag
            path = \.enabled
        case let .avatars(flag):
            title = "Аватары"
            value = flag
            path = \.showAvatars
        case let .names(flag):
            title = "Имена авторов"
            value = flag
            path = \.showNames
        case let .badges(flag):
            title = "Значки рядом с именем"
            value = flag
            path = \.showBadges
        case let .time(flag):
            title = "Время и статус сообщения"
            value = flag
            path = \.showTime
        case let .background(background):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                title: "Фон",
                label: screenshotBackgroundTitle(background),
                sectionId: 0,
                style: .blocks,
                action: actions.selectBackground
            )
        case let .color(argb):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                title: "Свой цвет",
                label: screenshotColorHex(argb),
                labelStyle: .color(screenshotUIColor(argb: argb)),
                sectionId: 0,
                style: .blocks,
                action: actions.selectColor
            )
        case .image:
            return ItemListActionItem(
                presentationData: presentationData,
                title: "Выбрать свою картинку",
                kind: .generic,
                alignment: .natural,
                sectionId: 0,
                style: .blocks,
                action: actions.selectImage
            )
        case .info:
            return ItemListTextItem(
                presentationData: presentationData,
                text: .plain("Выдели сообщения и нажми камеру рядом с анонимной пересылкой. Откроется предпросмотр одного изображения. Видео и анимации попадут в него статичным кадром. Недоступное медиа останется заглушкой. Настройки отдельны для каждого аккаунта."),
                sectionId: 0
            )
        }

        return ItemListSwitchItem(
            presentationData: presentationData,
            title: title,
            value: value,
            sectionId: 0,
            style: .blocks,
            updated: { flag in
                actions.update { $0[keyPath: path] = flag }
            }
        )
    }
}

private final class ScreenshotSettingsActions: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    let context: AccountContext
    weak var controller: ViewController?
    var currentColorARGB: Int32 = ShadowMessageScreenshotSettings.legacyBlackARGB
    private let updateDisposable = MetaDisposable()

    init(context: AccountContext) {
        self.context = context
    }

    deinit {
        self.updateDisposable.dispose()
    }

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
            return ActionSheetButtonItem(title: screenshotBackgroundTitle(background), action: { [weak self, weak sheet] in
                guard let self else { return }
                if background == .customColor {
                    if let sheet {
                        // Present UIKit's picker only after the Telegram action sheet is gone.
                        sheet.dismissed = { [weak self] _ in
                            self?.selectColor()
                        }
                        sheet.dismissAnimated()
                    } else {
                        self.selectColor()
                    }
                } else {
                    sheet?.dismissAnimated()
                    self.update { $0.background = background }
                }
            })
        }
        sheet.setItemGroups([
            ActionSheetItemGroup(items: options),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: data.strings.Common_Cancel, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                })
            ])
        ])
        self.controller?.present(sheet, in: .window(.root))
    }

    func selectColor() {
        if #available(iOS 14.0, *) {
            self.presentColorPicker()
        } else {
            // Keep the option visible so imported settings still render; only editing is unavailable.
            self.controller?.present(
                textAlertController(
                    context: self.context,
                    title: "Свой цвет",
                    text: "Выбор своего цвета доступен начиная с iOS 14.",
                    actions: [TextAlertAction(type: .defaultAction, title: "ОК", action: {})]
                ),
                in: .window(.root)
            )
        }
    }

    @available(iOS 14.0, *)
    private func presentColorPicker() {
        guard var presenter = self.controller?.view.window?.rootViewController else { return }
        while let next = presenter.presentedViewController {
            presenter = next
        }
        let picker = UIColorPickerViewController()
        picker.selectedColor = screenshotUIColor(argb: self.currentColorARGB)
        picker.supportsAlpha = false
        picker.delegate = self
        presenter.present(picker, animated: true)
    }

    func selectImage() {
        guard var presenter = self.controller?.view.window?.rootViewController else { return }
        while let next = presenter.presentedViewController {
            presenter = next
        }
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
        guard let original = info[.originalImage] as? UIImage else {
            picker.dismiss(animated: true)
            return
        }
        // Bound the stored background's resolution, regardless of camera resolution.
        let ratio = min(1.0, 2048.0 / max(original.size.width, original.size.height))
        let size = CGSize(width: max(1.0, original.size.width * ratio), height: max(1.0, original.size.height * ratio))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            original.draw(in: CGRect(origin: .zero, size: size))
        }
        let url = ShadowMessageScreenshotSettings.backgroundURL(mediaBoxPath: self.context.account.postbox.mediaBox.basePath)
        picker.dismiss(animated: true) { [weak self] in
            do {
                guard let data = image.jpegData(compressionQuality: 0.9) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                try data.write(to: url, options: .atomic)
                self?.update { $0.background = .customImage }
            } catch {
                guard let self else { return }
                self.controller?.present(
                    textAlertController(
                        context: self.context,
                        title: "Фон скриншота",
                        text: "Не удалось сохранить изображение. Предыдущий фон сохранён.",
                        actions: [TextAlertAction(type: .defaultAction, title: "ОК", action: {})]
                    ),
                    in: .window(.root)
                )
            }
        }
    }
}

@available(iOS 14.0, *)
extension ScreenshotSettingsActions: UIColorPickerViewControllerDelegate {
    func colorPickerViewControllerDidSelectColor(_ viewController: UIColorPickerViewController) {
        let value = screenshotARGB(from: viewController.selectedColor)
        self.currentColorARGB = value
        // This fires while the picker is open, so the settings list updates live behind it.
        self.update {
            $0.customColorARGB = value
            $0.background = .customColor
        }
    }

    func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        let value = screenshotARGB(from: viewController.selectedColor)
        self.currentColorARGB = value
        self.update {
            $0.customColorARGB = value
            $0.background = .customColor
        }
    }
}

func shadowMessageScreenshotSettingsController(context: AccountContext) -> ViewController {
    let actions = ScreenshotSettingsActions(context: context)
    let state = combineLatest(context.sharedContext.presentationData, ayuGramSettings(postbox: context.account.postbox))
    |> deliverOnMainQueue
    |> map { data, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let options = settings.messageScreenshot
        actions.currentColorARGB = options.customColorARGB
        let entries: [ScreenshotSettingEntry] = [
            .enabled(options.enabled),
            .background(options.background),
            .color(options.customColorARGB),
            .image,
            .avatars(options.showAvatars),
            .names(options.showNames),
            .badges(options.showBadges),
            .time(options.showTime),
            .info
        ]
        let presentation = ItemListPresentationData(data)
        return (
            ItemListControllerState(
                presentationData: presentation,
                title: .text("Скриншоты сообщений"),
                leftNavigationButton: nil,
                rightNavigationButton: nil,
                backNavigationButton: ItemListBackButton(title: data.strings.Common_Back)
            ),
            (
                ItemListNodeState(
                    presentationData: presentation,
                    entries: entries,
                    style: .blocks,
                    animateChanges: true
                ),
                actions
            )
        )
    }
    let controller = ItemListController(context: context, state: state)
    actions.controller = controller
    return controller
}

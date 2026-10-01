import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import OverlayStatusController
import AccountContext

// Shadow: «Экспорт чата» from the profile menu. Asks for a format, collects the
// messages stored on this device (deleted ones included) and hands the file to
// the system share sheet. The file lives in a per-export temporary directory
// that is removed when the share sheet closes.
public func shadowPresentChatExport(context: AccountContext, peerId: EnginePeer.Id, title: String, from controller: ViewController) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let actionSheet = ActionSheetController(presentationData: presentationData)
    var items: [ActionSheetItem] = [
        ActionSheetTextItem(title: "Экспортируются сообщения, сохранённые на этом устройстве, включая удалённые и старые версии правок. Медиа указываются подписью, сами файлы не входят.", parseMarkdown: false)
    ]
    for format in ShadowChatExport.Format.allCases {
        items.append(ActionSheetButtonItem(title: format.title, color: .accent, action: { [weak actionSheet, weak controller] in
            actionSheet?.dismissAnimated()
            guard let controller else {
                return
            }
            shadowRunChatExport(context: context, peerId: peerId, title: title, format: format, from: controller)
        }))
    }
    actionSheet.setItemGroups([
        ActionSheetItemGroup(items: items),
        ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
            actionSheet?.dismissAnimated()
        })])
    ])
    controller.present(actionSheet, in: .window(.root))
}

private func shadowRunChatExport(context: AccountContext, peerId: EnginePeer.Id, title: String, format: ShadowChatExport.Format, from controller: ViewController) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let progress = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: nil))
    controller.present(progress, in: .window(.root))

    let _ = (ShadowChatExportCollect.chat(postbox: context.account.postbox, peerId: peerId, title: title)
    |> deliverOn(Queue.concurrentDefaultQueue())).start(next: { [weak controller, weak progress] chat in
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("shadow-chat-export-" + UUID().uuidString, isDirectory: true)
        var file: URL?
        var failure: String?
        if chat.records.isEmpty {
            failure = "На устройстве нет сообщений этого чата."
        } else {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: nil)
                let url = directory.appendingPathComponent(ShadowChatExport.fileName(title: title, format: format))
                try ShadowChatExport.render(chat, format: format).write(to: url, options: [.atomic, .completeFileProtection])
                file = url
            } catch {
                try? FileManager.default.removeItem(at: directory)
                failure = error.localizedDescription
            }
        }
        Queue.mainQueue().async {
            progress?.dismiss()
            guard let controller, controller.isViewLoaded, let window = controller.view.window, var presenter = window.rootViewController else {
                try? FileManager.default.removeItem(at: directory)
                return
            }
            while let next = presenter.presentedViewController {
                presenter = next
            }
            guard let file else {
                let alert = UIAlertController(title: "Экспорт чата", message: failure, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: presentationData.strings.Common_OK, style: .default))
                presenter.present(alert, animated: true)
                return
            }
            let share = UIActivityViewController(activityItems: [file], applicationActivities: nil)
            share.completionWithItemsHandler = { _, _, _, _ in
                // Only the UUID directory created for this export.
                try? FileManager.default.removeItem(at: directory)
            }
            if let popover = share.popoverPresentationController {
                popover.sourceView = controller.view
                popover.sourceRect = CGRect(x: controller.view.bounds.midX, y: controller.view.bounds.midY, width: 1.0, height: 1.0)
                popover.permittedArrowDirections = []
            }
            presenter.present(share, animated: true)
        }
    })
}

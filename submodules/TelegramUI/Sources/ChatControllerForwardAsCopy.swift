import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit
import Display
import AccountContext
import PresentationDataUtils
import UndoUI

// Shadow: the chat's forward-as-copy UI over ShadowProtectedCopy (TelegramCore),
// which builds the copies of copy-protected (noforwards) or secret messages.
// The chat builds the batch behind a progress toast before it enqueues; a
// forward started anywhere else is turned into copies by enqueueMessages
// itself, without a toast.

private enum AyuCopyLimits {
    // The progress toast stays up for the whole copy and is dismissed
    // explicitly once the batch is ready.
    static let progressToastLifetime: Double = 60.0 * 60.0
}

extension ChatControllerImpl {
    typealias AyuCopyMessageBatch = ShadowProtectedCopy.Batch

    // Builds the copies behind a progress toast and hands the batch over once
    // every media item is local.
    func ayuPrepareCopyBatch(_ messages: [EngineRawMessage], threadId: Int64?, completion: @escaping (AyuCopyMessageBatch) -> Void) {
        let presentationData = self.context.sharedContext.currentPresentationData.with { $0 }
        let progressController = UndoOverlayController(presentationData: presentationData, content: ayuCopyProgressContent(percent: nil), elevatedLayout: false, action: { _ in return false })
        self.present(progressController, in: .current)

        let _ = (ShadowProtectedCopy.build(account: self.context.account, messages: messages, threadId: threadId)
        |> map { step -> ShadowProtectedCopy.Step<AyuCopyMessageBatch> in
            switch step {
            case let .progress(value):
                return .progress(Float(Int(value * 100.0)))
            case .finished:
                return step
            }
        }
        |> distinctUntilChanged(isEqual: { lhs, rhs in
            if case let .progress(lhsValue) = lhs, case let .progress(rhsValue) = rhs {
                return lhsValue == rhsValue
            }
            return false
        })
        |> deliverOnMainQueue).startStandalone(next: { [weak progressController] step in
            switch step {
            case let .progress(percent):
                if let progressController, progressController.isNodeLoaded {
                    progressController.content = ayuCopyProgressContent(percent: Int(percent))
                }
            case let .finished(batch):
                progressController?.dismiss()
                completion(batch)
            }
        })
    }

    func ayuReportUnsendableCopy(_ batch: AyuCopyMessageBatch) {
        let text: String
        if batch.failedCount > 0 {
            text = "Не скачалось медиа: \(batch.failedCount). Копия не отправлена — проверь соединение и повтори попытку."
        } else {
            text = "В выбранных сообщениях нечего скопировать: опросы, игры и истории не копируются."
        }
        let presentationData = self.context.sharedContext.currentPresentationData.with { $0 }
        self.present(textAlertController(context: self.context, title: "Не удалось переслать", text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), in: .window(.root))
    }

    func ayuPresentCopyInfo(_ text: String) {
        let presentationData = self.context.sharedContext.currentPresentationData.with { $0 }
        self.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), in: .current)
    }
}

private func ayuCopyProgressContent(percent: Int?) -> UndoOverlayContent {
    let text: String
    if let percent {
        text = "Пересылка защищена — скачиваю медиа для копии: \(percent)%"
    } else {
        text = "Пересылка защищена — готовлю копию…"
    }
    return .info(title: nil, text: text, timeout: AyuCopyLimits.progressToastLifetime, customUndoText: nil)
}

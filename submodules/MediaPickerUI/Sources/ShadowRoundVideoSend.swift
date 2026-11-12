import Foundation
import UIKit
import TelegramCore
import LegacyComponents
import MediaEditor
import ChatMediaSend

// Shadow: «отправить кружком» from the chat gallery editor. The editor marks items in
// `ChatMediaEditorItemStore.shadowRoundVideoIds`; right before sending, the mark becomes the
// VideoMessage preset in the legacy editing context, so LegacyMediaPickers converts the video
// (centered square, at most 60 s, no caption, no album). The new editor's trim and a plain crop are
// carried over; its drawings and filters are not (the editor says so when the round video is turned on).
// An item no longer marked loses a VideoMessage preset left from an earlier attempt.
func shadowApplyRoundVideoAdjustments(legacyContext: MediaPickerChatMediaSendLegacyContext, editingContext: TGMediaEditingContext?, store: ChatMediaEditorItemStore) {
    guard let editingContext else {
        return
    }
    for uniqueId in legacyContext.selectedUniqueIds {
        guard let item = legacyContext.item(for: uniqueId) as? (NSObject & TGMediaEditableItem) else {
            continue
        }
        let source = legacyContext.source(for: uniqueId, thumbnail: nil)
        if shadowRoundVideoIsActive(uniqueId: uniqueId, source: source, editing: legacyContext, store: store), let geometry = shadowRoundVideoSourceGeometry(source) {
            let pixelSize = geometry.pixelSize
            let duration = geometry.duration
            let values = store.entry(for: uniqueId)?.values
            let isPlainCrop = values.map { shadowRoundVideoIsPlainCrop($0) } ?? false
            let cropRect = shadowRoundVideoCropRect(editorCropRect: values?.cropRect, editorOriginalSize: values?.originalDimensions.cgSize ?? pixelSize, isPlainCrop: isPlainCrop, pixelSize: pixelSize)
            let trim = shadowRoundVideoTrim(trimRange: values?.videoTrimRange, duration: duration)
            if let adjustments = TGVideoEditAdjustments(originalSize: pixelSize, cropRect: cropRect, cropOrientation: .up, cropRotation: 0.0, cropLockedAspectRatio: 0.0, cropMirrored: false, trimStartValue: trim.start, trimEndValue: trim.end, toolValues: nil, paintingData: nil, sendAsGif: false, preset: TGMediaVideoConversionPresetVideoMessage) {
                editingContext.setAdjustments(adjustments, for: item)
            }
        } else if let current = editingContext.adjustments(for: item) as? TGVideoEditAdjustments, current.isRoundVideo() {
            editingContext.setAdjustments(nil, for: item)
        }
    }
}

private func shadowRoundVideoSourceGeometry(_ source: MediaPickerChatMediaSendSource?) -> (pixelSize: CGSize, duration: Double)? {
    switch source {
    case let .video(_, pixelSize, duration, _)?:
        return (pixelSize: pixelSize, duration: duration)
    case let .capturedLibraryVideo(_, pixelSize, duration, _)?:
        return (pixelSize: pixelSize, duration: duration)
    case let .capturedVideo(_, dimensions, duration)?:
        return (pixelSize: dimensions.cgSize, duration: duration)
    default:
        return nil
    }
}

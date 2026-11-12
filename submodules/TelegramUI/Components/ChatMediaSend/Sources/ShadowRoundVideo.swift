import Foundation
import CoreGraphics
import MediaEditor

// Shadow: «отправить кружком» from the chat gallery editor (13.2's ChatMediaEditorScreen).
//
// The editor keeps the flag in `ChatMediaEditorItemStore.shadowRoundVideoIds`, not in the legacy
// `TGVideoEditAdjustments`: the editor clears an item's legacy adjustments whenever it writes the
// item's edited thumbnail (`ChatMediaEditorLegacyThumbnailWriter`), which would silently drop a
// VideoMessage preset stored there. At send time the picker turns the flag into the VideoMessage
// preset (MediaPickerUI `shadowApplyRoundVideoAdjustments`) and the item goes through
// LegacyMediaPickers, which already converts it: a centered square, at most 60 s, no caption, no album.

public let shadowRoundVideoMaximumDuration: Double = 60.0

public func shadowRoundVideoButtonIsVisible(isGallery: Bool, isVideo: Bool, isAnimation: Bool, isFilePreview: Bool) -> Bool {
    return isGallery && isVideo && !isAnimation && !isFilePreview
}

public extension ChatMediaEditorItemStore {
    func shadowIsRoundVideo(_ uniqueId: String) -> Bool {
        return self.shadowRoundVideoIds.contains(uniqueId)
    }

    func shadowSetRoundVideo(_ value: Bool, for uniqueId: String) {
        if value {
            self.shadowRoundVideoIds.insert(uniqueId)
        } else {
            self.shadowRoundVideoIds.remove(uniqueId)
        }
    }
}

/// A marked item goes out as a round video only if it is a real video (not a GIF) without a price.
public func shadowRoundVideoIsActive(isMarked: Bool, source: MediaPickerChatMediaSendSource?, hasPrice: Bool) -> Bool {
    guard isMarked, !hasPrice, let source else {
        return false
    }
    switch source {
    case .video, .capturedVideo:
        return true
    case let .capturedLibraryVideo(_, _, _, isGif):
        return !isGif
    case .photo, .gif, .livePhoto, .image, .unsupported:
        return false
    }
}

public func shadowRoundVideoIsActive(uniqueId: String, source: MediaPickerChatMediaSendSource?, editing: MediaPickerChatMediaSendEditing, store: ChatMediaEditorItemStore) -> Bool {
    return shadowRoundVideoIsActive(isMarked: store.shadowIsRoundVideo(uniqueId), source: source, hasPrice: editing.price(for: uniqueId) != nil)
}

/// The trim the round video keeps: the editor's trim range (or the whole video), at most 60 s from its start.
public func shadowRoundVideoTrim(trimRange: Range<Double>?, duration: Double) -> (start: Double, end: Double) {
    var start = max(0.0, trimRange?.lowerBound ?? 0.0)
    var end = trimRange?.upperBound ?? duration
    if duration > 0.0 {
        end = min(end, duration)
    }
    if end <= start {
        start = 0.0
        end = duration
    }
    if end - start > shadowRoundVideoMaximumDuration {
        end = start + shadowRoundVideoMaximumDuration
    }
    return (start, end)
}

/// The editor's crop as a crop rect in the video's pixels, when it is a plain crop (no rotation, offset,
/// zoom, perspective or mirroring); otherwise the whole frame. The round video is the centered square
/// of this rect, which is what the editor's round preview masks.
public func shadowRoundVideoCropRect(editorCropRect: CGRect?, editorOriginalSize: CGSize, isPlainCrop: Bool, pixelSize: CGSize) -> CGRect {
    let full = CGRect(origin: .zero, size: pixelSize)
    guard isPlainCrop, let editorCropRect, editorOriginalSize.width > 0.0, editorOriginalSize.height > 0.0, pixelSize.width > 0.0, pixelSize.height > 0.0 else {
        return full
    }
    let scaleX = pixelSize.width / editorOriginalSize.width
    let scaleY = pixelSize.height / editorOriginalSize.height
    let rect = CGRect(x: editorCropRect.minX * scaleX, y: editorCropRect.minY * scaleY, width: editorCropRect.width * scaleX, height: editorCropRect.height * scaleY).intersection(full)
    if rect.isNull || rect.width < 1.0 || rect.height < 1.0 {
        return full
    }
    return rect
}

/// The circle the editor previews: the centered square of the shown media, as an inscribed circle.
public func shadowRoundVideoPreviewCircle(in bounds: CGRect) -> CGRect {
    let side = min(bounds.width, bounds.height)
    return CGRect(x: bounds.midX - side / 2.0, y: bounds.midY - side / 2.0, width: side, height: side)
}

/// A crop the round video can carry over: no rotation, offset, zoom, perspective, orientation or mirroring.
public func shadowRoundVideoIsPlainCrop(_ values: MediaEditorValues) -> Bool {
    return values.cropOffset == .zero && values.cropScale == 1.0 && values.cropRotation == 0.0 && values.cropMirroring == values.videoIsMirrored && (values.cropOrientation ?? .up) == .up && values.cropPerspective.isZero
}

/// Edits of the new editor that a round video does not carry (it keeps the trim and a plain crop).
public func shadowRoundVideoDropsEdits(_ values: MediaEditorValues) -> Bool {
    if values.drawing != nil || !values.entities.isEmpty {
        return true
    }
    if values.hasAdjustments || values.hasTint || values.hasBlur || values.hasCurves {
        return true
    }
    if values.audioTrack != nil {
        return true
    }
    return !shadowRoundVideoIsPlainCrop(values)
}

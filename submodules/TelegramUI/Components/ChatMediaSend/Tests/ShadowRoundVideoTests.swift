import Foundation
import UIKit
import XCTest
import TelegramCore
import MediaEditor
@testable import ChatMediaSend

// Shadow: «отправить кружком» from the chat gallery editor (ShadowRoundVideo.swift).

private final class RoundVideoTestSelection: MediaPickerChatMediaSendSelection {
    let selectedUniqueIds: [String]
    let grouping: Bool

    init(_ ids: [String], grouping: Bool = true) {
        self.selectedUniqueIds = ids
        self.grouping = grouping
    }
}

private final class RoundVideoTestEditing: MediaPickerChatMediaSendEditing {
    var forcedCaption: NSAttributedString?
    var isHighQualityPhoto = false
    var captions: [String: NSAttributedString] = [:]
    var prices: [String: Int64] = [:]

    func caption(for uniqueId: String) -> NSAttributedString? {
        return self.captions[uniqueId]
    }

    func timer(for uniqueId: String) -> Int32? {
        return nil
    }

    func spoiler(for uniqueId: String) -> Bool {
        return false
    }

    func price(for uniqueId: String) -> Int64? {
        return self.prices[uniqueId]
    }

    func coverImage(for uniqueId: String) -> UIImage? {
        return nil
    }

    func hasLegacyAdjustments(for uniqueId: String) -> Bool {
        return false
    }
}

final class ShadowRoundVideoTests: XCTestCase {
    private func video(_ id: String) -> MediaPickerChatMediaSendSource {
        return .video(identifier: id, pixelSize: CGSize(width: 1080.0, height: 1920.0), duration: 90.0, thumbnail: nil)
    }

    func testButtonOnlyForGalleryVideos() {
        XCTAssertTrue(shadowRoundVideoButtonIsVisible(isGallery: true, isVideo: true, isAnimation: false, isFilePreview: false))
        XCTAssertFalse(shadowRoundVideoButtonIsVisible(isGallery: false, isVideo: true, isAnimation: false, isFilePreview: false))
        XCTAssertFalse(shadowRoundVideoButtonIsVisible(isGallery: true, isVideo: false, isAnimation: false, isFilePreview: false))
        XCTAssertFalse(shadowRoundVideoButtonIsVisible(isGallery: true, isVideo: true, isAnimation: true, isFilePreview: false))
        XCTAssertFalse(shadowRoundVideoButtonIsVisible(isGallery: true, isVideo: true, isAnimation: false, isFilePreview: true))
    }

    func testOnlyMarkedRealVideosWithoutPriceGoRound() {
        XCTAssertTrue(shadowRoundVideoIsActive(isMarked: true, source: self.video("v"), hasPrice: false))
        XCTAssertFalse(shadowRoundVideoIsActive(isMarked: false, source: self.video("v"), hasPrice: false))
        XCTAssertFalse(shadowRoundVideoIsActive(isMarked: true, source: self.video("v"), hasPrice: true))
        XCTAssertFalse(shadowRoundVideoIsActive(isMarked: true, source: nil, hasPrice: false))
        XCTAssertFalse(shadowRoundVideoIsActive(isMarked: true, source: .photo(identifier: "p", pixelSize: CGSize(width: 10.0, height: 10.0), thumbnail: nil), hasPrice: false))
        XCTAssertFalse(shadowRoundVideoIsActive(isMarked: true, source: .gif(identifier: "g", pixelSize: CGSize(width: 10.0, height: 10.0), thumbnail: nil), hasPrice: false))
        XCTAssertTrue(shadowRoundVideoIsActive(isMarked: true, source: .capturedLibraryVideo(identifier: "c", pixelSize: CGSize(width: 10.0, height: 10.0), duration: 5.0, isGif: false), hasPrice: false))
        XCTAssertFalse(shadowRoundVideoIsActive(isMarked: true, source: .capturedLibraryVideo(identifier: "c", pixelSize: CGSize(width: 10.0, height: 10.0), duration: 5.0, isGif: true), hasPrice: false))
    }

    func testStoreFlag() {
        let store = ChatMediaEditorItemStore()
        XCTAssertFalse(store.shadowIsRoundVideo("v"))
        store.shadowSetRoundVideo(true, for: "v")
        XCTAssertTrue(store.shadowIsRoundVideo("v"))
        store.shadowSetRoundVideo(false, for: "v")
        XCTAssertFalse(store.shadowIsRoundVideo("v"))
    }

    // The editor's own edits give the item a store entry, which alone would send it through
    // ChatMediaSend and lose the round video; a marked video must still go through the legacy converter.
    func testMarkedVideoGoesThroughLegacyEvenWhenEditedInTheNewEditor() {
        let store = ChatMediaEditorItemStore()
        let values = chatMediaEditorValues(peerId: EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(1)), originalDimensions: PixelDimensions(width: 1080, height: 1920), qualityPreset: .compressedVeryHigh).withUpdatedVideoTrimRange(2.0 ..< 12.0)
        store.update("v") { $0.values = values }
        XCTAssertTrue(store.isEdited("v"))
        let editing = RoundVideoTestEditing()
        let sources: [String: MediaPickerChatMediaSendSource] = ["v": self.video("v"), "w": self.video("w")]
        XCTAssertNil(mediaPickerChatMediaSendLegacyOnlyReason(uniqueId: "v", source: sources["v"], editing: editing, store: store))
        store.shadowSetRoundVideo(true, for: "v")
        XCTAssertEqual(mediaPickerChatMediaSendLegacyOnlyReason(uniqueId: "v", source: sources["v"], editing: editing, store: store), .legacyAdjustments)
        XCTAssertEqual(mediaPickerChatMediaSendLegacyOnlyIds(selection: RoundVideoTestSelection(["v", "w"]), editing: editing, store: store, assetFor: { sources[$0] }), ["v"])
        editing.prices["v"] = 10
        XCTAssertNil(mediaPickerChatMediaSendLegacyOnlyReason(uniqueId: "v", source: sources["v"], editing: editing, store: store))
    }

    func testRoundVideoHasNoCaptionAndNoAlbum() {
        let store = ChatMediaEditorItemStore()
        store.shadowSetRoundVideo(true, for: "v")
        let editing = RoundVideoTestEditing()
        editing.captions["v"] = NSAttributedString(string: "hello")
        editing.captions["w"] = NSAttributedString(string: "world")
        let sources: [String: MediaPickerChatMediaSendSource] = ["v": self.video("v"), "w": self.video("w")]
        let items = mediaPickerChatMediaSendItems(selection: RoundVideoTestSelection(["v", "w"]), editing: editing, store: store, assetFor: { sources[$0] }, fileNameFor: { _ in nil })
        XCTAssertEqual(items.count, 2)
        XCTAssertNil(items[0].options.caption)
        XCTAssertTrue(items[0].options.excludedFromGrouping)
        XCTAssertEqual(items[1].options.caption?.string, "world")
        XCTAssertFalse(items[1].options.excludedFromGrouping)
    }

    private func assertTrim(_ trim: (start: Double, end: Double), _ start: Double, _ end: Double, line: UInt = #line) {
        XCTAssertEqual(trim.start, start, accuracy: 1e-9, line: line)
        XCTAssertEqual(trim.end, end, accuracy: 1e-9, line: line)
    }

    func testTrimKeepsTheEditorRangeUpToAMinute() {
        self.assertTrim(shadowRoundVideoTrim(trimRange: nil, duration: 30.0), 0.0, 30.0)
        self.assertTrim(shadowRoundVideoTrim(trimRange: nil, duration: 90.0), 0.0, 60.0)
        self.assertTrim(shadowRoundVideoTrim(trimRange: 5.0 ..< 20.0, duration: 90.0), 5.0, 20.0)
        self.assertTrim(shadowRoundVideoTrim(trimRange: 10.0 ..< 85.0, duration: 90.0), 10.0, 70.0)
        self.assertTrim(shadowRoundVideoTrim(trimRange: 10.0 ..< 120.0, duration: 90.0), 10.0, 70.0)
    }

    func testCropFollowsAPlainEditorCropOnly() {
        let pixelSize = CGSize(width: 1080.0, height: 1920.0)
        let full = CGRect(origin: .zero, size: pixelSize)
        XCTAssertEqual(shadowRoundVideoCropRect(editorCropRect: nil, editorOriginalSize: pixelSize, isPlainCrop: true, pixelSize: pixelSize), full)
        let crop = CGRect(x: 100.0, y: 200.0, width: 500.0, height: 600.0)
        XCTAssertEqual(shadowRoundVideoCropRect(editorCropRect: crop, editorOriginalSize: pixelSize, isPlainCrop: true, pixelSize: pixelSize), crop)
        XCTAssertEqual(shadowRoundVideoCropRect(editorCropRect: crop, editorOriginalSize: pixelSize, isPlainCrop: false, pixelSize: pixelSize), full)
        let halfSize = CGSize(width: 540.0, height: 960.0)
        XCTAssertEqual(shadowRoundVideoCropRect(editorCropRect: CGRect(x: 50.0, y: 100.0, width: 250.0, height: 300.0), editorOriginalSize: halfSize, isPlainCrop: true, pixelSize: pixelSize), crop)
    }

    func testPreviewCircleIsTheCenteredSquare() {
        XCTAssertEqual(shadowRoundVideoPreviewCircle(in: CGRect(x: 0.0, y: 0.0, width: 300.0, height: 500.0)), CGRect(x: 0.0, y: 100.0, width: 300.0, height: 300.0))
        XCTAssertEqual(shadowRoundVideoPreviewCircle(in: CGRect(x: 0.0, y: 0.0, width: 400.0, height: 200.0)), CGRect(x: 100.0, y: 0.0, width: 200.0, height: 200.0))
    }
}

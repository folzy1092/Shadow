import Foundation
import Postbox

// AyuGram fork (Этап 4a): builds the edit-history versions for a message that is
// being edited, capturing the previous caption/text AND — when the media itself
// changed — a backup of the previous media into the private gallery (reusing the
// Этап 3 persistence). Kept out of AccountStateManagementUtils so the touch there
// stays a single call (high merge-conflict risk in that file).
//
// Returns the full versions array to store, or nil when there is nothing worth
// capturing. Reads the owning account's snapshot (no nested Postbox transaction)
// so it is safe to call from inside a message-update closure.

private func ayuPrincipalResourceId(_ mediaList: [Media]) -> String? {
    for media in mediaList {
        if let first = AyuSavedMedia.savableResources(from: media).first {
            return first.resource.id.stringRepresentation
        }
    }
    return nil
}

func ayuBuildEditHistoryVersions(mediaBox: MediaBox, previousMessage: Message, newText: String, newMedia: [Media]) -> [SavedMessageEditVersion]? {
    guard currentAyuGramSettings(mediaBox: mediaBox).saveEditHistory else {
        return nil
    }

    // Mirror the original text rule (only preserve a non-empty previous caption),
    // and additionally capture whenever the principal media changed.
    let textChanged = !previousMessage.text.isEmpty && previousMessage.text != newText
    let previousMediaId = ayuPrincipalResourceId(previousMessage.media)
    let mediaChanged = previousMediaId != ayuPrincipalResourceId(newMedia)

    guard textChanged || mediaChanged else {
        return nil
    }

    // Back up the previous media (best effort) and remember where it went, so the
    // edit-history UI can show the old photo/video/voice alongside the old caption.
    var mediaFileName: String?
    var mediaKind: String?
    if mediaChanged, previousMediaId != nil {
        AyuSavedMedia.saveMessageMedia(mediaBox: mediaBox, message: previousMessage)
        mediaFileName = AyuSavedMedia.principalFileName(peerId: previousMessage.id.peerId, messageId: previousMessage.id, mediaList: previousMessage.media)
        mediaKind = AyuSavedMedia.mediaKind(for: previousMessage.media)
    }

    var versions: [SavedMessageEditVersion] = []
    if let existing = previousMessage.attributes.first(where: { $0 is SavedMessageEditsAttribute }) as? SavedMessageEditsAttribute {
        versions = existing.versions
    }
    let date = Int32(CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970)
    versions.append(SavedMessageEditVersion(text: previousMessage.text, date: date, mediaFileName: mediaFileName, mediaKind: mediaKind))
    if versions.count > 20 {
        versions.removeFirst(versions.count - 20)
    }
    return versions
}

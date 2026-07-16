import Foundation
import Postbox

// AyuGram fork: keeps previous versions of a message when it is edited so the
// chat UI can show an edit history. Each entry is the previous text / caption
// that was replaced, the timestamp at which it was superseded, and — when the
// media also changed — the name of the previous media backed up into the private
// AyuGram gallery (see AyuSavedMedia, reusing the Этап 3 persistence). Both media
// fields are optional and decoded defensively so older stored attributes (which
// had only text) keep working.
public final class SavedMessageEditVersion: PostboxCoding {
    public let text: String
    public let date: Int32
    // Name of the previous media file in the AyuGram gallery (nil for a
    // text/caption-only edit or when the media was not available to back up).
    public let mediaFileName: String?
    // A coarse media kind ("image" / "video" / "voice" / "roundVideo" / "file")
    // so the UI can pick an icon without opening the file. nil when no media.
    public let mediaKind: String?

    public init(text: String, date: Int32, mediaFileName: String? = nil, mediaKind: String? = nil) {
        self.text = text
        self.date = date
        self.mediaFileName = mediaFileName
        self.mediaKind = mediaKind
    }

    public init(decoder: PostboxDecoder) {
        self.text = decoder.decodeStringForKey("t", orElse: "")
        self.date = decoder.decodeInt32ForKey("d", orElse: 0)
        self.mediaFileName = decoder.decodeOptionalStringForKey("mf")
        self.mediaKind = decoder.decodeOptionalStringForKey("mk")
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeString(self.text, forKey: "t")
        encoder.encodeInt32(self.date, forKey: "d")
        if let mediaFileName = self.mediaFileName {
            encoder.encodeString(mediaFileName, forKey: "mf")
        } else {
            encoder.encodeNil(forKey: "mf")
        }
        if let mediaKind = self.mediaKind {
            encoder.encodeString(mediaKind, forKey: "mk")
        } else {
            encoder.encodeNil(forKey: "mk")
        }
    }
}

public class SavedMessageEditsAttribute: MessageAttribute {
    public let versions: [SavedMessageEditVersion]

    public init(versions: [SavedMessageEditVersion]) {
        self.versions = versions
    }

    required public init(decoder: PostboxDecoder) {
        self.versions = decoder.decodeObjectArrayWithDecoderForKey("v")
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeObjectArray(self.versions, forKey: "v")
    }
}

import Foundation
import Postbox

// AyuGram fork: marks a message that the server asked us to delete but that we
// kept (anti-delete). The chat UI renders a trash badge next to such messages.
public class DeletedMessageAttribute: MessageAttribute {
    public let date: Int32

    public init(date: Int32) {
        self.date = date
    }

    required public init(decoder: PostboxDecoder) {
        self.date = decoder.decodeInt32ForKey("d", orElse: 0)
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.date, forKey: "d")
    }
}

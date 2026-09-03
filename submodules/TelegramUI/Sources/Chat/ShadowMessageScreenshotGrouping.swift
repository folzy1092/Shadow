import Foundation

// Pure grouping policy shared by the screenshot preview and its executable tests.
// Unknown senders must never be combined just because both IDs are nil.
enum ShadowMessageScreenshotGrouping {
    static func continuesGroup(authorId: Int64?, timestamp: Int32, previousAuthorId: Int64?, previousTimestamp: Int32?, sameConversation: Bool) -> Bool {
        guard sameConversation, let authorId, authorId == previousAuthorId, let previousTimestamp else {
            return false
        }
        let interval = Int64(timestamp) - Int64(previousTimestamp)
        return interval >= 0 && interval <= 5 * 60
    }
}

import Foundation

// Pure grouping policy shared by the screenshot preview and its executable tests.
// Unknown senders must never be combined just because both IDs are nil.
enum ShadowMessageScreenshotGrouping {
    static func albumRows<Message>(_ messages: [Message], groupingKey: (Message) -> Int64?, sameConversation: (Message, Message) -> Bool) -> [[Message]] {
        var rows: [[Message]] = []
        for message in messages {
            if let key = groupingKey(message), let previous = rows.last?.last,
               groupingKey(previous) == key, sameConversation(previous, message) {
                rows[rows.count - 1].append(message)
            } else {
                rows.append([message])
            }
        }
        return rows
    }

    static func continuesGroup(authorId: Int64?, timestamp: Int32, previousAuthorId: Int64?, previousTimestamp: Int32?, sameConversation: Bool) -> Bool {
        guard sameConversation, let authorId, authorId == previousAuthorId, let previousTimestamp else {
            return false
        }
        let interval = Int64(timestamp) - Int64(previousTimestamp)
        return interval >= 0 && interval <= 5 * 60
    }
}

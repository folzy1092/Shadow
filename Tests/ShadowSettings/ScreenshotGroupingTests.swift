import Foundation

@main struct ScreenshotGroupingTests {
    static func main() {
        func grouped(_ author: Int64?, _ previous: Int64?, _ timestamp: Int32 = 1100, _ previousTimestamp: Int32? = 1000, sameConversation: Bool = true) -> Bool {
            return ShadowMessageScreenshotGrouping.continuesGroup(authorId: author, timestamp: timestamp, previousAuthorId: previous, previousTimestamp: previousTimestamp, sameConversation: sameConversation)
        }
        precondition(grouped(1, 1))
        precondition(grouped(1, 1, 1000))
        precondition(grouped(1, 1, 1300))
        precondition(!grouped(1, 1, 1301))
        precondition(!grouped(1, 1, 999))
        precondition(!grouped(1, 2))
        precondition(!grouped(nil, nil))
        precondition(!grouped(1, nil))
        precondition(!grouped(nil, 1))
        precondition(!grouped(1, 1, 1100, nil))
        precondition(!grouped(1, 1, sameConversation: false))
        precondition(!grouped(1, 1, Int32.max, Int32.min))
        precondition(!grouped(1, 1, Int32.min, Int32.max))
        precondition(grouped(Int64.max, Int64.max))
        print("Screenshot author grouping and timestamp boundaries passed")
    }
}

import Foundation

@main
struct OwnServerPresenceTests {
    static func main() {
        precondition(ShadowOwnServerPresence.offline(wasOnline: 1_700_000_000).exactLastSeenTimestamp == 1_700_000_000)
        precondition(ShadowOwnServerPresence.offline(wasOnline: 0).exactLastSeenTimestamp == nil)
        precondition(ShadowOwnServerPresence.offline(wasOnline: -1).exactLastSeenTimestamp == nil)
        // Online TTLs, including an expired one, are not last-seen dates.
        precondition(ShadowOwnServerPresence.online(expires: 1).exactLastSeenTimestamp == nil)
        precondition(ShadowOwnServerPresence.online(expires: Int32.max).exactLastSeenTimestamp == nil)
        let coarseStatuses: [ShadowOwnServerPresence] = [.unavailable, .recently, .lastWeek, .lastMonth]
        for status in coarseStatuses {
            precondition(status.exactLastSeenTimestamp == nil)
        }
        print("Own server presence: only server offline timestamps are exact")
    }
}

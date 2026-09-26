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

        struct Photo {
            let id: Int
            let album: Int64?
            let peer: Int64
            let thread: Int64?
        }
        let photos = [
            Photo(id: 1, album: 10, peer: 1, thread: nil),
            Photo(id: 2, album: 10, peer: 1, thread: nil),
            Photo(id: 3, album: nil, peer: 1, thread: nil),
            Photo(id: 4, album: 10, peer: 1, thread: nil),
            Photo(id: 5, album: 10, peer: 2, thread: nil),
            Photo(id: 6, album: 10, peer: 2, thread: 7),
            Photo(id: 7, album: nil, peer: 2, thread: 7),
            Photo(id: 8, album: nil, peer: 2, thread: 7)
        ]
        let rows = ShadowMessageScreenshotGrouping.albumRows(photos, groupingKey: { $0.album }, sameConversation: {
            $0.peer == $1.peer && $0.thread == $1.thread
        })
        precondition(rows.map { $0.map(\.id) } == [[1, 2], [3], [4], [5], [6], [7], [8]])
        print("Screenshot author grouping and timestamp boundaries passed")
    }
}

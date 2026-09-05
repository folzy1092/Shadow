import Foundation

// This is a live server response, not a preference or a persisted estimate.
// Keep offline.wasOnline separate from online.expires: an expired online TTL
// must never become a fabricated last-seen timestamp.
public enum ShadowOwnServerPresence: Equatable {
    case unavailable
    case offline(wasOnline: Int32)
    case online(expires: Int32)
    case recently
    case lastWeek
    case lastMonth

    public var exactLastSeenTimestamp: Int32? {
        if case let .offline(wasOnline) = self, wasOnline > 0 {
            return wasOnline
        }
        return nil
    }
}

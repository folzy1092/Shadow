import Foundation

@main
struct LocalPinsTests {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            count += 1
        }

        let suite = "shadow-local-pins-tests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = ShadowLocalPinStore(defaults: defaults)

        let a = ShadowLocalPin(namespace: 0, id: 50)
        let b = ShadowLocalPin(namespace: 0, id: 10)
        check(store.pins(accountPeerId: 1, peerId: 2).isEmpty, "Empty at first")
        store.setPinned(true, accountPeerId: 1, peerId: 2, pin: a)
        store.setPinned(true, accountPeerId: 1, peerId: 2, pin: b)
        store.setPinned(true, accountPeerId: 1, peerId: 2, pin: a)
        check(store.pins(accountPeerId: 1, peerId: 2) == [b, a], "Oldest first, no duplicates")
        check(store.pins(accountPeerId: 1, peerId: 3).isEmpty && store.pins(accountPeerId: 9, peerId: 2).isEmpty, "Per account and chat")
        check(store.isPinned(accountPeerId: 1, peerId: 2, pin: a), "Is pinned")
        store.setPinned(false, accountPeerId: 1, peerId: 2, pin: a)
        check(store.pins(accountPeerId: 1, peerId: 2) == [b], "Unpin")
        store.setPinned(false, accountPeerId: 1, peerId: 2, pin: b)
        check(store.pins(accountPeerId: 1, peerId: 2).isEmpty, "Unpin the last one")
        check(ShadowLocalPinStore(defaults: defaults).pins(accountPeerId: 1, peerId: 2).isEmpty, "Persisted")
        for id in 0 ..< 105 {
            store.setPinned(true, accountPeerId: 1, peerId: 4, pin: ShadowLocalPin(namespace: 0, id: Int32(id)))
        }
        let limited = store.pins(accountPeerId: 1, peerId: 4)
        check(limited.count == ShadowLocalPinStore.limitPerChat && limited.first?.id == 5, "Limit keeps the newest")

        // Which pin the header shows.
        let ids: [Int32] = [10, 20, 30]
        check(ShadowLocalPins.pickIndex(ids: [], referenceId: nil, isScrolled: false) == nil, "No pins")
        check(ShadowLocalPins.pickIndex(ids: ids, referenceId: nil, isScrolled: false) == 2, "No reference: newest")
        check(ShadowLocalPins.pickIndex(ids: ids, referenceId: 25, isScrolled: false) == 1, "Newest above the top visible message")
        check(ShadowLocalPins.pickIndex(ids: ids, referenceId: 20, isScrolled: false) == 1, "Visible pin itself")
        check(ShadowLocalPins.pickIndex(ids: ids, referenceId: 20, isScrolled: true) == 0, "After a tap: the one above")
        check(ShadowLocalPins.pickIndex(ids: ids, referenceId: 5, isScrolled: false) == 0, "Above all: the oldest")

        check(ShadowLocalPins.prefersFirst(30, over: 20, referenceId: nil, isScrolled: false), "No reference: newer")
        check(!ShadowLocalPins.prefersFirst(30, over: 20, referenceId: 25, isScrolled: false), "Only the older matches")
        check(ShadowLocalPins.prefersFirst(20, over: 10, referenceId: 25, isScrolled: false), "Both match: newer")
        check(ShadowLocalPins.prefersFirst(10, over: 20, referenceId: 5, isScrolled: false), "None match: older")

        defaults.removePersistentDomain(forName: suite)
        print("Local pins: \(count) checks passed")
    }
}

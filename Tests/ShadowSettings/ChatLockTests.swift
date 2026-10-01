import Foundation

@main
struct ChatLockTests {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            count += 1
        }
        let suite = "shadow-chat-lock-tests-\(UInt64.random(in: 0 ... UInt64.max))"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ShadowChatLockStore(defaults: defaults)

        check(!store.isLocked(accountPeerId: 1, peerId: 10), "Nothing locked initially")
        store.setLocked(true, accountPeerId: 1, peerId: 10)
        check(store.isLocked(accountPeerId: 1, peerId: 10), "Locked")
        check(!store.isLocked(accountPeerId: 2, peerId: 10), "Locks are per account")
        check(store.lockedPeerIds(accountPeerId: 1) == [10], "Locked list")
        check(store.requiresUnlock(accountPeerId: 1, peerId: 10), "Locked chat needs unlock")
        store.markUnlocked(accountPeerId: 1, peerId: 10)
        check(!store.requiresUnlock(accountPeerId: 1, peerId: 10), "Unlocked for the session")
        store.relock(accountPeerId: 1, peerId: 10)
        check(store.requiresUnlock(accountPeerId: 1, peerId: 10), "Leaving the chat relocks it")
        store.markUnlocked(accountPeerId: 1, peerId: 10)
        store.relockAll()
        check(store.requiresUnlock(accountPeerId: 1, peerId: 10), "Background relocks")
        store.setLocked(false, accountPeerId: 1, peerId: 10)
        check(!store.isLocked(accountPeerId: 1, peerId: 10), "Unlocked permanently")
        check(!store.hasLockedChats, "No locks left")

        check(!store.hasPassword, "No password initially")
        check(!store.setPassword("123"), "Too short password rejected")
        check(store.setPassword("1234"), "Password set")
        check(store.hasPassword, "Password stored")
        check(store.verifyPassword("1234"), "Correct password")
        check(!store.verifyPassword("12345"), "Wrong password")
        check(!store.verifyPassword(""), "Empty password")
        let stored = defaults.dictionary(forKey: "shadow.chatLock.password.v1")!
        check(stored["hash"] as? Data != Data("1234".utf8), "Password is not stored in clear")
        check((stored["salt"] as? Data)?.count == 16, "Random salt")

        let start = Date(timeIntervalSince1970: 1_000_000)
        check(store.resetRemaining(now: start) == nil, "No reset pending")
        store.requestReset(now: start)
        check(store.resetRemaining(now: start) == ShadowChatLockStore.resetDelay, "Reset waits an hour")
        check(!store.canResetWithoutPassword(now: start.addingTimeInterval(3599)), "Not before an hour")
        check(store.canResetWithoutPassword(now: start.addingTimeInterval(3600)), "After an hour")
        store.requestReset(now: start.addingTimeInterval(1800))
        check(store.resetRequestedAt == start, "Repeated request keeps the first time")
        store.setLocked(true, accountPeerId: 1, peerId: 20)
        store.markUnlocked(accountPeerId: 1, peerId: 20)
        check(store.resetRequestedAt == nil, "Successful unlock cancels the reset")
        store.performReset()
        check(!store.hasPassword && !store.hasLockedChats && store.resetRequestedAt == nil, "Reset clears everything")

        print("Shadow chat lock: \(count) checks passed")
    }
}

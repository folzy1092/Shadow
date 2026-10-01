import Foundation

// Shadow: local history of when contacts were online (spec 7.4). Fed from the
// status updates Telegram already receives (updatePeerPresencesClean); kept on
// the device for `retention` and never sent anywhere.
//
// Foundation only, so it is unit-tested by the Foundation suite.
public final class ShadowOnlineHistory {
    public static let shared = ShadowOnlineHistory(
        directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("shadow-online-history", isDirectory: true)
    )

    public static let retention: TimeInterval = 30 * 24 * 60 * 60
    // An "online" status without a matching offline one is closed at its
    // `until` time, but never later than this after it started.
    public static let maximumSessionLength: TimeInterval = 6 * 60 * 60

    public struct Session: Equatable, Codable {
        public var start: Int32
        public var end: Int32
    }

    private struct PeerLog: Codable {
        var sessions: [Session] = []
        // Set while the peer is online: the start time and the expected end.
        var openStart: Int32?
        var openUntil: Int32?
    }

    private let directory: URL
    private let queue = DispatchQueue(label: "shadow.online.history")
    // accountPeerId -> peerId -> log
    private var logs: [Int64: [Int64: PeerLog]] = [:]
    private var loadedAccounts = Set<Int64>()
    private var dirtyAccounts = Set<Int64>()
    private var saveScheduled = false

    public init(directory: URL) {
        self.directory = directory
        self.queue.setSpecific(key: ShadowOnlineHistory.queueKey, value: true)
    }

    private func fileURL(accountPeerId: Int64) -> URL {
        return self.directory.appendingPathComponent("\(accountPeerId).json")
    }

    private func ensureLoaded(_ accountPeerId: Int64) {
        if self.loadedAccounts.contains(accountPeerId) {
            return
        }
        self.loadedAccounts.insert(accountPeerId)
        if let data = try? Data(contentsOf: self.fileURL(accountPeerId: accountPeerId)), let decoded = try? JSONDecoder().decode([String: PeerLog].self, from: data) {
            var mapped: [Int64: PeerLog] = [:]
            for (key, value) in decoded {
                if let peerId = Int64(key) {
                    mapped[peerId] = value
                }
            }
            self.logs[accountPeerId] = mapped
        }
    }

    // `onlineUntil` is the status expiry when the peer is online, nil when it is
    // offline; `lastSeen` is the exact last-seen time when known.
    public func record(accountPeerId: Int64, peerId: Int64, onlineUntil: Int32?, lastSeen: Int32?, now: Int32 = Int32(Date().timeIntervalSince1970)) {
        self.queue.async {
            self.ensureLoaded(accountPeerId)
            var accountLogs = self.logs[accountPeerId] ?? [:]
            var log = accountLogs[peerId] ?? PeerLog()
            ShadowOnlineHistory.apply(&log, onlineUntil: onlineUntil, lastSeen: lastSeen, now: now)
            accountLogs[peerId] = log
            self.logs[accountPeerId] = accountLogs
            self.dirtyAccounts.insert(accountPeerId)
            self.scheduleSave()
        }
    }

    private static func apply(_ log: inout PeerLog, onlineUntil: Int32?, lastSeen: Int32?, now: Int32) {
        if let until = onlineUntil, until > now {
            if let openStart = log.openStart, let openUntil = log.openUntil, openUntil < now {
                // The previous session expired without an offline update.
                log.sessions.append(Session(start: openStart, end: max(openStart, openUntil)))
                log.openStart = nil
            }
            if log.openStart == nil {
                log.openStart = now
            }
            log.openUntil = until
        } else if let openStart = log.openStart {
            var end = lastSeen ?? now
            if let openUntil = log.openUntil {
                end = min(end, max(openUntil, openStart))
            }
            end = min(max(end, openStart), openStart + Int32(ShadowOnlineHistory.maximumSessionLength))
            log.sessions.append(Session(start: openStart, end: end))
            log.openStart = nil
            log.openUntil = nil
        }
        let cutoff = now - Int32(ShadowOnlineHistory.retention)
        log.sessions.removeAll(where: { $0.end < cutoff })
    }

    // Finished sessions plus the current one (if online), oldest first.
    public func sessions(accountPeerId: Int64, peerId: Int64, now: Int32 = Int32(Date().timeIntervalSince1970)) -> [Session] {
        return self.queue.sync {
            self.ensureLoaded(accountPeerId)
            guard let log = self.logs[accountPeerId]?[peerId] else {
                return []
            }
            var result = log.sessions
            if let openStart = log.openStart {
                let end = min(now, log.openUntil ?? now)
                result.append(Session(start: openStart, end: max(openStart, end)))
            }
            return result
        }
    }

    public func clear(accountPeerId: Int64) {
        self.queue.async {
            self.logs[accountPeerId] = [:]
            self.loadedAccounts.insert(accountPeerId)
            try? FileManager.default.removeItem(at: self.fileURL(accountPeerId: accountPeerId))
        }
    }

    private func scheduleSave() {
        if self.saveScheduled {
            return
        }
        self.saveScheduled = true
        self.queue.asyncAfter(deadline: .now() + 5.0) {
            self.saveScheduled = false
            self.flush()
        }
    }

    // Writes pending changes now (also used by tests).
    public func flush() {
        let work = {
            try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            for accountPeerId in self.dirtyAccounts {
                var encoded: [String: PeerLog] = [:]
                for (peerId, log) in self.logs[accountPeerId] ?? [:] {
                    encoded["\(peerId)"] = log
                }
                if let data = try? JSONEncoder().encode(encoded) {
                    try? data.write(to: self.fileURL(accountPeerId: accountPeerId), options: [.atomic])
                }
            }
            self.dirtyAccounts.removeAll()
        }
        if DispatchQueue.getSpecific(key: ShadowOnlineHistory.queueKey) != nil {
            work()
        } else {
            self.queue.sync(execute: work)
        }
    }

    private static let queueKey = DispatchSpecificKey<Bool>()
}

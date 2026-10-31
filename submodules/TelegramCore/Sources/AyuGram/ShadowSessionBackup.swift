import Foundation
import Security
import Postbox
import SwiftSignalKit

// Shadow 2.1.0: account backup in the iOS keychain
// (docs/specs/2026-10-30-shadow-2.1.0-session-backup.md).
//
// Every signed-in production account's AccountBackupData (the same data Telegram
// keeps in its account record: peer id, main datacenter and its auth key) is
// copied into a keychain item. Keychain items outlive the app, so after a
// reinstall «Восстановить аккаунты (N)» creates the account records again and
// Telegram starts each account on its old session, with no phone number or code.
//
//   * WhenUnlocked, not synchronizable: never in iCloud Keychain, but carried by
//     an encrypted iPhone backup (Folzy's decision, spec §7.1).
//   * Only the app signed with the same team can read the items, so a reinstall
//     signed by someone else sees no backup.
//   * A record that turns logged out (a manual logout, the duress code, a dead
//     session) removes its item; a record that is merely absent (a fresh install)
//     never does, or a reinstall would wipe the backup before it is restored.
//   * Face ID is asked by the restoring screen (LocalAuthentication), not by the
//     keychain item, so the automatic sync never prompts.
public enum ShadowSessionBackup {
    public struct Entry: Codable, Equatable {
        public var version: Int32
        public var peerId: Int64
        public var date: Int32
        public var data: AccountBackupData
    }

    public struct RestoreResult {
        public var restored: [Int64]
        public var skipped: Int
        public var errors: [String]
    }

    // Posted on the main queue when restored accounts failed to come back; the
    // texts are taken with takePendingFailures().
    public static let restoreFailedNotification = Notification.Name("ShadowSessionBackupRestoreFailed")

    public static let queue = Queue(name: "org.shadow.sessionBackup")

    private static let service: String = (Bundle.main.bundleIdentifier ?? "shadow") + ".shadow.sessions"
    // How long after a restore a vanished or logged-out record counts as a failed restore.
    private static let verificationWindow: Double = 600.0

    // 2.1.1: what the restore is waiting for, kept across launches. Telegram deletes
    // the record of a restored account whose session the server refuses, and the
    // app may be relaunched before anyone sees why, so the failure is written down
    // first and shown at the next chance.
    private struct RestoreState: Codable {
        var restoredAt: [Int64: Double] = [:]
        // Restored peers the records have shown at least once.
        var seen: Set<Int64> = []
        // Failed restores: their keychain items are kept so the restore can be retried.
        var failed: Set<Int64> = []
        // Texts not shown yet.
        var failures: [String] = []
    }

    private static let stateKey = "shadow.sessionBackup.restoreState"
    private static let stateLock = NSLock()

    private static func updateState<T>(_ f: (inout RestoreState) -> T) -> T {
        stateLock.lock()
        defer {
            stateLock.unlock()
        }
        var state = UserDefaults.standard.data(forKey: stateKey).flatMap { try? JSONDecoder().decode(RestoreState.self, from: $0) } ?? RestoreState()
        let result = f(&state)
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: stateKey)
        }
        return result
    }

    public static func userId(_ peerId: Int64) -> Int64 {
        return PeerId(peerId).id._internalGetInt64Value()
    }

    // MARK: - Keychain

    private static func query(account: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        if let account = account {
            query[kSecAttrAccount as String] = account
        }
        return query
    }

    @discardableResult
    static func write(_ entry: Entry) -> OSStatus {
        guard let data = try? JSONEncoder().encode(entry) else {
            return errSecParam
        }
        let account = String(entry.peerId)
        SecItemDelete(query(account: account) as CFDictionary)
        var item = query(account: account)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        return SecItemAdd(item as CFDictionary, nil)
    }

    static func remove(peerId: Int64) {
        SecItemDelete(query(account: String(peerId)) as CFDictionary)
    }

    public static func removeAll() {
        SecItemDelete(query(account: nil) as CFDictionary)
    }

    public static func loadAll() -> (entries: [Entry], errors: [String]) {
        var search = query(account: nil)
        search[kSecReturnData as String] = true
        search[kSecReturnAttributes as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: AnyObject?
        let status = SecItemCopyMatching(search as CFDictionary, &result)
        if status == errSecItemNotFound {
            return ([], [])
        }
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            return ([], ["Связка ключей: не удалось прочитать бэкап (OSStatus \(status))"])
        }
        var entries: [Entry] = []
        var errors: [String] = []
        for item in items {
            let account = item[kSecAttrAccount as String] as? String ?? "?"
            guard let data = item[kSecValueData as String] as? Data else {
                errors.append("Запись \(account): пустые данные")
                continue
            }
            do {
                let entry = try JSONDecoder().decode(Entry.self, from: data)
                entries.append(entry)
            } catch {
                errors.append("Запись \(account): не читается (\(error))")
            }
        }
        return (entries, errors)
    }

    // MARK: - Sync with the account records

    private struct RecordState {
        var data: AccountBackupData
        var isLoggedOut: Bool
    }

    private static func recordState(_ attributes: [TelegramAccountManagerTypes.Attribute]) -> RecordState? {
        var data: AccountBackupData?
        var isLoggedOut = false
        var isTest = false
        for attribute in attributes {
            switch attribute {
            case let .backupData(backupData):
                data = backupData.data
            case .loggedOut:
                isLoggedOut = true
            case let .environment(environment):
                if case .test = environment.environment {
                    isTest = true
                }
            default:
                break
            }
        }
        guard let data = data, data.peerId != 0, !isTest else {
            return nil
        }
        return RecordState(data: data, isLoggedOut: isLoggedOut)
    }

    // Called on `queue` for every account records update.
    public static func sync(records: [AccountRecord<TelegramAccountManagerTypes.Attribute>]) {
        let stored = Dictionary(loadAll().entries.map { ($0.peerId, $0) }, uniquingKeysWith: { first, _ in first })
        var live = Set<Int64>()
        var loggedOut = Set<Int64>()
        var latest: [Int64: AccountBackupData] = [:]
        for record in records {
            guard let state = recordState(record.attributes) else {
                continue
            }
            if state.isLoggedOut {
                loggedOut.insert(state.data.peerId)
            } else {
                live.insert(state.data.peerId)
                latest[state.data.peerId] = state.data
            }
        }
        for (peerId, data) in latest where stored[peerId]?.data != data {
            write(Entry(version: 1, peerId: peerId, date: Int32(Date().timeIntervalSince1970), data: data))
        }
        let (failedNow, keep) = checkRestored(live: live, loggedOut: loggedOut)
        for peerId in failedNow {
            noteRestoreFailed(peerId: peerId, reason: "сервер не принял сохранённую сессию (скорее всего, её завершили в «Активных сеансах» или она истекла)")
        }
        // A peer can have an old logged-out record next to a live one (signed in again).
        // An account that fell out right after a restore keeps its item, so the
        // restore can be tried again.
        for peerId in loggedOut.subtracting(live) where stored[peerId] != nil && !keep.contains(peerId) {
            remove(peerId: peerId)
        }
    }

    // A restored account that turns logged out, or whose record disappears (Telegram
    // deletes the record of a session the server refused), within the window has
    // failed. Returns those and every peer whose item must be kept.
    private static func checkRestored(live: Set<Int64>, loggedOut: Set<Int64>) -> (failedNow: [Int64], keep: Set<Int64>) {
        let now = Date().timeIntervalSince1970
        return updateState { state in
            var failedNow: [Int64] = []
            for (peerId, restoredAt) in state.restoredAt {
                let isRecent = now - restoredAt < verificationWindow
                if live.contains(peerId) || loggedOut.contains(peerId) {
                    state.seen.insert(peerId)
                }
                if live.contains(peerId) {
                    state.failed.remove(peerId)
                } else if isRecent && (loggedOut.contains(peerId) || state.seen.contains(peerId)) {
                    failedNow.append(peerId)
                }
                if !isRecent {
                    state.restoredAt[peerId] = nil
                    state.seen.remove(peerId)
                }
            }
            return (failedNow, state.failed.union(state.restoredAt.keys))
        }
    }

    // Records a failed restore once, keeps its item and tells the app to show it.
    // Only an account restored within the window counts: other records fail for
    // reasons of their own.
    public static func noteRestoreFailed(peerId: Int64, reason: String) {
        let text = "Аккаунт \(userId(peerId)): \(reason). Войди в этот аккаунт по номеру."
        let isNew = updateState { state -> Bool in
            guard state.restoredAt[peerId] != nil, !state.failed.contains(peerId) else {
                return false
            }
            state.failed.insert(peerId)
            state.failures.append(text)
            return true
        }
        if isNew {
            Logger.shared.log("ShadowSessionBackup", "restore failed: \(text)")
            announcePendingFailures()
        }
    }

    public static func announcePendingFailures() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: restoreFailedNotification, object: nil)
        }
    }

    // The failures not shown yet; taking them marks them shown.
    public static func takePendingFailures() -> [String] {
        return updateState { state in
            let failures = state.failures
            state.failures = []
            return failures
        }
    }

    // MARK: - Restore

    private static func presentPeerIds(_ records: [AccountRecord<TelegramAccountManagerTypes.Attribute>]) -> Set<Int64> {
        var result = Set<Int64>()
        for record in records {
            if let state = recordState(record.attributes), !state.isLoggedOut {
                result.insert(state.data.peerId)
            }
        }
        return result
    }

    // How many backed-up accounts are not in the app yet.
    public static func restorableCount(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Int, NoError> {
        return accountManager.transaction { transaction -> Int in
            let present = presentPeerIds(transaction.getRecords())
            return loadAll().entries.filter { !present.contains($0.peerId) }.count
        }
    }

    // Creates a record for every backed-up account that is not in the app, one
    // transaction per account, one after another (as Swiftgram restores its
    // backups), so every record is created against the records the previous one
    // left. With `switchToRestored` (the login screen) the first one becomes
    // current and the pending authorization is dropped, as a finished login does.
    public static func restoreAll(accountManager: AccountManager<TelegramAccountManagerTypes>, switchToRestored: Bool) -> Signal<RestoreResult, NoError> {
        return deferred { () -> Signal<RestoreResult, NoError> in
            let (entries, errors) = loadAll()
            var signal: Signal<[(Int64, AccountRecordId)], NoError> = .single([])
            for entry in entries.sorted(by: { $0.peerId < $1.peerId }) {
                signal = signal
                |> mapToSignal { restored -> Signal<[(Int64, AccountRecordId)], NoError> in
                    return restoreOne(entry, accountManager: accountManager)
                    |> map { id -> [(Int64, AccountRecordId)] in
                        guard let id = id else {
                            return restored
                        }
                        return restored + [(entry.peerId, id)]
                    }
                }
            }
            return signal
            |> mapToSignal { restored -> Signal<RestoreResult, NoError> in
                let result = RestoreResult(restored: restored.map { $0.0 }, skipped: entries.count - restored.count, errors: errors)
                guard switchToRestored, let firstId = restored.first?.1 else {
                    return .single(result)
                }
                return accountManager.transaction { transaction -> RestoreResult in
                    transaction.setCurrentId(firstId)
                    transaction.removeAuth()
                    return result
                }
            }
        }
        |> runOn(queue)
    }

    private static func restoreOne(_ entry: Entry, accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<AccountRecordId?, NoError> {
        return accountManager.transaction { transaction -> AccountRecordId? in
            let records = transaction.getRecords()
            if presentPeerIds(records).contains(entry.peerId) {
                return nil
            }
            let maxSortOrder = records.map { record -> Int32 in
                for attribute in record.attributes {
                    if case let .sortOrder(sortOrder) = attribute {
                        return sortOrder.order
                    }
                }
                return 0
            }.max() ?? 0
            let id = transaction.createRecord([
                .environment(AccountEnvironmentAttribute(environment: .production)),
                .sortOrder(AccountSortOrderAttribute(order: maxSortOrder + 1)),
                .backupData(AccountBackupDataAttribute(data: entry.data))
            ])
            updateState { state in
                state.restoredAt[entry.peerId] = Date().timeIntervalSince1970
                state.failed.remove(entry.peerId)
                state.seen.remove(entry.peerId)
            }
            return id
        }
    }

    // The text the «Скопировать» button copies: what happened, for Folzy to forward.
    public static func report(_ result: RestoreResult) -> String {
        var lines: [String] = ["Shadow: восстановление аккаунтов"]
        lines.append("Восстановлено: \(result.restored.count)" + (result.restored.isEmpty ? "" : " (" + result.restored.map { String(userId($0)) }.joined(separator: ", ") + ")"))
        lines.append("Уже были в приложении: \(result.skipped)")
        if !result.errors.isEmpty {
            lines.append("Ошибки:")
            lines.append(contentsOf: result.errors.map { "• " + $0 })
        }
        return lines.joined(separator: "\n")
    }
}

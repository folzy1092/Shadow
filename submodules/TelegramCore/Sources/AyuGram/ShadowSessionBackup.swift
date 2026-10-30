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

    // Posted on the main queue with userInfo["text"] when an account restored in
    // this launch turns out to have a session the server no longer accepts.
    public static let restoreFailedNotification = Notification.Name("ShadowSessionBackupRestoreFailed")

    public static let queue = Queue(name: "org.shadow.sessionBackup")

    private static let service: String = (Bundle.main.bundleIdentifier ?? "shadow") + ".shadow.sessions"
    // How long after a restore a logout is reported as «сессия завершена».
    private static let verificationWindow: Double = 600.0
    private static let pendingLock = NSLock()
    private static var pendingVerification: [Int64: Double] = [:]

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
        // A peer can have an old logged-out record next to a live one (signed in again).
        for peerId in loggedOut.subtracting(live) {
            // 2.1.1: an account that fell out right after a restore keeps its item,
            // so the restore can be tried again.
            pendingLock.lock()
            let restoredAt = pendingVerification[peerId]
            pendingLock.unlock()
            let recentlyRestored = restoredAt.map { Date().timeIntervalSince1970 - $0 < verificationWindow } ?? false
            if stored[peerId] != nil && !recentlyRestored {
                remove(peerId: peerId)
            }
            reportIfRestoredRecently(peerId: peerId)
        }
    }

    private static func reportIfRestoredRecently(peerId: Int64) {
        pendingLock.lock()
        let restoredAt = pendingVerification.removeValue(forKey: peerId)
        pendingLock.unlock()
        guard let restoredAt = restoredAt, Date().timeIntervalSince1970 - restoredAt < verificationWindow else {
            return
        }
        let text = "Аккаунт \(userId(peerId)): сервер не принял сохранённую сессию. Скорее всего, её завершили в «Активных сеансах» или она истекла. Войди в этот аккаунт по номеру."
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: restoreFailedNotification, object: nil, userInfo: ["text": text])
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

    // Creates a record for every backed-up account that is not in the app. With
    // `switchToRestored` (the login screen) the first one becomes current and the
    // pending authorization is dropped, as a finished login does.
    public static func restoreAll(accountManager: AccountManager<TelegramAccountManagerTypes>, switchToRestored: Bool) -> Signal<RestoreResult, NoError> {
        return accountManager.transaction { transaction -> RestoreResult in
            let (entries, errors) = loadAll()
            let records = transaction.getRecords()
            let present = presentPeerIds(records)
            var nextSortOrder = (records.map { record -> Int32 in
                for attribute in record.attributes {
                    if case let .sortOrder(sortOrder) = attribute {
                        return sortOrder.order
                    }
                }
                return 0
            }.max() ?? 0) + 1
            var restored: [Int64] = []
            var firstId: AccountRecordId?
            for entry in entries.sorted(by: { $0.peerId < $1.peerId }) where !present.contains(entry.peerId) {
                let id = transaction.createRecord([
                    .environment(AccountEnvironmentAttribute(environment: .production)),
                    .sortOrder(AccountSortOrderAttribute(order: nextSortOrder)),
                    .backupData(AccountBackupDataAttribute(data: entry.data))
                ])
                nextSortOrder += 1
                restored.append(entry.peerId)
                if firstId == nil {
                    firstId = id
                }
            }
            if switchToRestored, let firstId = firstId {
                transaction.setCurrentId(firstId)
                transaction.removeAuth()
            }
            let now = Date().timeIntervalSince1970
            pendingLock.lock()
            for peerId in restored {
                pendingVerification[peerId] = now
            }
            pendingLock.unlock()
            return RestoreResult(restored: restored, skipped: entries.count - restored.count, errors: errors)
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

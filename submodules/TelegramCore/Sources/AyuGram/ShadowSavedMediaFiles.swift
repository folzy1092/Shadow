import Foundation

// Capture time must be separate from the hard link's mtime: both cache and
// gallery links refer to the same inode. Serialize capture, restore and cleanup.
public enum ShadowSavedMediaFiles {
    public struct Metadata: Codable {
        public var savedAt: Double
        public var resourceId: String?
        public var purposes: [String]?
        public init(savedAt: Double, resourceId: String?, purposes: [String]? = nil) {
            self.savedAt = savedAt
            self.resourceId = resourceId
            self.purposes = purposes
        }
    }
    private static let lock = NSRecursiveLock()
    public static let metadataSuffix = ".shadow-meta"

    public static func synchronized<T>(_ body: () -> T) -> T {
        self.lock.lock()
        defer { self.lock.unlock() }
        return body()
    }

    public static func metadata(path: String, resourceId: String? = nil, purpose: String? = nil, now: Double = Date().timeIntervalSince1970) -> Metadata {
        return synchronized {
            let url = URL(fileURLWithPath: path + metadataSuffix)
            if let data = try? Data(contentsOf: url), var value = try? JSONDecoder().decode(Metadata.self, from: data), value.savedAt.isFinite, value.savedAt > 0 {
                var changed = false
                if value.resourceId == nil, let resourceId {
                    value.resourceId = resourceId
                    changed = true
                }
                if let purpose, !(value.purposes ?? []).contains(purpose) {
                    value.purposes = (value.purposes ?? ["legacy"]) + [purpose]
                    changed = true
                }
                if changed, let data = try? JSONEncoder().encode(value) { try? data.write(to: url, options: .atomic) }
                return value
            }
            // A legacy file has no trustworthy capture time. Start its retention
            // window at migration instead of deleting it using its download date.
            let value = Metadata(savedAt: now, resourceId: resourceId, purposes: [purpose ?? "legacy"])
            if let data = try? JSONEncoder().encode(value) { try? data.write(to: url, options: .atomic) }
            return value
        }
    }

    @discardableResult
    public static func save(source: String, destination: String, resourceId: String, purpose: String = "retained", now: Double = Date().timeIntervalSince1970) -> Bool {
        return synchronized {
            let manager = FileManager.default
            if manager.fileExists(atPath: destination) {
                let _ = metadata(path: destination, resourceId: resourceId, purpose: purpose, now: now)
                return false
            }
            let temporary = (destination as NSString).deletingLastPathComponent + "/.capture-" + UUID().uuidString
            defer { try? manager.removeItem(atPath: temporary) }
            do {
                do { try manager.linkItem(atPath: source, toPath: temporary) }
                catch { try manager.copyItem(atPath: source, toPath: temporary) }
                try manager.moveItem(atPath: temporary, toPath: destination)
                let _ = metadata(path: destination, resourceId: resourceId, purpose: purpose, now: now)
                return true
            } catch { return false }
        }
    }

    @discardableResult
    public static func remove(path: String) -> Bool {
        return synchronized {
            do {
                try FileManager.default.removeItem(atPath: path)
                try? FileManager.default.removeItem(atPath: path + metadataSuffix)
                return true
            } catch { return false }
        }
    }

    @discardableResult
    public static func removeIfOnlyEditHistory(path: String) -> Bool {
        return synchronized {
            guard FileManager.default.fileExists(atPath: path), metadata(path: path).purposes == ["editHistory"] else { return false }
            return remove(path: path)
        }
    }

    public static func copy(source: String, destination: URL) -> Bool {
        return synchronized {
            do {
                do { try FileManager.default.linkItem(at: URL(fileURLWithPath: source), to: destination) }
                catch { try FileManager.default.copyItem(at: URL(fileURLWithPath: source), to: destination) }
                return true
            } catch { return false }
        }
    }
}

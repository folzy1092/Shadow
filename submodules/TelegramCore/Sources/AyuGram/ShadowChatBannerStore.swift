import Foundation

// Shadow: storage of «Фоны чатов» (model and rules: ShadowChatBanners.swift).
// Per account store: index in memory, files on disk. Changes post
// `didChangeNotification` (userInfo["basePath"]) on the main queue so the chat
// list re-renders its rows.
public final class ShadowChatBannerStore {
    public static let shared = ShadowChatBannerStore()
    public static let didChangeNotification = Notification.Name("ShadowChatBannersDidChange")

    private let lock = NSLock()
    private var indexes: [String: ShadowChatBannersIndex] = [:]
    private var revisionValue: Int = 0

    // Bumped on every change: rows compare it to know their picture is stale.
    public var revision: Int {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.revisionValue
    }

    public init() {
    }

    public func directory(basePath: String) -> String {
        let path = AyuSavedMedia.ensureDirectory(basePath: basePath) + "/" + ShadowChatBanners.directoryName
        let _ = try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
        return path
    }

    private func indexPath(basePath: String) -> String {
        return self.directory(basePath: basePath) + "/index.json"
    }

    public func imagePath(basePath: String, id: String) -> String {
        return self.directory(basePath: basePath) + "/" + id + ".jpg"
    }

    public func index(basePath: String) -> ShadowChatBannersIndex {
        self.lock.lock()
        if let index = self.indexes[basePath] {
            self.lock.unlock()
            return index
        }
        self.lock.unlock()
        var index = ShadowChatBannersIndex()
        if let data = try? Data(contentsOf: URL(fileURLWithPath: self.indexPath(basePath: basePath))) {
            index = ShadowChatBanners.decode(data)
        }
        // A photo whose file is gone (manual cleanup, failed copy) is dropped.
        index.banners.removeAll(where: { !FileManager.default.fileExists(atPath: self.imagePath(basePath: basePath, id: $0.id)) })
        self.lock.lock()
        self.indexes[basePath] = index
        self.lock.unlock()
        return index
    }

    public func banner(basePath: String, peerId: Int64) -> ShadowChatBanner? {
        return self.index(basePath: basePath).banner(peerId: peerId)
    }

    @discardableResult
    public func add(basePath: String, jpegData: Data) -> ShadowChatBanner? {
        let id = UUID().uuidString.lowercased()
        let path = self.imagePath(basePath: basePath, id: id)
        do {
            try jpegData.write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch {
            return nil
        }
        let banner = ShadowChatBanner(id: id, created: Date().timeIntervalSince1970)
        self.modify(basePath: basePath) { index in
            index.banners.append(banner)
        }
        return banner
    }

    public func update(basePath: String, banner: ShadowChatBanner) {
        self.modify(basePath: basePath) { index in
            index.update(banner)
        }
    }

    public func setPeers(basePath: String, bannerId: String, peerIds: [Int64]) {
        self.modify(basePath: basePath) { index in
            index.setPeers(peerIds, bannerId: bannerId)
        }
    }

    public func setAllChats(basePath: String, bannerId: String, value: Bool) {
        self.modify(basePath: basePath) { index in
            index.setAllChats(value, bannerId: bannerId)
        }
    }

    public func setExcluded(basePath: String, bannerId: String, peerIds: [Int64]) {
        self.modify(basePath: basePath) { index in
            index.setExcluded(peerIds, bannerId: bannerId)
        }
    }

    public func remove(basePath: String, id: String) {
        try? FileManager.default.removeItem(atPath: self.imagePath(basePath: basePath, id: id))
        self.modify(basePath: basePath) { index in
            index.remove(id: id)
        }
    }

    private func modify(basePath: String, _ f: (inout ShadowChatBannersIndex) -> Void) {
        var index = self.index(basePath: basePath)
        f(&index)
        if let data = ShadowChatBanners.encode(index) {
            try? data.write(to: URL(fileURLWithPath: self.indexPath(basePath: basePath)), options: .atomic)
        }
        self.lock.lock()
        self.indexes[basePath] = index
        self.revisionValue += 1
        self.lock.unlock()
        let post = {
            NotificationCenter.default.post(name: ShadowChatBannerStore.didChangeNotification, object: nil, userInfo: ["basePath": basePath])
        }
        if Thread.isMainThread {
            post()
        } else {
            DispatchQueue.main.async(execute: post)
        }
    }
}

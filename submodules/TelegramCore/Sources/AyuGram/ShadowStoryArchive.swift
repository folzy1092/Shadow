import Foundation
import Postbox
import SwiftSignalKit

// Shadow: viewed stories are copied to a local archive (spec 7.5), so they stay
// available after the author deletes them or they expire. Files live in
// Application Support/shadow-stories/<account>/<peer>/<storyId>-<unixtime>.<ext>
// and never leave the device.
public final class ShadowStoryArchive {
    public static let shared = ShadowStoryArchive(
        directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("shadow-stories", isDirectory: true)
    )

    public struct Item: Equatable {
        public let peerId: Int64
        public let storyId: Int32
        public let date: Date
        public let url: URL
        public let isVideo: Bool
    }

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    private func folder(accountPeerId: Int64, peerId: Int64) -> URL {
        return self.directory.appendingPathComponent("\(accountPeerId)", isDirectory: true).appendingPathComponent("\(peerId)", isDirectory: true)
    }

    public func contains(accountPeerId: Int64, peerId: Int64, storyId: Int32) -> Bool {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: self.folder(accountPeerId: accountPeerId, peerId: peerId).path)) ?? []
        return names.contains(where: { $0.hasPrefix("\(storyId)-") })
    }

    func store(accountPeerId: Int64, peerId: Int64, storyId: Int32, storyDate: Int32, sourcePath: String, isVideo: Bool) {
        let folder = self.folder(accountPeerId: accountPeerId, peerId: peerId)
        let url = folder.appendingPathComponent("\(storyId)-\(storyDate).\(isVideo ? "mp4" : "jpg")")
        if FileManager.default.fileExists(atPath: url.path) {
            return
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? FileManager.default.copyItem(atPath: sourcePath, toPath: url.path)
    }

    // Saved stories of an account, newest first.
    public func items(accountPeerId: Int64) -> [Item] {
        let root = self.directory.appendingPathComponent("\(accountPeerId)", isDirectory: true)
        guard let peers = try? FileManager.default.contentsOfDirectory(atPath: root.path) else {
            return []
        }
        var result: [Item] = []
        for peer in peers {
            guard let peerId = Int64(peer) else {
                continue
            }
            let folder = root.appendingPathComponent(peer, isDirectory: true)
            for name in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [] {
                let url = folder.appendingPathComponent(name)
                let parts = url.deletingPathExtension().lastPathComponent.split(separator: "-")
                guard parts.count == 2, let storyId = Int32(parts[0]), let timestamp = Int32(parts[1]) else {
                    continue
                }
                result.append(Item(peerId: peerId, storyId: storyId, date: Date(timeIntervalSince1970: TimeInterval(timestamp)), url: url, isVideo: url.pathExtension == "mp4"))
            }
        }
        return result.sorted(by: { $0.date > $1.date })
    }

    public func remove(_ item: Item) {
        try? FileManager.default.removeItem(at: item.url)
    }
}

// Called when a story is marked as seen. Waits (up to a minute) for the media
// the viewer is downloading anyway and copies it; never fetches on its own.
func shadowArchiveViewedStory(account: Account, peerId: PeerId, id: Int32) {
    guard peerId != account.peerId else {
        return
    }
    let accountPeerId = account.peerId.toInt64()
    if ShadowStoryArchive.shared.contains(accountPeerId: accountPeerId, peerId: peerId.toInt64(), storyId: id) {
        return
    }
    let _ = (account.postbox.transaction { transaction -> (MediaResource, Bool, Int32)? in
        guard currentAyuGramSettings(transaction: transaction).saveViewedStories else {
            return nil
        }
        guard let stored = transaction.getStory(id: StoryId(peerId: peerId, id: id))?.get(Stories.StoredItem.self), case let .item(item) = stored, let media = item.media else {
            return nil
        }
        if let image = media as? TelegramMediaImage, let representation = largestImageRepresentation(image.representations) {
            return (representation.resource, false, item.timestamp)
        }
        if let file = media as? TelegramMediaFile, file.isVideo {
            return (file.resource, true, item.timestamp)
        }
        return nil
    }
    |> mapToSignal { value -> Signal<Never, NoError> in
        guard let value else {
            return .complete()
        }
        let (resource, isVideo, timestamp) = value
        return account.postbox.mediaBox.resourceData(resource)
        |> filter { $0.complete }
        |> take(1)
        |> timeout(60.0, queue: Queue.concurrentDefaultQueue(), alternate: .complete())
        |> mapToSignal { data -> Signal<Never, NoError> in
            ShadowStoryArchive.shared.store(accountPeerId: accountPeerId, peerId: peerId.toInt64(), storyId: id, storyDate: timestamp, sourcePath: data.path, isVideo: isVideo)
            return .complete()
        }
    }).start()
}

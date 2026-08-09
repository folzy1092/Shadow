import Foundation
import Postbox
import SwiftSignalKit

// AyuGram fork: local media persistence ("private gallery").
//
// This module keeps a private, fork-local copy of media so it survives even
// after Telegram deletes it: view-once / self-destruct media that expires, and
// (optionally) every incoming media the user receives. Files are stored as
// **hard links** to the MediaBox resource files whenever possible, so we add no
// extra disk usage while a resource is still cached — and, crucially, the bytes
// stay alive through the hard link even after the MediaBox deletes its own copy
// (which is what happens to secret-chat media on self-destruct).
//
// The gallery lives next to the postbox (a sibling of the MediaBox base path),
// so the MediaBox time/size cache sweeps never touch it. Each file is named so
// that the owning chat and message can be recovered from the name alone (needed
// for the pinned-chat whitelist in auto-clean and the per-category stats in the
// storage screen) — no separate index database is required.
//
// This feature is independent of Ghost Master: it is about local retention, not
// about hiding outgoing signals.

public enum AyuSavedMedia {
    // Directory name placed alongside the MediaBox (i.e. inside the postbox
    // directory, NOT inside the swept media directory).
    private static let directoryName = "ayu-saved-media"
    // All saved files start with this prefix so we can enumerate only our own
    // files and never trip over anything else that might share the directory.
    private static let filePrefix = "ayu"

    // Resolve (and lazily create) the gallery directory for a given MediaBox.
    // `mediaBox.basePath` is `<account>/postbox/media`; we drop the last path
    // component and drop in a sibling, ending up at `<account>/postbox/…`.
    public static func directory(basePath: String) -> String {
        let parent = (basePath as NSString).deletingLastPathComponent
        let path = parent + "/" + directoryName
        return path
    }

    public static func ensureDirectory(basePath: String) -> String {
        let path = directory(basePath: basePath)
        let _ = try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
        return path
    }

    // MARK: - Media extraction

    // A single savable resource plus the file extension we should store it with.
    struct SavableResource {
        let resource: MediaResource
        let fileExtension: String
    }

    private static func fileExtension(for file: TelegramMediaFile) -> String {
        if let name = file.fileName {
            let ext = (name as NSString).pathExtension
            if !ext.isEmpty {
                return ext.lowercased()
            }
        }
        if file.isVoice {
            return "ogg"
        }
        if file.isInstantVideo || file.isVideo || file.isAnimated {
            return "mp4"
        }
        if file.isMusic {
            return "mp3"
        }
        switch file.mimeType {
        case "image/jpeg", "image/jpg":
            return "jpg"
        case "image/png":
            return "png"
        case "image/gif":
            return "gif"
        case "image/webp":
            return "webp"
        case "audio/ogg":
            return "ogg"
        case "audio/mpeg":
            return "mp3"
        case "video/mp4":
            return "mp4"
        case "application/pdf":
            return "pdf"
        default:
            return "bin"
        }
    }

    // Returns the resources worth persisting for one media value. For images we
    // keep only the largest representation; for files we keep the main resource
    // (thumbnails are skipped — they are tiny and not the actual content).
    static func savableResources(from media: Media) -> [SavableResource] {
        if let image = media as? TelegramMediaImage {
            var best: TelegramMediaImageRepresentation?
            for representation in image.representations {
                if let current = best {
                    let candidateArea = Int(representation.dimensions.width) * Int(representation.dimensions.height)
                    let currentArea = Int(current.dimensions.width) * Int(current.dimensions.height)
                    if candidateArea > currentArea {
                        best = representation
                    }
                } else {
                    best = representation
                }
            }
            if let best = best {
                return [SavableResource(resource: best.resource, fileExtension: "jpg")]
            }
            return []
        } else if let file = media as? TelegramMediaFile {
            // Never persist stickers / animated emoji — they are not user media.
            if file.isSticker || file.isAnimatedSticker || file.isVideoSticker || file.isVideoEmoji {
                return []
            }
            return [SavableResource(resource: file.resource, fileExtension: fileExtension(for: file))]
        }
        return []
    }

    // MARK: - File naming

    private static func sanitize(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count)
        for character in value.unicodeScalars {
            if (character >= "0" && character <= "9") || (character >= "a" && character <= "z") || (character >= "A" && character <= "Z") {
                result.unicodeScalars.append(character)
            }
        }
        return result
    }

    // ayu_<peerId>_<msgNamespace>_<msgId>_<resourceId>.<ext>
    static func fileName(peerId: PeerId, messageId: MessageId?, resource: MediaResource, fileExtension: String) -> String {
        let peerComponent = "\(peerId.toInt64())"
        let namespaceComponent = messageId.map { "\($0.namespace)" } ?? "x"
        let idComponent = messageId.map { "\($0.id)" } ?? "x"
        let resourceComponent = sanitize(resource.id.stringRepresentation)
        return "\(filePrefix)_\(peerComponent)_\(namespaceComponent)_\(idComponent)_\(resourceComponent).\(fileExtension)"
    }

    // The gallery file name for a message's principal (largest / main) savable
    // resource, or nil if the message has no savable media. Deterministic, so
    // the edit-history attribute can store it and the UI can locate the file
    // later. Does not touch disk.
    public static func principalFileName(peerId: PeerId, messageId: MessageId?, mediaList: [Media]) -> String? {
        for media in mediaList {
            if let first = savableResources(from: media).first {
                return fileName(peerId: peerId, messageId: messageId, resource: first.resource, fileExtension: first.fileExtension)
            }
        }
        return nil
    }

    // A coarse media kind for UI iconography, derived without opening the file.
    public static func mediaKind(for mediaList: [Media]) -> String? {
        for media in mediaList {
            if media is TelegramMediaImage {
                return "image"
            } else if let file = media as? TelegramMediaFile {
                if file.isSticker || file.isAnimatedSticker || file.isVideoSticker || file.isVideoEmoji {
                    continue
                }
                if file.isVoice {
                    return "voice"
                }
                if file.isInstantVideo {
                    return "roundVideo"
                }
                if file.isVideo || file.isAnimated {
                    return "video"
                }
                return "file"
            }
        }
        return nil
    }

    // Recover the owning peer id from a saved file name (for the whitelist).
    public static func peerId(fromFileName name: String) -> Int64? {
        guard name.hasPrefix(filePrefix + "_") else {
            return nil
        }
        let components = name.components(separatedBy: "_")
        guard components.count >= 2 else {
            return nil
        }
        return Int64(components[1])
    }

    // MARK: - Saving

    // Persist all savable media of a message into the gallery. Uses hard links
    // (zero extra disk, survives MediaBox deletion); falls back to a byte copy
    // if linking is not possible. Skips resources that are not fully downloaded
    // and files that already exist. Returns the number of newly saved files.
    @discardableResult
    public static func saveMessageMedia(mediaBox: MediaBox, message: Message) -> Int {
        return saveMedia(mediaBox: mediaBox, peerId: message.id.peerId, messageId: message.id, mediaList: message.effectiveMedia)
    }

    @discardableResult
    public static func saveMedia(mediaBox: MediaBox, peerId: PeerId, messageId: MessageId?, mediaList: [Media]) -> Int {
        var savable: [SavableResource] = []
        for media in mediaList {
            savable.append(contentsOf: savableResources(from: media))
        }
        if savable.isEmpty {
            return 0
        }

        var sources: [(source: String, destinationName: String)] = []
        for entry in savable {
            guard let sourcePath = mediaBox.completedResourcePath(entry.resource) else {
                continue
            }
            let name = fileName(peerId: peerId, messageId: messageId, resource: entry.resource, fileExtension: entry.fileExtension)
            sources.append((sourcePath, name))
        }
        if sources.isEmpty {
            return 0
        }

        let directoryPath = ensureDirectory(basePath: mediaBox.basePath)
        var savedCount = 0
        for item in sources {
            let destinationPath = directoryPath + "/" + item.destinationName
            if FileManager.default.fileExists(atPath: destinationPath) {
                continue
            }
            // Prefer a hard link; fall back to a copy on failure.
            do {
                try FileManager.default.linkItem(atPath: item.source, toPath: destinationPath)
                savedCount += 1
            } catch {
                if (try? FileManager.default.copyItem(atPath: item.source, toPath: destinationPath)) != nil {
                    savedCount += 1
                }
            }
        }
        return savedCount
    }

    // MARK: - Auto-save of all incoming media (3b)

    // Given the reference of a media fetch, returns a closure that persists the
    // media once the fetch completes — or nil if this fetch is not an incoming
    // user-message media we should auto-save. The heavy lifting is deferred to
    // the returned closure so the fetch funnel stays cheap. Gated by the
    // `saveAllIncomingMedia` setting; independent of copy-protection and of the
    // system "Save to Camera Roll" (we read straight from the MediaBox).
    public static func autoSaveIncomingHook(mediaBox: MediaBox, reference: MediaResourceReference) -> (() -> Void)? {
        guard ayuGramSettingsCurrent.saveAllIncomingMedia else {
            return nil
        }
        guard case let .media(mediaReference, resource) = reference else {
            return nil
        }
        guard case let .message(messageReference, media) = mediaReference else {
            return nil
        }
        guard messageReference.isIncoming == true, let messageId = messageReference.id else {
            return nil
        }
        // Only act for the media's principal savable resource, so a video's
        // thumbnail fetch doesn't trigger a (thumbnail-only) save.
        let savable = savableResources(from: media)
        guard savable.contains(where: { $0.resource.id == resource.id }) else {
            return nil
        }
        let peerId = messageId.peerId
        return {
            Queue.concurrentDefaultQueue().async {
                let _ = saveMedia(mediaBox: mediaBox, peerId: peerId, messageId: messageId, mediaList: [media])
            }
        }
    }

    // MARK: - Auto-clean (3c)

    // Enumerate the gallery for the storage screen / cleanup. Each entry carries
    // the owning peer (if recoverable), byte size and last-modified time.
    public struct Entry {
        public let path: String
        public let name: String
        public let peerId: Int64?
        public let size: Int64
        public let modified: Double
    }

    public static func entries(basePath: String) -> [Entry] {
        let path = directory(basePath: basePath)
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: path) else {
            return []
        }
        var result: [Entry] = []
        for name in names {
            guard name.hasPrefix(filePrefix + "_") else {
                continue
            }
            let full = path + "/" + name
            guard let attributes = try? fileManager.attributesOfItem(atPath: full) else {
                continue
            }
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0.0
            result.append(Entry(path: full, name: name, peerId: peerId(fromFileName: name), size: size, modified: modified))
        }
        return result
    }

    public static func totalSize(basePath: String) -> Int64 {
        return entries(basePath: basePath).reduce(0) { $0 + $1.size }
    }

    // MARK: - Custom chat-list banner (single fixed image)

    // The banner is a single user-chosen image rendered behind the chat list's
    // top region. It lives in the same fork-private directory (never swept by the
    // MediaBox cache) under a fixed name, so there is at most one at a time.
    private static let bannerFileName = "shadow-banner.jpg"

    public static func bannerPath(basePath: String) -> String {
        return ensureDirectory(basePath: basePath) + "/" + bannerFileName
    }

    // True if a banner image is currently stored on disk.
    public static func hasBanner(basePath: String) -> Bool {
        return FileManager.default.fileExists(atPath: bannerPath(basePath: basePath))
    }

    // Persist the given JPEG data as the banner, replacing any previous one.
    // Returns true on success.
    @discardableResult
    public static func saveBanner(basePath: String, jpegData: Data) -> Bool {
        let path = bannerPath(basePath: basePath)
        do {
            try? FileManager.default.removeItem(atPath: path)
            try jpegData.write(to: URL(fileURLWithPath: path), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    // Load the stored banner bytes, or nil if none.
    public static func bannerData(basePath: String) -> Data? {
        let path = bannerPath(basePath: basePath)
        return try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
    }

    // Delete the stored banner. Returns true if a file was removed.
    @discardableResult
    public static func removeBanner(basePath: String) -> Bool {
        let path = bannerPath(basePath: basePath)
        return (try? FileManager.default.removeItem(atPath: path)) != nil
    }

    // MARK: - Custom "My Profile" background (single fixed image, visual-only)

    // Mirrors the banner storage exactly. Shown only on the local user's own
    // "Мой профиль" screen — never sent to the server, never seen by anyone else.
    private static let profileBackgroundFileName = "shadow-profile-background.jpg"

    public static func profileBackgroundPath(basePath: String) -> String {
        return ensureDirectory(basePath: basePath) + "/" + profileBackgroundFileName
    }

    public static func hasProfileBackground(basePath: String) -> Bool {
        return FileManager.default.fileExists(atPath: profileBackgroundPath(basePath: basePath))
    }

    @discardableResult
    public static func saveProfileBackground(basePath: String, jpegData: Data) -> Bool {
        let path = profileBackgroundPath(basePath: basePath)
        do {
            try? FileManager.default.removeItem(atPath: path)
            try jpegData.write(to: URL(fileURLWithPath: path), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    public static func profileBackgroundData(basePath: String) -> Data? {
        let path = profileBackgroundPath(basePath: basePath)
        return try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
    }

    @discardableResult
    public static func removeProfileBackground(basePath: String) -> Bool {
        let path = profileBackgroundPath(basePath: basePath)
        return (try? FileManager.default.removeItem(atPath: path)) != nil
    }

    // Remove everything in the gallery. Returns freed bytes.
    @discardableResult
    public static func clearAll(basePath: String) -> Int64 {
        let fileManager = FileManager.default
        var freed: Int64 = 0
        for entry in entries(basePath: basePath) {
            if (try? fileManager.removeItem(atPath: entry.path)) != nil {
                freed += entry.size
            }
        }
        return freed
    }

    // Delete gallery files older than `maxAge` seconds, skipping any file whose
    // owning peer is in `keepPeerIds` (the pinned-chat whitelist). `now` is the
    // reference time (unix). Returns the number of files removed.
    @discardableResult
    public static func cleanup(basePath: String, maxAge: Int32, keepPeerIds: Set<Int64>, now: Double) -> Int {
        guard maxAge > 0 else {
            return 0
        }
        let fileManager = FileManager.default
        var removed = 0
        for entry in entries(basePath: basePath) {
            if let peerId = entry.peerId, keepPeerIds.contains(peerId) {
                continue
            }
            if now - entry.modified >= Double(maxAge) {
                if (try? fileManager.removeItem(atPath: entry.path)) != nil {
                    removed += 1
                }
            }
        }
        return removed
    }

    // Trim the gallery so its total size does not exceed `maxBytes`, always
    // removing the OLDEST files first and skipping any file whose owning peer is
    // in `keepPeerIds`. `maxBytes <= 0` disables the size limit. Returns the
    // number of files removed. Files that can't be removed (whitelisted) still
    // count toward the total, so the limit is best-effort when the whitelist is
    // large.
    @discardableResult
    public static func cleanupBySize(basePath: String, maxBytes: Int64, keepPeerIds: Set<Int64>) -> Int {
        guard maxBytes > 0 else {
            return 0
        }
        let all = entries(basePath: basePath)
        var total: Int64 = all.reduce(0) { $0 + $1.size }
        if total <= maxBytes {
            return 0
        }
        // Oldest first.
        let ordered = all.sorted { $0.modified < $1.modified }
        let fileManager = FileManager.default
        var removed = 0
        for entry in ordered {
            if total <= maxBytes {
                break
            }
            if let peerId = entry.peerId, keepPeerIds.contains(peerId) {
                continue
            }
            if (try? fileManager.removeItem(atPath: entry.path)) != nil {
                total -= entry.size
                removed += 1
            }
        }
        return removed
    }
}

// Periodic auto-clean task. Started once per account from the managed
// operations. Every few minutes it reads the current interval and the pinned
// whitelist, then prunes the gallery. Cheap when disabled (interval == 0).
public func managedAyuMediaAutoClean(postbox: Postbox) -> Signal<Never, NoError> {
    let checkInterval: Double = 300.0
    let step = postbox.transaction { transaction -> (Int32, Int64, Set<Int64>) in
        let settings = currentAyuGramSettings(transaction: transaction)
        var keep = Set<Int64>()
        if settings.mediaAutoCleanKeepPinned {
            for item in transaction.getPinnedItemIds(groupId: .root) {
                if case let .peer(peerId) = item {
                    keep.insert(peerId.toInt64())
                }
            }
            for item in transaction.getPinnedItemIds(groupId: Namespaces.PeerGroup.archive) {
                if case let .peer(peerId) = item {
                    keep.insert(peerId.toInt64())
                }
            }
        }
        // Channel / bot exclusions: scan the peers owning gallery files and add
        // the matching ones to the whitelist. Channels are recognised by the peer
        // id namespace alone; bots require a peer lookup.
        if settings.mediaAutoCleanKeepChannels || settings.mediaAutoCleanKeepBots {
            var ownerIds = Set<Int64>()
            for entry in AyuSavedMedia.entries(basePath: postbox.mediaBox.basePath) {
                if let peerId = entry.peerId {
                    ownerIds.insert(peerId)
                }
            }
            for ownerId in ownerIds {
                let peerId = PeerId(ownerId)
                if settings.mediaAutoCleanKeepChannels, peerId.namespace == Namespaces.Peer.CloudChannel {
                    keep.insert(ownerId)
                    continue
                }
                if settings.mediaAutoCleanKeepBots, peerId.namespace == Namespaces.Peer.CloudUser {
                    if let user = transaction.getPeer(peerId) as? TelegramUser, user.botInfo != nil {
                        keep.insert(ownerId)
                    }
                }
            }
        }
        // Same retention window applies to the kept (anti-deleted) messages
        // themselves — not just to their media files in the gallery.
        ayuForkStorePruneKeptDeleted(transaction: transaction, mediaBox: postbox.mediaBox, maxAge: settings.mediaAutoCleanInterval, now: Int32(Date().timeIntervalSince1970))
        return (settings.mediaAutoCleanInterval, settings.attachmentSizeLimit, keep)
    }
    |> mapToSignal { maxAge, maxBytes, keep -> Signal<Never, NoError> in
        let basePath = postbox.mediaBox.basePath
        return Signal<Never, NoError> { subscriber in
            if maxAge > 0 {
                let _ = AyuSavedMedia.cleanup(basePath: basePath, maxAge: maxAge, keepPeerIds: keep, now: Date().timeIntervalSince1970)
            }
            if maxBytes > 0 {
                let _ = AyuSavedMedia.cleanupBySize(basePath: basePath, maxBytes: maxBytes, keepPeerIds: keep)
            }
            subscriber.putCompletion()
            return EmptyDisposable
        }
        |> runOn(Queue.concurrentDefaultQueue())
    }

    return (
        step
        |> then(
            Signal<Never, NoError>.complete()
            |> suspendAwareDelay(checkInterval, queue: Queue.concurrentDefaultQueue())
        )
    )
    |> restart
}

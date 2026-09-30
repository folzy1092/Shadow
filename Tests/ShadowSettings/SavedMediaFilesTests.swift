import Foundation
@main struct SavedMediaFilesTests {
    static func main() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let source = root.appendingPathComponent("cache").path
        let destination = root.appendingPathComponent("saved").path
        let bytes = Data("media bytes".utf8)
        try bytes.write(to: URL(fileURLWithPath: source))
        try manager.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: source)
        precondition(ShadowSavedMediaFiles.save(source: source, destination: destination, resourceId: "resource", purpose: "editHistory", now: 200))
        precondition(ShadowSavedMediaFiles.metadata(path: destination).savedAt == 200)
        precondition((try? manager.attributesOfItem(atPath: source)[.modificationDate] as? Date)?.timeIntervalSince1970 == 100)
        precondition(!ShadowSavedMediaFiles.save(source: "/nonexistent-shadow-resource", destination: destination, resourceId: "resource", purpose: "retained", now: 300))
        precondition(!ShadowSavedMediaFiles.removeIfOnlyEditHistory(path: destination))
        try manager.removeItem(atPath: source)
        precondition((try? Data(contentsOf: URL(fileURLWithPath: destination))) == bytes)
        let restored = root.appendingPathComponent("restored")
        precondition(ShadowSavedMediaFiles.copy(source: destination, destination: restored))
        precondition((try? Data(contentsOf: restored)) == bytes && manager.fileExists(atPath: destination))
        let edit = root.appendingPathComponent("edit").path
        precondition(ShadowSavedMediaFiles.save(source: destination, destination: edit, resourceId: "edit-resource", purpose: "editHistory", now: 400))
        precondition(ShadowSavedMediaFiles.removeIfOnlyEditHistory(path: edit))
        precondition(!manager.fileExists(atPath: edit + ShadowSavedMediaFiles.metadataSuffix))
        let legacy = root.appendingPathComponent("legacy").path
        try bytes.write(to: URL(fileURLWithPath: legacy))
        precondition(ShadowSavedMediaFiles.metadata(path: legacy, resourceId: "legacy-resource", now: 500).savedAt == 500)
        precondition(!ShadowSavedMediaFiles.removeIfOnlyEditHistory(path: legacy))
        DispatchQueue.concurrentPerform(iterations: 30) { index in
            let path = root.appendingPathComponent("concurrent-\(index % 3)").path
            _ = ShadowSavedMediaFiles.save(source: destination, destination: path, resourceId: "resource", now: 600)
            _ = ShadowSavedMediaFiles.remove(path: path)
        }
        let entries = try manager.contentsOfDirectory(atPath: root.path)
        precondition(!entries.contains { $0.hasPrefix(".capture-") })
        print("Saved media: capture dates, independent links, ownership, migration and concurrency passed")
    }
}

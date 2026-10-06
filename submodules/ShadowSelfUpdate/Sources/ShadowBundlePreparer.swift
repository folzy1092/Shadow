import Foundation

// Shadow: makes an unpacked CI build look like the installed copy before it is
// re-signed, so iOS treats it as an update of this app (same data, same login):
// - main bundle id = the installed one (ESign installs ph.telegra.Telegra);
//   extension ids and BGTask ids follow the same prefix;
// - only the extensions the installed copy has are kept (whatever the
//   installer kept or dropped worked for this certificate), the same for Watch;
// - every kept extension embeds the same profile as the app.
//
// Foundation only, so it is unit-tested by the Foundation suite.
public enum ShadowBundlePreparer {
    public struct Installed: Equatable {
        public var bundleId: String
        // Folder names in PlugIns, e.g. "NotificationService.appex".
        public var plugIns: Set<String>
        public var hasWatch: Bool

        public init(bundleId: String, plugIns: Set<String>, hasWatch: Bool) {
            self.bundleId = bundleId
            self.plugIns = plugIns
            self.hasWatch = hasWatch
        }

        public static func current(bundle: Bundle = .main) -> Installed {
            var plugIns = Set<String>()
            if let url = bundle.builtInPlugInsURL, let names = try? FileManager.default.contentsOfDirectory(atPath: url.path) {
                plugIns = Set(names.filter { $0.hasSuffix(".appex") })
            }
            let hasWatch = FileManager.default.fileExists(atPath: bundle.bundleURL.appendingPathComponent("Watch").path)
            return Installed(bundleId: bundle.bundleIdentifier ?? "", plugIns: plugIns, hasWatch: hasWatch)
        }
    }

    public struct Summary: Equatable {
        public var previousBundleId: String
        public var removedPlugIns: [String]
        public var keptPlugIns: [String]
        public var removedWatch: Bool
    }

    public enum PrepareError: LocalizedError {
        case noApp
        case badInfoPlist
        case noInstalledBundleId

        public var errorDescription: String? {
            switch self {
            case .noApp: return "В IPA нет Payload/*.app."
            case .badInfoPlist: return "Не удалось прочитать Info.plist сборки."
            case .noInstalledBundleId: return "Не удалось определить bundle ID установленного Shadow."
            }
        }
    }

    public static func findApp(inPayloadParent root: URL) -> URL? {
        let payload = root.appendingPathComponent("Payload", isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: payload.path) else {
            return nil
        }
        return names.sorted().first(where: { $0.hasSuffix(".app") }).map { payload.appendingPathComponent($0, isDirectory: true) }
    }

    // "old.id.Share" -> "new.id.Share"; ids outside the old prefix stay.
    public static func rebase(_ identifier: String, from oldPrefix: String, to newPrefix: String) -> String {
        if identifier == oldPrefix {
            return newPrefix
        }
        if identifier.hasPrefix(oldPrefix + ".") {
            return newPrefix + identifier.dropFirst(oldPrefix.count)
        }
        return identifier
    }

    public static func prepare(app: URL, installed: Installed, profileURL: URL?) throws -> Summary {
        guard !installed.bundleId.isEmpty else {
            throw PrepareError.noInstalledBundleId
        }
        let fileManager = FileManager.default
        let infoURL = app.appendingPathComponent("Info.plist")
        guard let mainPlist = readPlist(infoURL), let previous = mainPlist.0["CFBundleIdentifier"] as? String else {
            throw PrepareError.badInfoPlist
        }
        var info = mainPlist.0
        let format = mainPlist.1
        let target = installed.bundleId

        info["CFBundleIdentifier"] = target
        if let tasks = info["BGTaskSchedulerPermittedIdentifiers"] as? [String] {
            info["BGTaskSchedulerPermittedIdentifiers"] = tasks.map { rebase($0, from: previous, to: target) }
        }
        try writePlist(info, format: format, to: infoURL)

        var removed: [String] = []
        var kept: [String] = []
        let plugInsURL = app.appendingPathComponent("PlugIns", isDirectory: true)
        if let names = try? fileManager.contentsOfDirectory(atPath: plugInsURL.path) {
            for name in names.sorted() where name.hasSuffix(".appex") {
                let appex = plugInsURL.appendingPathComponent(name, isDirectory: true)
                if !installed.plugIns.contains(name) {
                    try fileManager.removeItem(at: appex)
                    removed.append(name)
                    continue
                }
                kept.append(name)
                let appexInfoURL = appex.appendingPathComponent("Info.plist")
                if let appexPlist = readPlist(appexInfoURL) {
                    var appexInfo = appexPlist.0
                    let appexFormat = appexPlist.1
                    if let identifier = appexInfo["CFBundleIdentifier"] as? String {
                        appexInfo["CFBundleIdentifier"] = rebase(identifier, from: previous, to: target)
                    }
                    if let companion = appexInfo["WKCompanionAppBundleIdentifier"] as? String {
                        appexInfo["WKCompanionAppBundleIdentifier"] = rebase(companion, from: previous, to: target)
                    }
                    if var ext = appexInfo["NSExtension"] as? [String: Any], var attributes = ext["NSExtensionAttributes"] as? [String: Any], let wk = attributes["WKAppBundleIdentifier"] as? String {
                        attributes["WKAppBundleIdentifier"] = rebase(wk, from: previous, to: target)
                        ext["NSExtensionAttributes"] = attributes
                        appexInfo["NSExtension"] = ext
                    }
                    try writePlist(appexInfo, format: appexFormat, to: appexInfoURL)
                }
                let embedded = appex.appendingPathComponent("embedded.mobileprovision")
                try? fileManager.removeItem(at: embedded)
                if let profileURL {
                    try fileManager.copyItem(at: profileURL, to: embedded)
                }
            }
            if kept.isEmpty {
                try fileManager.removeItem(at: plugInsURL)
            }
        }

        var removedWatch = false
        if !installed.hasWatch {
            for name in ["Watch", "com.apple.WatchPlaceholder"] {
                let url = app.appendingPathComponent(name, isDirectory: true)
                if fileManager.fileExists(atPath: url.path) {
                    try fileManager.removeItem(at: url)
                    removedWatch = true
                }
            }
        }

        return Summary(previousBundleId: previous, removedPlugIns: removed, keptPlugIns: kept, removedWatch: removedWatch)
    }

    private static func readPlist(_ url: URL) -> ([String: Any], PropertyListSerialization.PropertyListFormat)? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        var format = PropertyListSerialization.PropertyListFormat.xml
        guard let dict = (try? PropertyListSerialization.propertyList(from: data, options: [], format: &format)) as? [String: Any] else {
            return nil
        }
        return (dict, format)
    }

    private static func writePlist(_ dict: [String: Any], format: PropertyListSerialization.PropertyListFormat, to url: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: format, options: 0)
        try data.write(to: url, options: .atomic)
    }
}

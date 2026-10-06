import Foundation
import SwiftSignalKit
import Zsign
import ZipArchive

// Shadow: "Обновить" in the Shadow hub. Downloads the announced IPA, makes it
// look like the installed copy (ShadowBundlePreparer), signs it on the device
// with the pair from "Автообновление" (zsign), packs it and offers it to iOS
// through a local HTTPS server and itms-services. iOS then replaces this app;
// the data container stays because the bundle id and the team do not change.
//
// One run at a time, shared by every screen (leaving the hub does not stop it).
public final class ShadowSelfUpdater: NSObject {
    public static let shared = ShadowSelfUpdater()

    public enum Stage: Equatable {
        case idle
        case downloading(received: Int64, total: Int64)
        case unpacking(Double)
        case signing
        case packing(Double)
        case startingServer
        // The itms-services prompt is (or should be) on screen. hint: iOS has
        // not asked for the manifest for a while.
        case waitingForConfirmation(hint: Bool)
        case sending(sent: Int64, total: Int64)
        // The whole IPA is with iOS; Shadow is about to be closed by the install.
        case installing
        case failed(String)
    }

    public struct State: Equatable {
        public var stage: Stage
        public var build: Int?
        // The signed IPA, to share manually if the system install does not start.
        public var signedIPA: URL?

        public var isRunning: Bool {
            switch self.stage {
            case .idle, .failed, .installing:
                return false
            default:
                return true
            }
        }
    }

    private let statePromise = ValuePromise<State>(State(stage: .idle, build: nil, signedIPA: nil), ignoreRepeated: true)
    // State and run bookkeeping; never blocked by the slow steps.
    private let queue = DispatchQueue(label: "ShadowSelfUpdater", qos: .userInitiated)
    // Unpacking, signing and packing.
    private let workQueue = DispatchQueue(label: "ShadowSelfUpdater.work", qos: .userInitiated)
    private var stateValue = State(stage: .idle, build: nil, signedIPA: nil)
    private var runId = 0
    private var session: URLSession?
    private var downloadTask: URLSessionDownloadTask?
    private var server: ShadowInstallServer?
    private var keepAwake: Disposable?
    private var hintTimer: DispatchWorkItem?
    private var openInstallURL: ((URL) -> Void)?

    public var state: Signal<State, NoError> {
        return self.statePromise.get()
    }

    public var currentState: State {
        return self.queue.sync { self.stateValue }
    }

    public var workDirectory: URL {
        return FileManager.default.temporaryDirectory.appendingPathComponent("ShadowUpdate", isDirectory: true)
    }

    // openURL opens the itms-services link (UIApplication); keepAwake holds the
    // screen on while the update is prepared.
    // Call on the main thread.
    public func start(ipaURL: URL, build: Int, version: String?, openURL: @escaping (URL) -> Void, keepAwake: @escaping () -> Disposable) {
        let awake = keepAwake()
        self.queue.async {
            if self.stateValue.isRunning {
                DispatchQueue.main.async {
                    awake.dispose()
                }
                return
            }
            self.runId += 1
            let runId = self.runId
            self.openInstallURL = openURL
            self.cleanUp()
            self.releaseAwake()
            self.keepAwake = awake
            self.setState(State(stage: .downloading(received: 0, total: 0), build: build, signedIPA: nil))
            self.download(ipaURL, runId: runId, build: build, version: version)
        }
    }

    public func cancel() {
        self.queue.async {
            self.runId += 1
            self.finish(State(stage: .idle, build: nil, signedIPA: nil))
            self.cleanUp()
        }
    }

    // MARK: - Steps

    private func download(_ url: URL, runId: Int, build: Int, version: String?) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60.0
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let delegate = DownloadDelegate()
        delegate.progress = { [weak self] received, total in
            self?.queue.async {
                guard let self, self.runId == runId else {
                    return
                }
                self.setState(stage: .downloading(received: received, total: total))
            }
        }
        let destination = self.workDirectory.appendingPathComponent("download.ipa")
        delegate.destination = destination
        delegate.completion = { [weak self] error in
            self?.queue.async {
                guard let self, self.runId == runId else {
                    return
                }
                self.session?.finishTasksAndInvalidate()
                self.session = nil
                self.downloadTask = nil
                if let error {
                    self.fail(error)
                    return
                }
                self.workQueue.async {
                    self.prepare(downloaded: destination, runId: runId, build: build, version: version)
                }
            }
        }
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        self.session = session
        let task = session.downloadTask(with: url)
        self.downloadTask = task
        task.resume()
    }

    // Runs on workQueue; state changes hop to queue.
    private func prepare(downloaded: URL, runId: Int, build: Int, version: String?) {
        let isCurrent: () -> Bool = { [weak self] in
            guard let self else {
                return false
            }
            return self.queue.sync { self.runId == runId }
        }
        let update: (Stage) -> Void = { [weak self] stage in
            self?.queue.async {
                guard let self, self.runId == runId else {
                    return
                }
                self.setState(stage: stage)
            }
        }
        let failRun: (Error) -> Void = { [weak self] error in
            self?.queue.async {
                guard let self, self.runId == runId else {
                    return
                }
                self.fail(error)
            }
        }

        let store = ShadowSigningStore.shared
        guard store.isConfigured else {
            failRun(UpdateError.notConfigured)
            return
        }
        let root = self.workDirectory.appendingPathComponent("package", isDirectory: true)
        update(.unpacking(0.0))
        var unzipError: Error?
        var lastUnzipPercent = -1
        let unzipped = SSZipArchive.unzipFile(atPath: downloaded.path, toDestination: root.path, overwrite: true, password: nil, progressHandler: { _, _, entry, total in
            guard total > 0 else {
                return
            }
            let percent = Int(Double(entry) * 100.0 / Double(total))
            if percent != lastUnzipPercent {
                lastUnzipPercent = percent
                update(.unpacking(Double(percent) / 100.0))
            }
        }, completionHandler: { _, _, error in
            unzipError = error
        })
        try? FileManager.default.removeItem(at: downloaded)
        guard isCurrent() else {
            return
        }
        guard unzipped, let app = ShadowBundlePreparer.findApp(inPayloadParent: root) else {
            failRun(unzipError ?? UpdateError.badArchive)
            return
        }

        let installed = ShadowBundlePreparer.Installed.current()
        do {
            _ = try ShadowBundlePreparer.prepare(app: app, installed: installed, profileURL: store.profileURL)
        } catch {
            failRun(error)
            return
        }

        update(.signing)
        if let error = ShadowZsign.sign(appPath: app.path, provisionPath: store.profileURL.path, p12Path: store.certificateURL.path, password: store.password ?? "") {
            failRun(UpdateError.signing(error))
            return
        }
        guard isCurrent() else {
            return
        }
        let bundleVersion = Bundle(path: app.path)?.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "\(build)"

        update(.packing(0.0))
        let ipa = self.workDirectory.appendingPathComponent("Shadow-\(build)-signed.ipa")
        var lastZipPercent = -1
        // Level 1: fast, and the IPA stays about the size of the download.
        let zipped = SSZipArchive.createZipFile(atPath: ipa.path, withContentsOfDirectory: root.path, keepParentDirectory: false, compressionLevel: 1, password: nil, aes: false, progressHandler: { entry, total in
            guard total > 0 else {
                return
            }
            let percent = Int(Double(entry) * 100.0 / Double(total))
            if percent != lastZipPercent {
                lastZipPercent = percent
                update(.packing(Double(percent) / 100.0))
            }
        })
        try? FileManager.default.removeItem(at: root)
        guard isCurrent() else {
            return
        }
        guard zipped else {
            failRun(UpdateError.packing)
            return
        }

        let item = ShadowInstallServer.Item(
            ipaURL: ipa,
            bundleId: installed.bundleId,
            bundleVersion: bundleVersion,
            title: "Shadow" + (version.map { " \($0)" } ?? "")
        )
        self.queue.async {
            guard self.runId == runId else {
                return
            }
            var state = self.stateValue
            state.signedIPA = ipa
            state.stage = .startingServer
            self.setState(state)
            ShadowLocalTLSIdentity.load { [weak self] result in
                self?.queue.async {
                    guard let self, self.runId == runId else {
                        return
                    }
                    switch result {
                    case let .failure(error):
                        self.fail(error)
                    case let .success(material):
                        self.serve(item: item, material: material, runId: runId)
                    }
                }
            }
        }
    }

    private func serve(item: ShadowInstallServer.Item, material: ShadowLocalTLSIdentity.Material, runId: Int) {
        let server = ShadowInstallServer(item: item)
        self.server = server
        server.onManifestRequested = { [weak self] in
            self?.queue.async {
                guard let self, self.runId == runId else {
                    return
                }
                self.hintTimer?.cancel()
                self.setState(stage: .sending(sent: 0, total: 0))
            }
        }
        server.onPayloadProgress = { [weak self] sent, total in
            self?.queue.async {
                guard let self, self.runId == runId, case let .sending(previous, _) = self.stateValue.stage else {
                    return
                }
                // Percent steps are enough for the list.
                if total > 0, previous > 0, sent * 100 / total == previous * 100 / total, sent < total {
                    return
                }
                self.setState(stage: .sending(sent: sent, total: total))
            }
        }
        server.onPayloadFinished = { [weak self] in
            self?.queue.async {
                guard let self, self.runId == runId else {
                    return
                }
                var state = self.stateValue
                state.stage = .installing
                self.finish(state)
            }
        }
        server.start(material: material) { [weak self] result in
            self?.queue.async {
                guard let self, self.runId == runId else {
                    return
                }
                switch result {
                case let .failure(error):
                    self.fail(error)
                case let .success(manifestURL):
                    guard let installURL = ShadowInstallServer.installURL(manifest: manifestURL) else {
                        self.fail(UpdateError.packing)
                        return
                    }
                    self.setState(stage: .waitingForConfirmation(hint: false))
                    let hint = DispatchWorkItem { [weak self] in
                        guard let self, self.runId == runId, case .waitingForConfirmation(hint: false) = self.stateValue.stage else {
                            return
                        }
                        self.setState(stage: .waitingForConfirmation(hint: true))
                    }
                    self.hintTimer = hint
                    self.queue.asyncAfter(deadline: .now() + 25.0, execute: hint)
                    let open = self.openInstallURL
                    DispatchQueue.main.async {
                        open?(installURL)
                    }
                }
            }
        }
    }

    // Opens the itms-services prompt again (the user dismissed it).
    public func retryInstallPrompt() {
        self.queue.async {
            guard case .waitingForConfirmation = self.stateValue.stage, let manifestURL = self.server?.manifestURL, let installURL = ShadowInstallServer.installURL(manifest: manifestURL) else {
                return
            }
            let open = self.openInstallURL
            DispatchQueue.main.async {
                open?(installURL)
            }
        }
    }

    // MARK: - State

    private func setState(stage: Stage) {
        var state = self.stateValue
        state.stage = stage
        self.setState(state)
    }

    private func setState(_ state: State) {
        self.stateValue = state
        self.statePromise.set(state)
    }

    private func fail(_ error: Error) {
        var state = self.stateValue
        state.stage = .failed(error.localizedDescription)
        self.finish(state)
        self.server?.stop()
        self.server = nil
    }

    // End of a run: release the screen. The server stays up after a successful
    // send in case iOS asks for the IPA again.
    private func finish(_ state: State) {
        self.hintTimer?.cancel()
        self.hintTimer = nil
        self.releaseAwake()
        self.setState(state)
    }

    private func releaseAwake() {
        if let awake = self.keepAwake {
            self.keepAwake = nil
            DispatchQueue.main.async {
                awake.dispose()
            }
        }
    }

    private func cleanUp() {
        self.downloadTask?.cancel()
        self.downloadTask = nil
        self.session?.invalidateAndCancel()
        self.session = nil
        self.server?.stop()
        self.server = nil
        try? FileManager.default.removeItem(at: self.workDirectory)
    }

    enum UpdateError: LocalizedError {
        case notConfigured
        case badArchive
        case signing(String)
        case packing
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Выберите сертификат и профиль в «Автообновлении»."
            case .badArchive: return "Скачанный файл — не IPA Shadow."
            case let .signing(reason): return "Подпись: \(reason)"
            case .packing: return "Не удалось упаковать подписанный IPA."
            case let .http(status): return "Сервер вернул \(status) при загрузке IPA."
            }
        }
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    var progress: ((Int64, Int64) -> Void)?
    var completion: ((Error?) -> Void)?
    var destination: URL?
    private var movedError: Error?
    private var didMove = false
    private var lastPermille: Int64 = -1

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        // Called for every packet; the list only needs 0.1% steps.
        let total = max(totalBytesExpectedToWrite, 0)
        let permille = total > 0 ? totalBytesWritten * 1000 / total : totalBytesWritten / (1024 * 1024)
        if permille != self.lastPermille {
            self.lastPermille = permille
            self.progress?(totalBytesWritten, total)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let response = downloadTask.response as? HTTPURLResponse, !(200 ..< 300).contains(response.statusCode) {
            self.movedError = ShadowSelfUpdater.UpdateError.http(response.statusCode)
            return
        }
        guard let destination = self.destination else {
            return
        }
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            self.didMove = true
        } catch {
            self.movedError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            self.completion?(error)
        } else if let movedError = self.movedError {
            self.completion?(movedError)
        } else if !self.didMove {
            self.completion?(ShadowSelfUpdater.UpdateError.badArchive)
        } else {
            self.completion?(nil)
        }
    }
}

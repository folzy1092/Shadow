import Foundation
import UIKit
import SwiftSignalKit
import Zsign
import ZipArchive

// Shadow: "Обновить" in the Shadow hub. Downloads the announced IPA, makes it
// look like the installed copy (ShadowBundlePreparer), signs it on the device
// with the pair from "Автообновление" (zsign), packs it and offers it to iOS
// through itms-services. iOS then replaces this app; the data container stays
// because the bundle id and the team do not change.
//
// The install follows IPA Hub (Feather) "Semi Local": the IPA on
// http://127.0.0.1 (no DNS, no local TLS), the manifest from api.palera.in and
// a Safari page that hands the link to iOS. The backloop.dev HTTPS route of
// 1.4.0 stopped working: its certificate was revoked on 2026-07-31; it is only
// tried while the system still trusts it and api.palera.in does not answer.
// What the install saw is in State.diagnostics.
//
// One run at a time, shared by every screen (leaving the hub does not stop it).
public final class ShadowSelfUpdater: NSObject {
    public static let shared = ShadowSelfUpdater()

    // How long iOS has to start the download after the link before the
    // cause is shown.
    static let hintDelay: TimeInterval = 10.0

    // How the app shows the install link; all run on the main thread.
    public struct InstallOpener {
        // UIApplication.open with its completion.
        public let openURL: (URL, @escaping (Bool) -> Void) -> Void
        // SFSafariViewController with the /install page; hidePage closes it.
        public let showPage: (URL) -> Void
        public let hidePage: () -> Void

        public init(openURL: @escaping (URL, @escaping (Bool) -> Void) -> Void, showPage: @escaping (URL) -> Void, hidePage: @escaping () -> Void) {
            self.openURL = openURL
            self.showPage = showPage
            self.hidePage = hidePage
        }
    }

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
        // What the install saw, from the server start on.
        public var diagnostics: ShadowInstallDiagnostics?

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
    private var opener: InstallOpener?
    private var installItem: ShadowInstallServer.Item?
    // The backloop pack, kept only while the system trusts its certificate.
    private var trustedMaterial: ShadowLocalTLSIdentity.Material?
    // api.palera.in failed before the certificate check finished.
    private var awaitingCertificate = false
    // The itms-services link of the running server and its Safari page.
    private var installLink: URL?
    private var installPage: URL?
    // The link was shown in this run: resigning active means the window came.
    private var didOpen = false

    override init() {
        super.init()
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: nil, using: { [weak self] _ in
            self?.queue.async {
                self?.appWillResignActive()
            }
        })
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil, using: { [weak self] _ in
            self?.queue.async {
                self?.appDidBecomeActive()
            }
        })
    }

    public var state: Signal<State, NoError> {
        return self.statePromise.get()
    }

    public var currentState: State {
        return self.queue.sync { self.stateValue }
    }

    public var workDirectory: URL {
        return FileManager.default.temporaryDirectory.appendingPathComponent("ShadowUpdate", isDirectory: true)
    }

    // opener shows the itms-services link; keepAwake holds the screen on (and
    // the app running) while the update is prepared and sent.
    // Call on the main thread.
    public func start(ipaURL: URL, build: Int, version: String?, opener: InstallOpener, keepAwake: @escaping () -> Disposable) {
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
            self.cleanUp()
            self.opener = opener
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
            self.setState(state)
            self.beginInstall(item: item, runId: runId)
        }
    }

    // MARK: - Install

    private func beginInstall(item: ShadowInstallServer.Item, runId: Int) {
        self.installItem = item
        self.trustedMaterial = nil
        self.awaitingCertificate = false
        var state = self.stateValue
        state.stage = .startingServer
        state.diagnostics = ShadowInstallDiagnostics()
        self.setState(state)

        // For the diagnostics: the local route does not look the host up.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = ShadowInstallLinks.resolve(host: ShadowLocalTLSIdentity.host)
            self?.queue.async {
                guard let self, self.runId == runId else {
                    return
                }
                self.updateDiagnostics { diagnostics in
                    diagnostics.resolved = result.error == nil ? result.addresses : nil
                    diagnostics.resolveError = result.error
                }
            }
        }
        self.checkBackloopCertificate(runId: runId)
        self.startServer(route: .localHTTP, opener: .safariPage, runId: runId)
    }

    // The backloop pack: its expiry for the diagnostics and, while the system
    // still trusts it, the fallback when api.palera.in does not answer.
    private func checkBackloopCertificate(runId: Int) {
        ShadowLocalTLSIdentity.load { [weak self] result in
            switch result {
            case let .failure(error):
                self?.queue.async {
                    guard let self, self.runId == runId else {
                        return
                    }
                    self.updateDiagnostics { diagnostics in
                        diagnostics.certificate = .failed(ShadowLocalTLSIdentity.shortText(error))
                    }
                    self.certificateChecked(runId: runId)
                }
            case let .success(material):
                // The trust evaluation may go to the network (revocation).
                DispatchQueue.global(qos: .utility).async {
                    let problem = ShadowLocalTLSIdentity.trustProblem(chain: material.chain)
                    self?.queue.async {
                        guard let self, self.runId == runId else {
                            return
                        }
                        self.trustedMaterial = problem == nil ? material : nil
                        self.updateDiagnostics { diagnostics in
                            diagnostics.certificate = problem.map { .failed($0) } ?? .ok
                            diagnostics.certificateNotAfter = material.notAfter
                        }
                        self.certificateChecked(runId: runId)
                    }
                }
            }
        }
    }

    private func certificateChecked(runId: Int) {
        if self.awaitingCertificate {
            self.awaitingCertificate = false
            self.fallBackFromExternalManifest(runId: runId)
        }
    }

    // A new server (and port) for route; the links come when it is ready.
    private func startServer(route: ShadowInstallServer.Route, opener: ShadowInstallDiagnostics.Opener, runId: Int) {
        guard let item = self.installItem else {
            return
        }
        self.hintTimer?.cancel()
        self.hintTimer = nil
        self.awaitingCertificate = false
        self.server?.stop()
        let server = ShadowInstallServer(item: item, route: route)
        self.server = server
        self.installLink = nil
        self.installPage = nil
        var state = self.stateValue
        state.stage = .startingServer
        state.diagnostics?.route = route.isLocalHTTP ? .localHTTP : .backloopHTTPS
        state.diagnostics?.opener = route.isLocalHTTP ? opener : .openURL
        state.diagnostics?.server = ShadowInstallActivity()
        state.diagnostics?.openResult = nil
        state.diagnostics?.promptSeen = false
        if route.isLocalHTTP {
            state.diagnostics?.externalManifest = .pending
        }
        self.setState(state)

        server.onActivity = { [weak self, weak server] activity in
            self?.queue.async {
                guard let self, let server, self.isCurrent(server, runId: runId) else {
                    return
                }
                self.updateDiagnostics { diagnostics in
                    diagnostics.server = activity
                }
            }
        }
        server.onPayloadRequested = { [weak self, weak server] in
            self?.queue.async {
                guard let self, let server, self.isCurrent(server, runId: runId) else {
                    return
                }
                // The user confirmed: iOS is downloading the IPA.
                self.hintTimer?.cancel()
                self.hintTimer = nil
                self.hidePage()
                if case .waitingForConfirmation = self.stateValue.stage {
                    self.setState(stage: .sending(sent: 0, total: 0))
                }
            }
        }
        server.onPayloadProgress = { [weak self, weak server] sent, total in
            self?.queue.async {
                guard let self, let server, self.isCurrent(server, runId: runId), case let .sending(previous, _) = self.stateValue.stage else {
                    return
                }
                // Percent steps are enough for the list.
                if total > 0, previous > 0, sent * 100 / total == previous * 100 / total, sent < total {
                    return
                }
                self.setState(stage: .sending(sent: sent, total: total))
            }
        }
        server.onPayloadFinished = { [weak self, weak server] in
            self?.queue.async {
                guard let self, let server, self.isCurrent(server, runId: runId) else {
                    return
                }
                self.hidePage()
                var state = self.stateValue
                state.stage = .installing
                self.finish(state)
            }
        }
        server.start { [weak self, weak server] result in
            self?.queue.async {
                guard let self, let server, self.isCurrent(server, runId: runId) else {
                    return
                }
                switch result {
                case let .failure(error):
                    self.fail(error)
                case let .success(port):
                    self.serverReady(server, port: port, runId: runId)
                }
            }
        }
    }

    private func isCurrent(_ server: ShadowInstallServer, runId: Int) -> Bool {
        return self.runId == runId && self.server === server
    }

    private func serverReady(_ server: ShadowInstallServer, port: UInt16, runId: Int) {
        switch server.route {
        case .localHTTP:
            let payload = ShadowInstallLinks.payloadURL(port: port)
            guard let item = self.installItem,
                  let manifest = ShadowInstallLinks.externalManifestURL(bundleId: item.bundleId, bundleVersion: item.bundleVersion, title: item.title, payload: payload),
                  let link = ShadowInstallLinks.itmsURL(manifest: manifest) else {
                self.updateDiagnostics { diagnostics in
                    diagnostics.externalManifest = .failed("bundle id")
                }
                self.fallBackFromExternalManifest(runId: runId)
                return
            }
            self.installLink = link
            self.installPage = ShadowInstallLinks.pageURL(port: port)
            server.setPageTarget(link)
            self.checkExternalManifest(manifest, payload: payload, server: server, runId: runId)
        case .backloopHTTPS:
            guard let manifest = ShadowInstallLinks.backloopManifestURL(host: ShadowLocalTLSIdentity.host, port: port),
                  let link = ShadowInstallLinks.itmsURL(manifest: manifest) else {
                self.fail(UpdateError.installLink)
                return
            }
            self.installLink = link
            server.setPageTarget(link)
            self.present(runId: runId)
        }
    }

    // iOS gets the manifest from api.palera.in itself; the app asks first so
    // that a dead service or a blocking VPN shows up as the cause.
    private func checkExternalManifest(_ manifest: URL, payload: URL, server: ShadowInstallServer, runId: Int) {
        let request = URLRequest(url: manifest, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8.0)
        URLSession.shared.dataTask(with: request, completionHandler: { [weak self, weak server] data, response, error in
            let problem = ShadowInstallLinks.externalManifestProblem(data: data, response: response, error: error, payload: payload)
            self?.queue.async {
                guard let self, let server, self.isCurrent(server, runId: runId) else {
                    return
                }
                if let problem {
                    self.updateDiagnostics { diagnostics in
                        diagnostics.externalManifest = .failed(problem)
                    }
                    self.fallBackFromExternalManifest(runId: runId)
                } else {
                    self.updateDiagnostics { diagnostics in
                        diagnostics.externalManifest = .ok
                    }
                    self.present(runId: runId)
                }
            }
        }).resume()
    }

    // No manifest from api.palera.in: the backloop route if its certificate
    // is still trusted, else the local link anyway (iOS may still get it).
    private func fallBackFromExternalManifest(runId: Int) {
        guard let diagnostics = self.stateValue.diagnostics else {
            return
        }
        if case .pending = diagnostics.certificate {
            self.awaitingCertificate = true
            return
        }
        if let material = self.trustedMaterial {
            self.startServer(route: .backloopHTTPS(material), opener: .openURL, runId: runId)
        } else if self.installLink != nil {
            self.present(runId: runId)
        } else {
            self.fail(UpdateError.installLink)
        }
    }

    // Shows the install link: the Safari page or UIApplication.open.
    private func present(runId: Int) {
        guard let link = self.installLink, let opener = self.opener else {
            return
        }
        var state = self.stateValue
        state.stage = .waitingForConfirmation(hint: false)
        state.diagnostics?.openResult = nil
        state.diagnostics?.promptSeen = false
        self.setState(state)
        self.didOpen = true
        self.armHint(runId: runId)
        let page = self.installPage
        let mode = state.diagnostics?.opener ?? .openURL
        DispatchQueue.main.async { [weak self] in
            switch mode {
            case .safariPage:
                if let page {
                    opener.showPage(page)
                }
            case .openURL:
                opener.hidePage()
                opener.openURL(link) { opened in
                    self?.queue.async {
                        guard let self, self.runId == runId else {
                            return
                        }
                        self.updateDiagnostics { diagnostics in
                            diagnostics.openResult = opened
                        }
                    }
                }
            }
        }
    }

    // If iOS has not started the download hintDelay after the link, the
    // cause is shown under the status.
    private func armHint(runId: Int) {
        self.hintTimer?.cancel()
        let hint = DispatchWorkItem { [weak self] in
            guard let self, self.runId == runId, case .waitingForConfirmation(hint: false) = self.stateValue.stage else {
                return
            }
            self.hintTimer = nil
            if let server = self.server {
                let activity = server.snapshot()
                self.updateDiagnostics { diagnostics in
                    diagnostics.server = activity
                }
                if activity.payloadRequested {
                    return
                }
            }
            // The page did not lead anywhere: the cause and the buttons are
            // under it. Leaving the app from here (to change the VPN) is not
            // the install window.
            self.hidePage()
            self.didOpen = false
            self.setState(stage: .waitingForConfirmation(hint: true))
        }
        self.hintTimer = hint
        self.queue.asyncAfter(deadline: .now() + ShadowSelfUpdater.hintDelay, execute: hint)
    }

    // "Показать окно установки": the window was dismissed or never came.
    public func retryInstallPrompt() {
        self.queue.async {
            guard case .waitingForConfirmation = self.stateValue.stage, let server = self.server, let diagnostics = self.stateValue.diagnostics else {
                return
            }
            let runId = self.runId
            let activity = server.snapshot()
            self.updateDiagnostics { diagnostics in
                diagnostics.server = activity
            }
            guard activity.isReady else {
                // The listener stopped (Shadow was in the background or the
                // port was taken): a new server with a new port and links.
                self.startServer(route: server.route, opener: diagnostics.opener, runId: runId)
                return
            }
            // No window the last time: the other way of opening the link.
            if diagnostics.route == .localHTTP, !diagnostics.promptSeen {
                self.updateDiagnostics { diagnostics in
                    diagnostics.opener = diagnostics.opener == .safariPage ? .openURL : .safariPage
                }
            }
            self.present(runId: runId)
        }
    }

    // The system install window covers the app: it did appear. Only while
    // the link is fresh: once the hint is up, the user leaves on purpose.
    private func appWillResignActive() {
        guard case .waitingForConfirmation(hint: false) = self.stateValue.stage, self.didOpen else {
            return
        }
        self.hintTimer?.cancel()
        self.hintTimer = nil
        self.updateDiagnostics { diagnostics in
            diagnostics.promptSeen = true
        }
    }

    // Back from the window: "Установить" starts the download soon,
    // "Отмена" does not.
    private func appDidBecomeActive() {
        guard case .waitingForConfirmation(hint: false) = self.stateValue.stage, let diagnostics = self.stateValue.diagnostics, diagnostics.promptSeen, !diagnostics.server.payloadRequested else {
            return
        }
        self.armHint(runId: self.runId)
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
        self.hidePage()
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

    private func hidePage() {
        guard let opener = self.opener else {
            return
        }
        DispatchQueue.main.async {
            opener.hidePage()
        }
    }

    private func updateDiagnostics(_ update: (inout ShadowInstallDiagnostics) -> Void) {
        guard var diagnostics = self.stateValue.diagnostics else {
            return
        }
        update(&diagnostics)
        var state = self.stateValue
        state.diagnostics = diagnostics
        self.setState(state)
    }

    private func cleanUp() {
        self.downloadTask?.cancel()
        self.downloadTask = nil
        self.session?.invalidateAndCancel()
        self.session = nil
        self.server?.stop()
        self.server = nil
        self.hidePage()
        self.opener = nil
        self.installItem = nil
        self.trustedMaterial = nil
        self.awaitingCertificate = false
        self.installLink = nil
        self.installPage = nil
        self.didOpen = false
        try? FileManager.default.removeItem(at: self.workDirectory)
    }

    enum UpdateError: LocalizedError {
        case notConfigured
        case badArchive
        case signing(String)
        case packing
        case http(Int)
        case installLink

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Выберите сертификат и профиль в «Автообновлении»."
            case .badArchive: return "Скачанный файл — не IPA Shadow."
            case let .signing(reason): return "Подпись: \(reason)"
            case .packing: return "Не удалось упаковать подписанный IPA."
            case let .http(status): return "Сервер вернул \(status) при загрузке IPA."
            case .installLink: return "Не удалось составить ссылку установки. Поделитесь подписанным IPA и установите его через ESign."
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

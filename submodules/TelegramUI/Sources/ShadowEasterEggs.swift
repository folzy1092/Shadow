import Foundation
import UIKit
import AVFoundation
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext

// Shadow: easter eggs, like AyuGram's tg://ayu/<name>.
//
// shadow://<name> (not a known quick-link command) looks for a post with a
// video or a GIF whose caption is shadow://<name> or tg://ayu/<name>, in the
// public channels of ShadowDeviceAccess easter_egg_channels, in order. The
// video plays full screen and cannot be closed while it plays; at the end it
// fades out by itself. The channel itself is never opened.
enum ShadowEasterEggs {
    // name → message, for this run of the app.
    private static var found: [String: Message] = [:]
    private static var isPlaying = false
    // Keeps the player (and its window) alive until it closes.
    private static var current: ShadowEasterEggPlayer?

    static func normalizedName(_ name: String) -> String? {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_-")
        guard !value.isEmpty, value.count <= 64, value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return nil
        }
        return value
    }

    // The caption names this egg: its first token is one of the egg links.
    static func captionMatches(_ text: String, name: String) -> Bool {
        let firstToken = text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).first.map { String($0).lowercased() } ?? ""
        let trimmed = firstToken.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:()[]{}«»\"'"))
        return trimmed == "shadow://\(name)" || trimmed == "tg://ayu/\(name)" || trimmed == "shadow://egg/\(name)" || trimmed == "tg://shadow/\(name)"
    }

    private static func videoFile(_ message: Message) -> TelegramMediaFile? {
        for media in message.media {
            if let file = media as? TelegramMediaFile, file.isVideo || file.isAnimated || file.mimeType.hasPrefix("video/") {
                return file
            }
        }
        return nil
    }

    private static func videoCodec(_ file: TelegramMediaFile) -> String? {
        for attribute in file.attributes {
            if case let .Video(_, _, _, _, _, videoCodec) = attribute {
                return videoCodec?.lowercased()
            }
        }
        return nil
    }

    // AVPlayer plays H.264/HEVC; channel videos may come as AV1 with the other
    // codecs among alternativeRepresentations (relax: a black screen, no sound).
    static func isPlayableCodec(_ codec: String?) -> Bool {
        guard let codec else {
            return true
        }
        return ["h264", "avc", "avc1", "h265", "hevc", "hvc1", "hev1"].contains(codec)
    }

    // The main file when AVPlayer can play it, else the largest playable
    // alternative representation.
    static func playableFile(_ file: TelegramMediaFile) -> TelegramMediaFile {
        if isPlayableCodec(videoCodec(file)) {
            return file
        }
        let alternatives = file.alternativeRepresentations.filter { isPlayableCodec(videoCodec($0)) }
        return alternatives.max(by: { ($0.size ?? 0) < ($1.size ?? 0) }) ?? file
    }

    // "h264 · video/mp4 · 527 КБ" (+ how many alternatives the post has).
    static func fileDescription(_ file: TelegramMediaFile) -> String {
        var parts: [String] = [videoCodec(file) ?? "кодек ?", file.mimeType]
        if let size = file.size {
            parts.append("\(size / 1024) КБ")
        }
        if !file.alternativeRepresentations.isEmpty {
            parts.append("вариантов: \(file.alternativeRepresentations.count)")
        }
        return parts.joined(separator: " · ")
    }

    private static func search(context: AccountContext, channel: String, name: String) -> Signal<Message?, NoError> {
        return context.engine.peers.resolvePeerByName(name: channel, referrer: nil)
        |> mapToSignal { result -> Signal<EnginePeer?, NoError> in
            if case let .result(peer) = result {
                return .single(peer)
            }
            return .complete()
        }
        |> take(1)
        |> mapToSignal { peer -> Signal<Message?, NoError> in
            guard let peer, case .channel = peer else {
                return .single(nil)
            }
            return context.engine.messages.searchMessages(location: .peer(peerId: peer.id, fromId: nil, tags: nil, reactions: nil, threadId: nil, minDate: nil, maxDate: nil), query: name, state: nil, limit: 50)
            |> take(1)
            |> map { result, _ -> Message? in
                return result.messages.first(where: { captionMatches($0.text, name: name) && videoFile($0) != nil })
            }
        }
    }

    // Searches the channels one by one; nil when no channel has the egg.
    private static func find(context: AccountContext, name: String) -> Signal<Message?, NoError> {
        if let message = found[name] {
            return .single(message)
        }
        let channels = (ShadowDeviceAccess.cachedWhitelist?.easterEggChannels ?? ShadowDeviceAccess.defaultEasterEggChannels)
        var signal: Signal<Message?, NoError> = .single(nil)
        for channel in channels {
            signal = signal |> mapToSignal { message -> Signal<Message?, NoError> in
                if let message {
                    return .single(message)
                }
                return search(context: context, channel: channel, name: name)
            }
        }
        return signal
        |> timeout(15.0, queue: .mainQueue(), alternate: .single(nil))
        |> deliverOnMainQueue
        |> map { message -> Message? in
            if let message {
                found[name] = message
            }
            return message
        }
    }

    // `notFound` runs when the name is not an egg (the caller opens Shadow settings).
    static func open(context: AccountContext, name rawName: String, notFound: @escaping () -> Void) {
        guard let name = normalizedName(rawName) else {
            notFound()
            return
        }
        if isPlaying {
            return
        }
        isPlaying = true
        let windowScene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first(where: { $0.activationState == .foregroundActive })
        let player = ShadowEasterEggPlayer(windowScene: windowScene, finished: {
            isPlaying = false
            current = nil
        })
        current = player
        player.showLoading()
        let _ = (find(context: context, name: name)
        |> deliverOnMainQueue).startStandalone(next: { message in
            guard let message, let mainFile = videoFile(message) else {
                player.close(animated: false)
                notFound()
                return
            }
            let file = playableFile(mainFile)
            let fileInfo = fileDescription(file)
            let postbox = context.account.postbox
            let reference = AnyMediaReference.message(message: MessageReference(message), media: file)
            let data = Signal<MediaResourceData, NoError> { subscriber in
                let fetch = fetchedMediaResource(mediaBox: postbox.mediaBox, userLocation: .peer(message.id.peerId), userContentType: MediaResourceUserContentType(file: file), reference: reference.resourceReference(file.resource)).start()
                let data = postbox.mediaBox.resourceData(file.resource, option: .complete(waitUntilFetchStatus: false)).start(next: { next in
                    if next.complete {
                        subscriber.putNext(next)
                        subscriber.putCompletion()
                    }
                })
                return ActionDisposable {
                    fetch.dispose()
                    data.dispose()
                }
            }
            player.loadDisposable.set((data
            |> take(1)
            |> timeout(60.0, queue: .mainQueue(), alternate: .complete())
            |> deliverOnMainQueue).startStrict(next: { data in
                player.play(path: data.path, isAnimation: file.isAnimated, fileInfo: fileInfo)
            }, completed: {
                if !player.didStartPlaying {
                    player.fail("Видео не скачалось за 60 с.\n\(fileInfo)")
                }
            }))
        })
    }
}

// A window above everything: black backdrop, the video aspect-fit. While the
// video plays nothing closes it; before that a tap cancels the loading.
private final class ShadowEasterEggPlayer {
    private let window: UIWindow
    private let controller = ShadowEasterEggViewController()
    private let finished: () -> Void
    let loadDisposable = MetaDisposable()
    private(set) var didStartPlaying = false
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var failObserver: NSObjectProtocol?
    private var linkPath: String?
    private var closed = false
    private var statusObservation: NSKeyValueObservation?
    private var watchdog: Foundation.Timer?
    private var fileInfo = ""
    private var failed = false

    init(windowScene: UIWindowScene?, finished: @escaping () -> Void) {
        if let windowScene {
            self.window = UIWindow(windowScene: windowScene)
        } else {
            self.window = UIWindow(frame: UIScreen.main.bounds)
        }
        self.finished = finished
        self.window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 5.0)
        self.window.backgroundColor = .clear
        self.window.rootViewController = self.controller
        // Before the first frame (loading, or a video that will not play) a tap
        // closes it; once it really plays, nothing does.
        self.controller.cancelLoading = { [weak self] in
            guard let self, self.failed || !self.isActuallyPlaying else {
                return
            }
            self.close(animated: true)
        }
    }

    func showLoading() {
        self.window.isHidden = false
        self.controller.view.alpha = 0.0
        UIView.animate(withDuration: 0.2) {
            self.controller.view.alpha = 1.0
        }
        self.controller.setLoading(true)
    }

    private var isActuallyPlaying: Bool {
        guard let item = self.player?.currentItem else {
            return false
        }
        return item.status == .readyToPlay && item.currentTime().seconds > 0.05
    }

    func play(path: String, isAnimation: Bool, fileInfo: String) {
        guard !self.closed else {
            return
        }
        // AVPlayer needs a file extension: the media cache has none. A hard
        // link (or a copy) instead of a symlink: AVFoundation does not always
        // follow a symlink into the media cache.
        let linkPath = NSTemporaryDirectory() + "shadow-egg-\(Int64.random(in: 1 ... Int64.max)).mp4"
        do {
            try FileManager.default.linkItem(atPath: path, toPath: linkPath)
        } catch {
            do {
                try FileManager.default.copyItem(atPath: path, toPath: linkPath)
            } catch {
                self.fail("Не удалось подготовить файл: \(error.localizedDescription)\n\(fileInfo)")
                return
            }
        }
        self.linkPath = linkPath
        self.fileInfo = fileInfo

        let item = AVPlayerItem(url: URL(fileURLWithPath: linkPath))
        let player = AVPlayer(playerItem: item)
        player.isMuted = isAnimation
        self.player = player
        self.endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main, using: { [weak self] _ in
            self?.close(animated: true)
        })
        self.failObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main, using: { [weak self] notification in
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            self?.fail("Воспроизведение прервалось.\n" + ShadowEasterEggPlayer.describe(error))
        })
        // A file AVPlayer cannot open only flips the item to .failed (no
        // notification): without this the black window stayed forever.
        self.statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                switch item.status {
                case .failed:
                    self.fail("AVPlayer не открыл видео.\n" + ShadowEasterEggPlayer.describe(item.error))
                case .readyToPlay:
                    // Never longer than the video itself (plus a margin).
                    let duration = item.duration.seconds
                    let limit = duration.isFinite && duration > 0.0 ? duration + 3.0 : 60.0
                    self.restartWatchdog(after: limit)
                default:
                    break
                }
            }
        }
        // Not ready within 10 s: give up and say so.
        self.watchdog?.invalidate()
        self.watchdog = Foundation.Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false, block: { [weak self] _ in
            guard let self, !self.isActuallyPlaying else {
                return
            }
            self.fail("Видео не запустилось за 10 с.")
        })
        self.controller.setLoading(false)
        self.controller.attach(player: player)
        self.didStartPlaying = true
        player.play()
    }

    func close(animated: Bool) {
        if self.closed {
            return
        }
        self.closed = true
        self.loadDisposable.dispose()
        self.watchdog?.invalidate()
        self.watchdog = nil
        self.statusObservation?.invalidate()
        self.statusObservation = nil
        self.player?.pause()
        if let endObserver = self.endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        if let failObserver = self.failObserver {
            NotificationCenter.default.removeObserver(failObserver)
        }
        let cleanup: () -> Void = {
            self.window.isHidden = true
            self.window.rootViewController = nil
            self.player = nil
            if let linkPath = self.linkPath {
                try? FileManager.default.removeItem(atPath: linkPath)
            }
            self.finished()
        }
        if animated {
            UIView.animate(withDuration: 0.35, animations: {
                self.controller.view.alpha = 0.0
            }, completion: { _ in
                cleanup()
            })
        } else {
            cleanup()
        }
    }
}

extension ShadowEasterEggPlayer {
    // Shadow: a failed egg stays on screen with the reason (there is no other
    // log of it) until a tap or 10 s.
    func fail(_ reason: String) {
        guard !self.closed, !self.failed else {
            return
        }
        self.failed = true
        self.player?.pause()
        self.controller.setLoading(false)
        var text = "Пасхалка не воспроизвелась\n\n" + reason
        if !self.fileInfo.isEmpty, !reason.contains(self.fileInfo) {
            text += "\n" + self.fileInfo
        }
        self.controller.showMessage(text)
        self.restartWatchdog(after: 10.0)
    }

    static func describe(_ error: Error?) -> String {
        guard let error = error as NSError? else {
            return "Без текста ошибки."
        }
        var text = "\(error.domain) \(error.code): \(error.localizedDescription)"
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            text += "\n← \(underlying.domain) \(underlying.code)"
        }
        return text
    }

    fileprivate func restartWatchdog(after seconds: Double) {
        self.watchdog?.invalidate()
        self.watchdog = Foundation.Timer.scheduledTimer(withTimeInterval: seconds, repeats: false, block: { [weak self] _ in
            self?.close(animated: true)
        })
    }
}

private final class ShadowEasterEggViewController: UIViewController {
    var cancelLoading: (() -> Void)?
    private let playerLayer = AVPlayerLayer()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let messageLabel = UILabel()

    override var prefersStatusBarHidden: Bool {
        return true
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        return true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .black
        self.playerLayer.videoGravity = .resizeAspect
        self.view.layer.addSublayer(self.playerLayer)
        self.spinner.color = .white
        self.view.addSubview(self.spinner)
        self.messageLabel.textColor = UIColor(white: 1.0, alpha: 0.85)
        self.messageLabel.font = UIFont.systemFont(ofSize: 14.0)
        self.messageLabel.numberOfLines = 0
        self.messageLabel.textAlignment = .center
        self.messageLabel.isHidden = true
        self.view.addSubview(self.messageLabel)
        self.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.tapped)))
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.playerLayer.frame = self.view.bounds
        self.spinner.center = CGPoint(x: self.view.bounds.midX, y: self.view.bounds.midY)
        let width = self.view.bounds.width - 48.0
        let size = self.messageLabel.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        self.messageLabel.frame = CGRect(x: 24.0, y: floor((self.view.bounds.height - size.height) / 2.0), width: width, height: ceil(size.height))
    }

    func showMessage(_ text: String) {
        self.playerLayer.isHidden = true
        self.messageLabel.text = text + "\n\nНажмите, чтобы закрыть"
        self.messageLabel.isHidden = false
        self.view.setNeedsLayout()
    }

    func setLoading(_ loading: Bool) {
        if loading {
            self.spinner.startAnimating()
        } else {
            self.spinner.stopAnimating()
        }
    }

    func attach(player: AVPlayer) {
        self.playerLayer.player = player
    }

    @objc private func tapped() {
        self.cancelLoading?()
    }
}

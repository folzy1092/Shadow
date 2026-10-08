import Foundation
import UIKit
import WebKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import UndoUI

// Shadow: «Лента» (beta) tab. The page is ShadowFeedPage (WKWebView) written to
// a temporary folder; media download like in a chat (fetchedMediaResource) and
// are hard-linked next to the page with a proper extension, so <img>/<video>
// load them as files. Posts come from ShadowFeedCollect (only what is stored
// on the device). Tapping a post opens the channel over the tab bar, «назад»
// comes back to the feed.
final class ShadowFeedController: ViewController, WKScriptMessageHandler {
    private final class WeakHandler: NSObject, WKScriptMessageHandler {
        weak var target: WKScriptMessageHandler?

        init(_ target: WKScriptMessageHandler) {
            self.target = target
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            self.target?.userContentController(userContentController, didReceive: message)
        }
    }

    static let pageSize = 30
    // Bigger videos show only their poster; a tap opens the post.
    static let maxVideoSize: Int64 = 25 * 1024 * 1024

    private let context: AccountContext
    private var presentationData: PresentationData
    private var settings: AyuGramSettings
    private let folder: URL
    private var webView: WKWebView?
    private var isPageReady = false
    private var didInit = false

    private var channels: [ShadowFeedCollect.Channel] = []
    private var folders: [ShadowFeedCollect.Folder] = []
    private var chips: [ShadowFeed.Chip] = []
    private var selectedChip = "all"
    private var refs: [ShadowFeedCollect.Ref] = []
    private var cursor = 0
    private var refsById: [String: ShadowFeedCollect.Ref] = [:]
    private var postsById: [String: ShadowFeed.Post] = [:]
    private var mediaSources: [String: ShadowFeedCollect.MediaSource] = [:]
    private var readyMedia: [String: String] = [:]
    private var loadingMedia = Set<String>()

    private let mediaDisposables = DisposableDict<String>()
    private let loadDisposable = MetaDisposable()
    private let pageDisposable = MetaDisposable()
    private let refreshDisposable = MetaDisposable()
    private let actionDisposables = DisposableSet()
    private var settingsDisposable: Disposable?
    private var presentationDataDisposable: Disposable?
    private var refreshTimer: SwiftSignalKit.Timer?

    init(context: AccountContext) {
        self.context = context
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        self.settings = currentAyuGramSettings(accountId: context.account.id)
        self.folder = FileManager.default.temporaryDirectory.appendingPathComponent("shadow-feed-\(context.account.peerId.toInt64())", isDirectory: true)
        super.init(navigationBarPresentationData: nil)
        self.title = "Лента"
        self.tabBarItem.title = "Лента"
        self.updateTabIcon()

        self.settingsDisposable = (ayuGramSettings(postbox: context.account.postbox)
        |> deliverOnMainQueue).start(next: { [weak self] settings in
            guard let self else {
                return
            }
            let previous = self.settings
            self.settings = settings
            if previous.feedIncludeMuted != settings.feedIncludeMuted || previous.feedIncludeArchived != settings.feedIncludeArchived || previous.feedShowFolders != settings.feedShowFolders {
                self.reload()
            }
            if previous.feedAutoplay != settings.feedAutoplay || previous.feedMarkRead != settings.feedMarkRead {
                self.pushSettings()
            }
        })
        self.presentationDataDisposable = (context.sharedContext.presentationData
        |> deliverOnMainQueue).start(next: { [weak self] presentationData in
            guard let self else {
                return
            }
            let previousTheme = self.presentationData.theme
            self.presentationData = presentationData
            if previousTheme !== presentationData.theme {
                self.updateTabIcon()
                self.evaluate("document.documentElement.dataset.theme = \(self.jsonString(presentationData.theme.overallDarkAppearance ? "dark" : "light"))")
            }
        })
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.settingsDisposable?.dispose()
        self.presentationDataDisposable?.dispose()
        self.mediaDisposables.dispose()
        self.loadDisposable.dispose()
        self.pageDisposable.dispose()
        self.refreshDisposable.dispose()
        self.actionDisposables.dispose()
        self.refreshTimer?.invalidate()
        self.webView?.configuration.userContentController.removeScriptMessageHandler(forName: "shadow")
    }

    private func updateTabIcon() {
        let tabBar = self.presentationData.theme.rootController.tabBar
        self.tabBarItem.image = ShadowFeedController.tabIcon("newspaper", color: tabBar.iconColor)
        self.tabBarItem.selectedImage = ShadowFeedController.tabIcon("newspaper.fill", color: tabBar.selectedIconColor)
    }

    // The other tab icons are 30x30 canvases; the symbol is centred on one, so
    // it sits on the same line as them in the normal and the compact bar.
    static func tabIcon(_ name: String, color: UIColor) -> UIImage? {
        let configuration = UIImage.SymbolConfiguration(pointSize: 19.0, weight: .medium)
        guard let symbol = UIImage(systemName: name, withConfiguration: configuration)?.withTintColor(color, renderingMode: .alwaysOriginal) else {
            return nil
        }
        let size = CGSize(width: 30.0, height: 30.0)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let rect = CGRect(x: floor((size.width - symbol.size.width) / 2.0), y: floor((size.height - symbol.size.height) / 2.0), width: symbol.size.width, height: symbol.size.height)
            symbol.draw(in: rect)
        }
    }

    // MARK: - Page

    override func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNode.backgroundColor = self.presentationData.theme.list.plainBackgroundColor
        self.displayNodeDidLoad()

        try? FileManager.default.removeItem(at: self.folder)
        try? FileManager.default.createDirectory(at: self.folder, withIntermediateDirectories: true, attributes: nil)
        let index = self.folder.appendingPathComponent("index.html")
        try? ShadowFeedPage.html.write(to: index, atomically: true, encoding: .utf8)

        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.add(WeakHandler(self), name: "shadow")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        self.displayNode.view.addSubview(webView)
        self.webView = webView
        webView.loadFileURL(index, allowingReadAccessTo: self.folder)
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        // Below the status bar: «Прочитать всё» and «⋯» must not sit under it.
        let top = layout.statusBarHeight ?? layout.safeInsets.top
        self.webView?.frame = CGRect(x: 0.0, y: top, width: layout.size.width, height: max(0.0, layout.size.height - top))
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.refreshTimer?.invalidate()
        let timer = SwiftSignalKit.Timer(timeout: 45.0, repeat: true, completion: { [weak self] in
            self?.refreshTop()
        }, queue: Queue.mainQueue())
        self.refreshTimer = timer
        timer.start()
        self.refreshTop()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        self.refreshTimer?.invalidate()
        self.refreshTimer = nil
    }

    private func evaluate(_ script: String) {
        guard self.isPageReady else {
            return
        }
        self.webView?.evaluateJavaScript(script, completionHandler: nil)
    }

    private func jsonString(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value], options: []), let string = String(data: data, encoding: .utf8) else {
            return "null"
        }
        return String(string.dropFirst().dropLast())
    }

    private func encoded<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value), let string = String(data: data, encoding: .utf8) else {
            return "null"
        }
        return string
    }

    private var accountPeerId: Int64 {
        return self.context.account.peerId.toInt64()
    }

    private func pageSettings() -> [String: Any] {
        return [
            "autoplay": self.settings.feedAutoplay,
            "feedIncludeMuted": self.settings.feedIncludeMuted,
            "feedIncludeArchived": self.settings.feedIncludeArchived,
            "feedShowFolders": self.settings.feedShowFolders,
            "feedMarkRead": self.settings.feedMarkRead
        ]
    }

    private func pushSettings() {
        self.evaluate("Feed.setConfig(\(self.jsonString(["settings": self.pageSettings()])))")
    }

    // MARK: - Chips and posts

    private func visibleChannels() -> [ShadowFeedCollect.Channel] {
        let hidden = ShadowFeedStore.shared.hiddenChannels(accountPeerId: self.accountPeerId)
        return self.channels.filter { channel in
            if hidden.contains(channel.peerId.toInt64()) {
                return false
            }
            if channel.isMuted && !self.settings.feedIncludeMuted {
                return false
            }
            return true
        }
    }

    private func buildChips() {
        var chips: [ShadowFeed.Chip] = [ShadowFeed.Chip(id: "all", title: "Все", peerIds: nil), ShadowFeed.Chip(id: "unread", title: "Непрочитанные", peerIds: nil)]
        if self.settings.feedShowFolders {
            for folder in self.folders {
                chips.append(ShadowFeed.Chip(id: "folder:\(folder.id)", title: folder.title, peerIds: folder.peerIds.map { $0.toInt64() }))
            }
        }
        for collection in ShadowFeedStore.shared.collections(accountPeerId: self.accountPeerId) {
            chips.append(ShadowFeed.Chip(id: "col:\(collection.id)", title: collection.title, peerIds: collection.peerIds))
        }
        self.chips = ShadowFeedStore.orderedChips(chips, order: ShadowFeedStore.shared.order(accountPeerId: self.accountPeerId))
        if !self.chips.contains(where: { $0.id == self.selectedChip }) {
            self.selectedChip = "all"
        }
    }

    private func chipPeerIds() -> [PeerId] {
        let visible = self.visibleChannels()
        guard let chip = self.chips.first(where: { $0.id == self.selectedChip }), let peerIds = chip.peerIds else {
            return visible.map { $0.peerId }
        }
        let wanted = Set(peerIds)
        return visible.filter { wanted.contains($0.peerId.toInt64()) }.map { $0.peerId }
    }

    private func reload() {
        guard self.isPageReady else {
            return
        }
        self.loadDisposable.set((ShadowFeedCollect.channels(account: self.context.account, includeArchived: self.settings.feedIncludeArchived)
        |> deliverOnMainQueue).start(next: { [weak self] channels, folders in
            guard let self else {
                return
            }
            self.channels = channels
            self.folders = folders
            self.buildChips()
            let config: [String: Any] = [
                "theme": self.presentationData.theme.overallDarkAppearance ? "dark" : "light",
                "chips": self.chips.map { ["id": $0.id, "title": $0.title] },
                "selected": self.selectedChip,
                "lastSeen": Int(ShadowFeedStore.shared.lastSeen(accountPeerId: self.accountPeerId)),
                "settings": self.pageSettings(),
                "channels": channels.map { ["id": $0.peerId.toInt64(), "title": $0.title] },
                "collections": ShadowFeedStore.shared.collections(accountPeerId: self.accountPeerId).map { ["id": $0.id, "title": $0.title, "peerIds": $0.peerIds] }
            ]
            if self.didInit {
                self.evaluate("Feed.setConfig(\(self.jsonString(config)))")
                self.evaluate("Feed.setChips(\(self.jsonString(config["chips"]!)), \(self.jsonString(self.selectedChip)), 0)")
            } else {
                self.didInit = true
                self.evaluate("Feed.init(\(self.jsonString(config)))")
            }
            self.loadChip()
            self.updateUnreadCount()
        }))
    }

    private func updateUnreadCount() {
        let peerIds = self.visibleChannels().map { $0.peerId }
        self.refreshDisposable.set((ShadowFeedCollect.index(account: self.context.account, peerIds: peerIds, unreadOnly: true, settings: self.settings)
        |> deliverOnMainQueue).start(next: { [weak self] refs in
            guard let self else {
                return
            }
            self.evaluate("Feed.setChips(\(self.jsonString(self.chips.map { ["id": $0.id, "title": $0.title] })), \(self.jsonString(self.selectedChip)), \(refs.count))")
        }))
    }

    private func loadChip() {
        let unreadOnly = self.selectedChip == "unread"
        self.pageDisposable.set((ShadowFeedCollect.index(account: self.context.account, peerIds: self.chipPeerIds(), unreadOnly: unreadOnly, settings: self.settings)
        |> deliverOnMainQueue).start(next: { [weak self] refs in
            guard let self else {
                return
            }
            self.refs = refs
            self.cursor = 0
            for ref in refs {
                self.refsById[ref.postId] = ref
            }
            self.loadPage(replace: true)
        }))
    }

    private func loadPage(replace: Bool) {
        let slice = Array(self.refs[min(self.cursor, self.refs.count) ..< min(self.cursor + ShadowFeedController.pageSize, self.refs.count)])
        self.cursor += slice.count
        let hasMore = self.cursor < self.refs.count
        self.pageDisposable.set((ShadowFeedCollect.posts(account: self.context.account, refs: slice)
        |> deliverOnMainQueue).start(next: { [weak self] page in
            guard let self else {
                return
            }
            self.absorb(page)
            let posts = self.encoded(page.posts)
            if replace {
                self.evaluate("Feed.setPosts(\(posts), \(hasMore))")
            } else {
                self.evaluate("Feed.appendPosts(\(posts), \(hasMore))")
            }
        }))
    }

    private func absorb(_ page: ShadowFeedCollect.Page) {
        for post in page.posts {
            self.postsById[post.id] = post
        }
        for (key, source) in page.media {
            self.mediaSources[key] = source
        }
    }

    // New posts at the top: shown right away at the top, else a «N новых» pill.
    private func refreshTop() {
        guard self.isPageReady, self.didInit, self.selectedChip != "unread" else {
            return
        }
        let newest = self.refs.first?.timestamp ?? 0
        let known = Set(self.refsById.keys)
        let account = self.context.account
        self.refreshDisposable.set((ShadowFeedCollect.index(account: account, peerIds: self.chipPeerIds(), unreadOnly: false, settings: self.settings)
        |> mapToSignal { refs -> Signal<([ShadowFeedCollect.Ref], ShadowFeedCollect.Page?), NoError> in
            let fresh = refs.filter { $0.timestamp > newest && !known.contains($0.postId) }
            if fresh.isEmpty {
                return .single((refs, nil))
            }
            return ShadowFeedCollect.posts(account: account, refs: fresh)
            |> map { page -> ([ShadowFeedCollect.Ref], ShadowFeedCollect.Page?) in
                return (fresh, page)
            }
        }
        |> deliverOnMainQueue).start(next: { [weak self] fresh, page in
            guard let self, let page else {
                return
            }
            for ref in fresh {
                self.refsById[ref.postId] = ref
            }
            self.refs = fresh + self.refs
            self.cursor += fresh.count
            self.absorb(page)
            self.evaluate("Feed.prependPosts(\(self.encoded(page.posts)))")
        }))
    }

    // MARK: - Media

    private func fileName(for key: String, fileExtension: String) -> String {
        let safe = key.map { $0.isLetter || $0.isNumber || $0 == "_" ? String($0) : "_" }.joined()
        return "\(safe).\(fileExtension)"
    }

    private func requestMedia(_ keys: [String]) {
        for key in keys {
            if let name = self.readyMedia[key] {
                self.evaluate("Feed.mediaReady(\(self.jsonString(key)), \(self.jsonString(name)))")
                continue
            }
            if self.loadingMedia.contains(key) {
                continue
            }
            guard let source = self.mediaSources[key] else {
                continue
            }
            if self.mediaSources[key + ":poster"] != nil {
                self.requestMedia([key + ":poster"])
            }
            switch source {
            case let .resource(reference, resource, peerId, kind, fileExtension, size):
                if (kind == "video" || kind == "gif"), let size, size > ShadowFeedController.maxVideoSize {
                    continue
                }
                self.loadingMedia.insert(key)
                let contentType: MediaResourceUserContentType = kind == "video" || kind == "gif" ? .video : (kind == "avatar" ? .avatar : .image)
                let mediaBox = self.context.account.postbox.mediaBox
                let fetch = fetchedMediaResource(mediaBox: mediaBox, userLocation: .peer(peerId), userContentType: contentType, reference: reference)
                let data = mediaBox.resourceData(resource)
                |> filter { $0.complete }
                |> take(1)
                let name = self.fileName(for: key, fileExtension: fileExtension)
                let destination = self.folder.appendingPathComponent(name)
                let combined: Signal<Bool, NoError> = Signal { subscriber in
                    let fetchDisposable = fetch.start()
                    let dataDisposable = data.start(next: { data in
                        try? FileManager.default.removeItem(at: destination)
                        do {
                            try FileManager.default.linkItem(atPath: data.path, toPath: destination.path)
                        } catch {
                            try? FileManager.default.copyItem(atPath: data.path, toPath: destination.path)
                        }
                        subscriber.putNext(FileManager.default.fileExists(atPath: destination.path))
                        subscriber.putCompletion()
                    })
                    return ActionDisposable {
                        fetchDisposable.dispose()
                        dataDisposable.dispose()
                    }
                }
                self.mediaDisposables.set((combined |> deliverOnMainQueue).start(next: { [weak self] success in
                    guard let self else {
                        return
                    }
                    self.loadingMedia.remove(key)
                    if success {
                        self.readyMedia[key] = name
                        self.evaluate("Feed.mediaReady(\(self.jsonString(key)), \(self.jsonString(name)))")
                    }
                }), forKey: key)
            }
        }
    }

    // MARK: - Actions

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let action = body["action"] as? String else {
            return
        }
        switch action {
        case "ready":
            self.isPageReady = true
            self.didInit = false
            self.reload()
        case "chip":
            if let id = body["id"] as? String {
                self.selectedChip = id
                self.loadChip()
            }
        case "more":
            self.loadPage(replace: false)
        case "need":
            if let keys = body["keys"] as? [String] {
                self.requestMedia(keys)
            }
        case "seen":
            if let ids = body["ids"] as? [String] {
                self.markSeen(ids)
            }
        case "open":
            if let id = body["id"] as? String {
                self.openPost(id)
            }
        case "comments":
            if let id = body["id"] as? String {
                self.openComments(id)
            }
        case "react":
            if let id = body["id"] as? String, let key = body["key"] as? String {
                self.react(id, key: key)
            }
        case "url":
            if let url = body["url"] as? String {
                self.openURL(url)
            }
        case "readAll":
            self.readAll()
        case "hideChannel":
            if let peerId = (body["peerId"] as? NSNumber)?.int64Value {
                ShadowFeedStore.shared.setChannelHidden(peerId, hidden: true, accountPeerId: self.accountPeerId)
                self.refs.removeAll(where: { $0.id.peerId.toInt64() == peerId })
                self.toast("Канал убран из ленты, подписка не меняется. Вернуть: Shadow → Лента → «Вернуть убранные каналы».")
            }
        case "saveCollection":
            if let collection = body["collection"] as? [String: Any], let id = collection["id"] as? String, let title = collection["title"] as? String, let peerIds = collection["peerIds"] as? [NSNumber] {
                ShadowFeedStore.shared.setCollection(ShadowFeedStore.Collection(id: id, title: title, peerIds: peerIds.map { $0.int64Value }), accountPeerId: self.accountPeerId)
                self.reload()
            }
        case "removeCollection":
            if let id = body["id"] as? String {
                ShadowFeedStore.shared.removeCollection(id: id, accountPeerId: self.accountPeerId)
                self.reload()
            }
        case "order":
            if let ids = body["ids"] as? [String] {
                ShadowFeedStore.shared.setOrder(ids, accountPeerId: self.accountPeerId)
                self.buildChips()
            }
        case "setting":
            if let key = body["key"] as? String, let value = body["value"] as? Bool {
                self.updateSetting(key, value)
            }
        case "copyLink":
            if let id = body["id"] as? String, let ref = self.refsById[id] {
                let _ = (ShadowFeedCollect.link(account: self.context.account, id: ref.id)
                |> deliverOnMainQueue).start(next: { [weak self] link in
                    guard let link else {
                        return
                    }
                    UIPasteboard.general.string = link
                    self?.toast("Ссылка скопирована")
                })
            }
        default:
            break
        }
    }

    private func updateSetting(_ key: String, _ value: Bool) {
        let _ = updateAyuGramSettings(postbox: self.context.account.postbox) { current in
            var current = current
            switch key {
            case "autoplay": current.feedAutoplay = value
            case "feedIncludeMuted": current.feedIncludeMuted = value
            case "feedIncludeArchived": current.feedIncludeArchived = value
            case "feedShowFolders": current.feedShowFolders = value
            case "feedMarkRead": current.feedMarkRead = value
            default: break
            }
            return current
        }.startStandalone()
    }

    private func markSeen(_ ids: [String]) {
        let refs = ids.compactMap { self.refsById[$0] }
        if let newest = refs.map({ $0.timestamp }).max() {
            ShadowFeedStore.shared.setLastSeen(newest, accountPeerId: self.accountPeerId)
        }
        guard self.settings.feedMarkRead, !refs.isEmpty else {
            return
        }
        self.actionDisposables.add(ShadowFeedCollect.markRead(account: self.context.account, ids: refs.map { $0.id }).start())
    }

    private func readAll() {
        let account = self.context.account
        self.actionDisposables.add((ShadowFeedCollect.topMessageIds(account: account, peerIds: self.chipPeerIds())
        |> mapToSignal { ids -> Signal<Void, NoError> in
            return ShadowFeedCollect.markRead(account: account, ids: ids)
        }
        |> deliverOnMainQueue).start(completed: { [weak self] in
            self?.updateUnreadCount()
        }))
    }

    private func openPost(_ id: String) {
        guard let ref = self.refsById[id] else {
            return
        }
        let context = self.context
        let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: ref.id.peerId))
        |> deliverOnMainQueue).start(next: { [weak self] peer in
            guard let self, let peer, let navigationController = self.navigationController as? NavigationController else {
                return
            }
            context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(peer), subject: .message(id: .id(ref.id), highlight: ChatControllerSubject.MessageHighlight(quote: nil), timecode: nil, setupReply: false), keepStack: .always))
        })
    }

    private func openComments(_ id: String) {
        guard let ref = self.refsById[id], let navigationController = self.navigationController as? NavigationController else {
            return
        }
        self.actionDisposables.add(ChatControllerImpl.openMessageReplies(context: self.context, navigationController: navigationController, present: { [weak self] controller, arguments in
            self?.present(controller, in: .window(.root), with: arguments)
        }, messageId: ref.id, isChannelPost: true, atMessage: nil, displayModalProgress: true).start())
    }

    private func react(_ id: String, key: String) {
        guard let ref = self.refsById[id], key != "stars" else {
            return
        }
        let mine = self.postsById[id]?.reactions.filter { $0.mine }.map { $0.key } ?? []
        var reactions: [UpdateMessageReaction] = []
        if !mine.contains(key) {
            if key.hasPrefix("custom:"), let fileId = Int64(key.dropFirst("custom:".count)) {
                reactions = [.custom(fileId: fileId, file: nil)]
            } else {
                reactions = [.builtin(key)]
            }
        }
        self.context.engine.messages.setMessageReactions(ids: [ref.id], reactions: reactions)
        // The new counts arrive with the update; rebuild the post shortly after.
        let account = self.context.account
        self.actionDisposables.add((Signal<Void, NoError>.single(Void()) |> delay(0.8, queue: Queue.mainQueue())
        |> mapToSignal { _ -> Signal<ShadowFeedCollect.Page, NoError> in
            return ShadowFeedCollect.posts(account: account, refs: [ref])
        }
        |> deliverOnMainQueue).start(next: { [weak self] page in
            guard let self, let post = page.posts.first else {
                return
            }
            self.absorb(page)
            self.evaluate("Feed.updateReactions(\(self.encoded(post)))")
        }))
    }

    private func openURL(_ url: String) {
        self.context.sharedContext.openExternalUrl(context: self.context, urlContext: .generic, url: url, forceExternal: false, presentationData: self.presentationData, navigationController: self.navigationController as? NavigationController, dismissInput: {})
    }

    private func toast(_ text: String) {
        self.present(UndoOverlayController(presentationData: self.presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), in: .current)
    }
}

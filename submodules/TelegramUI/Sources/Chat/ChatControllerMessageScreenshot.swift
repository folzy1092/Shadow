import Foundation
import UIKit
import AsyncDisplayKit
import Display
import AlertUI
import PresentationDataUtils
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import AccountContext
import AvatarNode
import LocalizedPeerData
import WallpaperBackgroundNode
import ChatMessageItemImpl
import ChatMessageDateAndStatusNode
import ChatMessageBubbleItemNode

extension ChatControllerImpl {
    func presentShadowMessageScreenshot() {
        guard !self.shadowScreenshotPreparing,
              let ids = self.presentationInterfaceState.interfaceState.selectionState?.selectedIds, !ids.isEmpty else { return }
        guard ids.count <= 100 else { self.shadowScreenshotError("Выбери не больше 100 сообщений."); return }
        self.shadowScreenshotPreparing = true
        let _ = (self.context.account.postbox.transaction { transaction -> (AyuGramSettings, [EngineRawMessage], EnginePeer?) in
            let messages = ids.compactMap { transaction.getMessage($0) }.sorted { $0.index < $1.index }
            let accountPeer = transaction.getPeer(self.context.account.peerId).map(EnginePeer.init)
            return (currentAyuGramSettings(transaction: transaction), messages, accountPeer)
        } |> deliverOnMainQueue).start(next: { [weak self] settings, messages, accountPeer in
            guard let self else { return }
            self.shadowScreenshotPreparing = false
            guard settings.messageScreenshot.enabled, self.viewIfLoaded?.window != nil else { return }
            guard messages.count == ids.count else { self.shadowScreenshotError("Часть сообщений больше недоступна. Выдели сообщения заново."); return }
            // The export must not open view-once media or bypass secret-chat protection.
            guard !messages.contains(where: { message in
                message.id.peerId.namespace == Namespaces.Peer.SecretChat || message.attributes.contains(where: { $0 is AutoremoveTimeoutMessageAttribute || $0 is AutoclearTimeoutMessageAttribute })
            }) else { self.shadowScreenshotError("Секретные и исчезающие сообщения не включаются в скриншот."); return }
            guard settings.allowSaveRestrictedContent || !messages.contains(where: { $0.isCopyProtected() || $0.peers[$0.id.peerId]?.isCopyProtectionEnabled == true }) else {
                self.shadowScreenshotError("В этом чате запрещено сохранение контента."); return
            }
            guard var presenter = self.view.window?.rootViewController else { return }
            while let next = presenter.presentedViewController { presenter = next }
            let state = self.presentationInterfaceState
            let data = ChatPresentationData(theme: ChatPresentationThemeData(theme: state.theme, wallpaper: state.chatWallpaper), fontSize: state.fontSize, strings: state.strings, dateTimeFormat: state.dateTimeFormat, nameDisplayOrder: state.nameDisplayOrder, disableAnimations: true, largeEmoji: false, chatBubbleCorners: state.bubbleCorners, shadowScreenshot: settings.messageScreenshot)
            let preview = ShadowMessageScreenshotPreview(context: self.context, accountPeer: accountPeer, messages: messages, data: data, options: settings.messageScreenshot)
            presenter.present(UINavigationController(rootViewController: preview), animated: true)
        })
    }

    private func shadowScreenshotError(_ text: String) {
        self.present(textAlertController(context: self.context, title: "Скриншот сообщений", text: text, actions: [TextAlertAction(type: .defaultAction, title: "ОК", action: {})]), in: .window(.root))
    }
}

// Isolated native message nodes. Never extracts live chat cells or scrolls history.
private final class ShadowMessageScreenshotPreview: UIViewController {
    private let context: AccountContext
    private let accountPeer: EnginePeer?
    private let messages: [EngineRawMessage]
    private let data: ChatPresentationData
    private let messageTheme: PresentationTheme
    private let options: ShadowMessageScreenshotSettings
    private let scrollView = UIScrollView()
    private let content = ASDisplayNode()
    private var background: WallpaperBackgroundNode?
    private var imageBackground: UIImageView?
    private var started = false
    private var ready = false
    private let width: CGFloat = 390.0
    private var contentHeight: CGFloat = 12.0

    init(context: AccountContext, accountPeer: EnginePeer?, messages: [EngineRawMessage], data: ChatPresentationData, options: ShadowMessageScreenshotSettings) {
        self.context = context
        self.accountPeer = accountPeer
        self.messages = messages
        self.data = data
        self.messageTheme = Self.desktopBubbleTheme(data.theme.theme)
        self.options = options
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // Desktop-style quotes keep their bubbles. Use one neutral bubble palette
    // for both directions without mutating the live chat's shared theme.
    private static func desktopBubbleTheme(_ theme: PresentationTheme) -> PresentationTheme {
        let colors = theme.chat.message.incoming.withUpdated(secondaryTextColor: UIColor(white: theme.overallDarkAppearance ? 0.65 : 0.4, alpha: 1.0))
        let result = PresentationTheme(name: theme.name, index: theme.index, referenceTheme: theme.referenceTheme, overallDarkAppearance: theme.overallDarkAppearance, intro: theme.intro, passcode: theme.passcode, rootController: theme.rootController, list: theme.list, chatList: theme.chatList, chat: theme.chat.withUpdated(message: theme.chat.message.withUpdated(incoming: colors, outgoing: colors)), actionSheet: theme.actionSheet, contextMenu: theme.contextMenu, inAppNotification: theme.inAppNotification, chart: theme.chart, preview: theme.preview)
        result.forceSync = true
        result.starGift = theme.starGift
        return result
    }

    private func author(of message: EngineRawMessage) -> EnginePeer? {
        if let author = message.author {
            return EnginePeer(author)
        }
        if let peer = message.peers[message.id.peerId] as? TelegramChannel, case .broadcast = peer.info {
            return EnginePeer(peer)
        }
        // Some outgoing records have no embedded author. Resolve the captured
        // account, never the currently active account after a possible switch.
        if !message.flags.contains(.Incoming) {
            return self.accountPeer
        }
        if let peer = message.peers[message.id.peerId] as? TelegramUser {
            return EnginePeer(peer)
        }
        return nil
    }

    private func startsGroup(at index: Int, author: EnginePeer?) -> Bool {
        guard index > 0 else { return true }
        let message = self.messages[index]
        let previous = self.messages[index - 1]
        let sameConversation = message.id.peerId == previous.id.peerId && message.threadId == previous.threadId
            && !message.media.contains(where: { $0 is TelegramMediaAction })
            && !previous.media.contains(where: { $0 is TelegramMediaAction })
        return !ShadowMessageScreenshotGrouping.continuesGroup(authorId: author?.id.toInt64(), timestamp: message.timestamp, previousAuthorId: self.author(of: previous)?.id.toInt64(), previousTimestamp: previous.timestamp, sameConversation: sameConversation)
    }

    private func appendAvatar(author: EnginePeer?, y: CGFloat) {
        let size = CGSize(width: 32.0, height: 32.0)
        let avatar = AvatarNode(font: Font.regular(14.0))
        avatar.frame = CGRect(origin: CGPoint(x: 8.0, y: y), size: size)
        avatar.updateSize(size: size)
        avatar.clipsToBounds = true
        avatar.cornerRadius = size.width * 0.5
        if let author {
            // Unlike setPeerV2's image-cache-only path, setPeer also prepares
            // the gradient/initials placeholder when no photo is available.
            avatar.setPeer(context: self.context, theme: self.messageTheme, peer: author, clipStyle: .round, synchronousLoad: true, displayDimensions: size)
        } else {
            avatar.setCustomLetters(["?"])
        }
        self.content.addSubnode(avatar)
        avatar.recursivelyEnsureDisplaySynchronously(true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Скриншот сообщений"
        self.view.backgroundColor = self.data.theme.theme.list.blocksBackgroundColor
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(self.close))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(self.share))
        self.navigationItem.rightBarButtonItem?.isEnabled = false
        self.view.addSubview(self.scrollView)
        self.scrollView.addSubview(self.content.view)
        self.content.isUserInteractionEnabled = false
        self.content.clipsToBounds = true
        self.content.backgroundColor = self.data.theme.theme.chatList.backgroundColor

        switch self.options.background {
        case .white: self.content.backgroundColor = .white
        case .black: self.content.backgroundColor = .black
        case .customImage:
            let url = ShadowMessageScreenshotSettings.backgroundURL(mediaBoxPath: self.context.account.postbox.mediaBox.basePath)
            if let image = UIImage(contentsOfFile: url.path) {
                let view = UIImageView(image: image)
                view.contentMode = .scaleAspectFill
                view.clipsToBounds = true
                self.content.view.addSubview(view)
                self.imageBackground = view
            }
        case .chat:
            let background = createWallpaperBackgroundNode(context: self.context, forChatDisplay: false)
            background.update(wallpaper: self.data.theme.wallpaper, animated: false)
            background.updateBubbleTheme(bubbleTheme: self.data.theme.theme, bubbleCorners: self.data.chatBubbleCorners)
            self.content.addSubnode(background)
            self.background = background
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !self.started else { return }
        self.started = true
        if self.options.background == .customImage && self.imageBackground == nil {
            self.fail("Своя картинка не найдена. Выбери её в Кастомизации → Скриншоты сообщений.")
            return
        }
        self.appendMessage(at: 0)
    }

    private func appendMessage(at index: Int) {
        guard self.viewIfLoaded?.window != nil else { return }
        guard index < self.messages.count else {
            self.contentHeight += 8.0
            self.ready = true
            self.navigationItem.rightBarButtonItem?.isEnabled = true
            self.updateContentLayout()
            return
        }
        let message = self.messages[index]
        let author = self.author(of: message)
        let startsGroup = self.startsGroup(at: index, author: author)
        if index > 0 {
            self.contentHeight += startsGroup ? 10.0 : 2.0
        }
        var rowOptions = self.options
        rowOptions.showNames = self.options.showNames && startsGroup
        // This is a render-only copy, not a Postbox write or a change to the
        // message's direction, ID, forwarding information or read state.
        let renderMessage = message.author == nil ? (author.map { message.withUpdatedAuthor($0._asPeer()) } ?? message) : message
        let avatarWidth: CGFloat = self.options.showAvatars ? 42.0 : 0.0
        let wallpaper: TelegramWallpaper = self.options.background == .chat ? self.data.theme.wallpaper : .color(self.options.background == .white ? 0xffffff : 0x000000)
        guard let template = self.context.sharedContext.makeChatMessagePreviewItem(context: self.context, messages: [renderMessage], theme: self.messageTheme, strings: self.data.strings, wallpaper: wallpaper, fontSize: self.data.fontSize, chatBubbleCorners: self.data.chatBubbleCorners, dateTimeFormat: self.data.dateTimeFormat, nameOrder: self.data.nameDisplayOrder, forcedResourceStatus: nil, tapMessage: nil, clickThroughMessage: nil, backgroundNode: self.background, availableReactions: nil, accountPeer: nil, isCentered: false, isPreview: false, isStandalone: true, rank: nil, rankRole: nil) as? ChatMessageItemImpl else {
            self.fail("Не удалось подготовить сообщение."); return
        }
        template.controllerInteraction.chatIsRotated = false
        template.controllerInteraction.canReadHistory = false
        var downloads = template.controllerInteraction.automaticMediaDownloadSettings
        downloads.cellular.enabled = false
        downloads.wifi.enabled = false
        downloads.downloadInBackground = false
        template.controllerInteraction.automaticMediaDownloadSettings = downloads
        let data = ChatPresentationData(theme: ChatPresentationThemeData(theme: self.messageTheme, wallpaper: wallpaper), fontSize: self.data.fontSize, strings: self.data.strings, dateTimeFormat: self.data.dateTimeFormat, nameDisplayOrder: self.data.nameDisplayOrder, disableAnimations: true, largeEmoji: false, chatBubbleCorners: self.data.chatBubbleCorners, shadowScreenshot: rowOptions)
        let item = ChatMessageItemImpl(presentationData: data, context: self.context, chatLocation: template.chatLocation, associatedData: template.associatedData, controllerInteraction: template.controllerInteraction, content: template.content, disableDate: true)
        let params = ListViewItemLayoutParams(width: self.width - avatarWidth - 8.0, leftInset: 0.0, rightInset: 0.0, availableHeight: 1000.0)
        item.nodeConfiguredForParams(async: { $0() }, params: params, synchronousLoads: true, previousItem: nil, nextItem: nil, completion: { [weak self] node, apply in
            guard let self, self.viewIfLoaded?.window != nil else { return }
            apply().1(ListViewItemApply(isOnScreen: true))
            let groupTop = self.contentHeight
            // Stickers use a separate native node without the bubble's author
            // header. Give those rows the same once-per-group name treatment.
            var header: UILabel?
            if rowOptions.showNames, !(node is ChatMessageBubbleItemNode), let author {
                let label = UILabel()
                label.font = Font.semibold(14.0)
                label.textColor = self.messageTheme.chat.message.incoming.accentTextColor
                label.text = author.compactDisplayTitle
                label.lineBreakMode = .byTruncatingTail
                label.frame = CGRect(x: avatarWidth + 8.0, y: self.contentHeight, width: params.width - 8.0, height: 20.0)
                header = label
            }
            let headerHeight: CGFloat = header == nil ? 0.0 : 20.0
            let height = max(startsGroup && self.options.showAvatars ? 32.0 : 1.0, node.contentSize.height + headerHeight)
            guard ShadowMessageScreenshotSettings.renderScale(width: Double(self.width), height: Double(self.contentHeight + height + 20.0)) != nil else {
                self.fail("Подборка слишком длинная. Выбери меньше сообщений."); return
            }
            if let header { self.content.view.addSubview(header) }
            // Native cells retain their actual direction and media semantics.
            // Align their content frame, not the full-width cell, to one column.
            let contentFrame = (node as? ChatMessageItemNodeProtocol)?.contentFrame() ?? CGRect(origin: .zero, size: node.contentSize)
            node.frame = CGRect(x: avatarWidth + 8.0 - contentFrame.minX, y: self.contentHeight + headerHeight, width: params.width, height: node.contentSize.height)
            self.content.addSubnode(node)
            node.isUserInteractionEnabled = false
            node.visibility = .visible(1.0, CGRect(origin: .zero, size: node.bounds.size))
            if !self.options.showTime { self.hideTime(in: node) }
            if self.options.showAvatars && startsGroup {
                self.appendAvatar(author: author, y: groupTop)
            }
            self.contentHeight += height
            self.updateContentLayout()
            // Yield between messages to keep dismissal responsive.
            DispatchQueue.main.async { [weak self] in self?.appendMessage(at: index + 1) }
        })
    }

    private func hideTime(in node: ASDisplayNode) {
        if node is ChatMessageDateAndStatusNode { node.isHidden = true }
        for child in node.subnodes ?? [] { self.hideTime(in: child) }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.scrollView.frame = self.view.bounds.inset(by: self.view.safeAreaInsets)
        self.updateContentLayout()
    }

    private func updateContentLayout() {
        let size = CGSize(width: self.width, height: self.contentHeight)
        self.content.bounds = CGRect(origin: .zero, size: size)
        let scale = min(1.0, max(1.0, self.scrollView.bounds.width) / self.width)
        self.content.view.transform = CGAffineTransform(scaleX: scale, y: scale)
        self.content.position = CGPoint(x: self.scrollView.bounds.width * 0.5, y: size.height * scale * 0.5)
        self.scrollView.contentSize = CGSize(width: self.scrollView.bounds.width, height: size.height * scale)
        self.background?.frame = CGRect(origin: .zero, size: size)
        self.background?.updateLayout(size: size, displayMode: .aspectFill, transition: .immediate)
        self.imageBackground?.frame = CGRect(origin: .zero, size: size)
        for case let node as ListViewItemNode in self.content.subnodes ?? [] {
            // Native message wallpaper coordinates expect an inverted list.
            // Convert without rotating the screenshot or the message itself.
            let rect = CGRect(x: node.frame.minX, y: size.height - node.frame.maxY + node.insets.top, width: node.frame.width, height: node.frame.height)
            node.updateAbsoluteRect(rect, within: size)
        }
    }

    private func fail(_ text: String) {
        self.ready = false
        self.navigationItem.rightBarButtonItem?.isEnabled = false
        let alert = UIAlertController(title: "Скриншот сообщений", message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "ОК", style: .default))
        self.present(alert, animated: true)
    }

    @objc private func close() { self.dismiss(animated: true) }

    @objc private func share() {
        guard self.ready, let scale = ShadowMessageScreenshotSettings.renderScale(width: Double(self.width), height: Double(self.contentHeight)) else { return }
        let format = UIGraphicsImageRendererFormat()
        format.scale = CGFloat(scale)
        format.opaque = true
        self.content.recursivelyEnsureDisplaySynchronously(true)
        let previewTransform = self.content.view.transform
        self.content.view.transform = .identity
        defer { self.content.view.transform = previewTransform }
        // Layer render ignores the outer scroll view and captures the full selection.
        let image = UIGraphicsImageRenderer(size: self.content.bounds.size, format: format).image { renderer in
            self.content.layer.render(in: renderer.cgContext)
        }
        let share = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        share.popoverPresentationController?.barButtonItem = self.navigationItem.rightBarButtonItem
        self.present(share, animated: true)
    }
}

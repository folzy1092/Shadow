import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import AccountContext
import AvatarNode
import WallpaperBackgroundNode
import ChatMessageItemImpl
import ChatMessageDateAndStatusNode

extension ChatControllerImpl {
    func presentShadowMessageScreenshot() {
        guard !self.shadowScreenshotPreparing,
              let ids = self.presentationInterfaceState.interfaceState.selectionState?.selectedIds, !ids.isEmpty else { return }
        guard ids.count <= 100 else { self.shadowScreenshotError("Выбери не больше 100 сообщений."); return }
        self.shadowScreenshotPreparing = true
        let _ = (self.context.account.postbox.transaction { transaction -> (AyuGramSettings, [EngineRawMessage]) in
            let messages = ids.compactMap { transaction.getMessage($0) }.sorted { $0.index < $1.index }
            return (currentAyuGramSettings(transaction: transaction), messages)
        } |> deliverOnMainQueue).start(next: { [weak self] settings, messages in
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
            let preview = ShadowMessageScreenshotPreview(context: self.context, messages: messages, data: data, options: settings.messageScreenshot)
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
    private let messages: [EngineRawMessage]
    private let data: ChatPresentationData
    private let options: ShadowMessageScreenshotSettings
    private let scrollView = UIScrollView()
    private let content = ASDisplayNode()
    private var background: WallpaperBackgroundNode?
    private var imageBackground: UIImageView?
    private var started = false
    private var ready = false
    private let width: CGFloat = 390.0
    private var contentHeight: CGFloat = 12.0

    init(context: AccountContext, messages: [EngineRawMessage], data: ChatPresentationData, options: ShadowMessageScreenshotSettings) {
        self.context = context
        self.messages = messages
        self.data = data
        self.options = options
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

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
        let avatarWidth: CGFloat = self.options.showAvatars ? 42.0 : 0.0
        let wallpaper: TelegramWallpaper = self.options.background == .chat ? self.data.theme.wallpaper : .color(self.options.background == .white ? 0xffffff : 0x000000)
        guard let template = self.context.sharedContext.makeChatMessagePreviewItem(context: self.context, messages: [message], theme: self.data.theme.theme, strings: self.data.strings, wallpaper: wallpaper, fontSize: self.data.fontSize, chatBubbleCorners: self.data.chatBubbleCorners, dateTimeFormat: self.data.dateTimeFormat, nameOrder: self.data.nameDisplayOrder, forcedResourceStatus: nil, tapMessage: nil, clickThroughMessage: nil, backgroundNode: self.background, availableReactions: nil, accountPeer: nil, isCentered: false, isPreview: false, isStandalone: true, rank: nil, rankRole: nil) as? ChatMessageItemImpl else {
            self.fail("Не удалось подготовить сообщение."); return
        }
        template.controllerInteraction.chatIsRotated = false
        var downloads = template.controllerInteraction.automaticMediaDownloadSettings
        downloads.cellular.enabled = false
        downloads.wifi.enabled = false
        downloads.downloadInBackground = false
        template.controllerInteraction.automaticMediaDownloadSettings = downloads
        let data = ChatPresentationData(theme: ChatPresentationThemeData(theme: self.data.theme.theme, wallpaper: wallpaper), fontSize: self.data.fontSize, strings: self.data.strings, dateTimeFormat: self.data.dateTimeFormat, nameDisplayOrder: self.data.nameDisplayOrder, disableAnimations: true, largeEmoji: false, chatBubbleCorners: self.data.chatBubbleCorners, shadowScreenshot: self.options)
        let item = ChatMessageItemImpl(presentationData: data, context: self.context, chatLocation: template.chatLocation, associatedData: template.associatedData, controllerInteraction: template.controllerInteraction, content: template.content, disableDate: true)
        let params = ListViewItemLayoutParams(width: self.width - avatarWidth - 8.0, leftInset: 0.0, rightInset: 0.0, availableHeight: 1000.0)
        item.nodeConfiguredForParams(async: { $0() }, params: params, synchronousLoads: true, previousItem: nil, nextItem: nil, completion: { [weak self] node, apply in
            guard let self, self.viewIfLoaded?.window != nil else { return }
            apply().1(ListViewItemApply(isOnScreen: true))
            let height = max(36.0, node.contentSize.height)
            guard ShadowMessageScreenshotSettings.renderScale(width: Double(self.width), height: Double(self.contentHeight + height + 20.0)) != nil else {
                self.fail("Подборка слишком длинная. Выбери меньше сообщений."); return
            }
            node.frame = CGRect(x: avatarWidth + 4.0, y: self.contentHeight, width: params.width, height: height)
            self.content.addSubnode(node)
            node.isUserInteractionEnabled = false
            if !self.options.showTime { self.hideTime(in: node) }
            if self.options.showAvatars, let author = message.author {
                let avatar = AvatarNode(font: Font.regular(14.0))
                avatar.frame = CGRect(x: 6.0, y: self.contentHeight + max(0.0, height - 32.0), width: 32.0, height: 32.0)
                avatar.setPeerV2(context: self.context, theme: self.data.theme.theme, peer: EnginePeer(author), synchronousLoad: true)
                self.content.addSubnode(avatar)
            }
            self.contentHeight += height + 6.0
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
        // Layer render ignores the outer scroll view and captures the full selection.
        let image = UIGraphicsImageRenderer(size: self.content.bounds.size, format: format).image { renderer in
            self.content.layer.render(in: renderer.cgContext)
        }
        let share = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        share.popoverPresentationController?.barButtonItem = self.navigationItem.rightBarButtonItem
        self.present(share, animated: true)
    }
}

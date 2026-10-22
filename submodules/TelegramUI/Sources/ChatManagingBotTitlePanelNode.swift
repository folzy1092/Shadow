import Foundation
import UIKit
import Display
import AsyncDisplayKit
import TelegramPresentationData
import ChatPresentationInterfaceState
import ComponentFlow
import AvatarNode
import MultilineTextComponent
import PlainButtonComponent
import ComponentDisplayAdapters
import AccountContext
import TelegramCore
import BundleIconComponent
import ContextUI
import SwiftSignalKit
import LegacyChatHeaderPanelComponent

// Shadow: how the bot panel is drawn next to the pinned message
// (ShadowBusinessBotPinnedTitlePanelNode). full is stock Telegram.
enum ShadowManagingBotPanelStyle: Equatable {
    case full
    // One half of a 50 pt row: avatar, name (if shown), Стоп/Старт, settings.
    case half(showName: Bool)
    // Only the avatar; a tap opens Стоп/Старт and the settings menu.
    case icon
}

private final class ChatManagingBotTitlePanelComponent: Component {
    let context: AccountContext
    let theme: PresentationTheme
    let strings: PresentationStrings
    let insets: UIEdgeInsets
    let peer: EnginePeer
    let managesChat: Bool
    let isPaused: Bool
    let style: ShadowManagingBotPanelStyle
    let toggleIsPaused: () -> Void
    let openSettings: (UIView) -> Void
    let openBotMenu: (UIView) -> Void

    init(
        context: AccountContext,
        theme: PresentationTheme,
        strings: PresentationStrings,
        insets: UIEdgeInsets,
        peer: EnginePeer,
        managesChat: Bool,
        isPaused: Bool,
        style: ShadowManagingBotPanelStyle = .full,
        toggleIsPaused: @escaping () -> Void,
        openSettings: @escaping (UIView) -> Void,
        openBotMenu: @escaping (UIView) -> Void = { _ in }
    ) {
        self.context = context
        self.theme = theme
        self.strings = strings
        self.insets = insets
        self.peer = peer
        self.managesChat = managesChat
        self.isPaused = isPaused
        self.style = style
        self.toggleIsPaused = toggleIsPaused
        self.openSettings = openSettings
        self.openBotMenu = openBotMenu
    }

    static func ==(lhs: ChatManagingBotTitlePanelComponent, rhs: ChatManagingBotTitlePanelComponent) -> Bool {
        if lhs.context !== rhs.context {
            return false
        }
        if lhs.theme !== rhs.theme {
            return false
        }
        if lhs.strings != rhs.strings {
            return false
        }
        if lhs.insets != rhs.insets {
            return false
        }
        if lhs.peer != rhs.peer {
            return false
        }
        if lhs.managesChat != rhs.managesChat {
            return false
        }
        if lhs.isPaused != rhs.isPaused {
            return false
        }
        if lhs.style != rhs.style {
            return false
        }
        return true
    }

    final class View: UIView {
        private let title = ComponentView<Empty>()
        private let text = ComponentView<Empty>()
        private var avatarNode: AvatarNode?
        private let actionButton = ComponentView<Empty>()
        private let settingsButton = ComponentView<Empty>()
        // Shadow: icon style — active/paused dot on the avatar, tap anywhere.
        private let shadowStatusDot = UIView()
        private var shadowIconTap: UITapGestureRecognizer?
        
        private var component: ChatManagingBotTitlePanelComponent?
        
        override init(frame: CGRect) {
            super.init(frame: frame)
            
            self.shadowStatusDot.isUserInteractionEnabled = false
            self.shadowStatusDot.isHidden = true
            self.addSubview(self.shadowStatusDot)
            
            let shadowIconTap = UITapGestureRecognizer(target: self, action: #selector(self.shadowIconTapped))
            shadowIconTap.isEnabled = false
            self.addGestureRecognizer(shadowIconTap)
            self.shadowIconTap = shadowIconTap
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        @objc private func shadowIconTapped() {
            guard let component = self.component, let avatarView = self.avatarNode?.view else {
                return
            }
            component.openBotMenu(avatarView)
        }
        
        func update(component: ChatManagingBotTitlePanelComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
            self.component = component
            
            switch component.style {
            case .full:
                self.shadowIconTap?.isEnabled = false
                self.shadowStatusDot.isHidden = true
                self.avatarNode?.view.alpha = 1.0
                self.title.view?.isHidden = false
                self.text.view?.isHidden = false
                self.settingsButton.view?.isHidden = false
                self.actionButton.view?.isHidden = false
                return self.updateFull(component: component, availableSize: availableSize, transition: transition)
            case let .half(showName):
                self.shadowIconTap?.isEnabled = false
                self.shadowStatusDot.isHidden = true
                self.avatarNode?.view.alpha = 1.0
                return self.updateShadowCompact(component: component, availableSize: availableSize, showName: showName, isIcon: false, transition: transition)
            case .icon:
                self.shadowIconTap?.isEnabled = true
                return self.updateShadowCompact(component: component, availableSize: availableSize, showName: false, isIcon: true, transition: transition)
            }
        }
        
        private func shadowAvatarNode(component: ChatManagingBotTitlePanelComponent, frame: CGRect) {
            let avatarNode: AvatarNode
            if let current = self.avatarNode {
                avatarNode = current
            } else {
                avatarNode = AvatarNode(font: avatarPlaceholderFont(size: 15.0))
                self.avatarNode = avatarNode
                self.insertSubview(avatarNode.view, belowSubview: self.shadowStatusDot)
            }
            avatarNode.frame = frame
            avatarNode.updateSize(size: frame.size)
            avatarNode.setPeer(context: component.context, theme: component.theme, peer: component.peer)
        }
        
        // Shadow: the half and icon styles (50 pt high). Left to right: avatar,
        // name (half, if shown), Стоп/Старт, settings. Without the name the
        // returned width is what the content needs, so the parent can give the
        // rest of the row to the pinned message.
        private func updateShadowCompact(component: ChatManagingBotTitlePanelComponent, availableSize: CGSize, showName: Bool, isIcon: Bool, transition: ComponentTransition) -> CGSize {
            let height: CGFloat = 50.0
            let avatarDiameter: CGFloat = isIcon ? 34.0 : 30.0
            let leftInset: CGFloat = component.insets.left + 8.0
            let rightInset: CGFloat = component.insets.right + (isIcon ? 8.0 : 4.0)
            let avatarTextSpacing: CGFloat = 7.0
            let avatarButtonsSpacing: CGFloat = 6.0
            let buttonsSpacing: CGFloat = 4.0
            
            var actionButtonSize = CGSize()
            var settingsButtonSize = CGSize()
            var buttonsWidth: CGFloat = 0.0
            if !isIcon {
                actionButtonSize = self.actionButton.update(
                    transition: transition,
                    component: AnyComponent(PlainButtonComponent(
                        content: AnyComponent(MultilineTextComponent(
                            text: .plain(NSAttributedString(string: component.isPaused ? component.strings.Chat_BusinessBotPanel_ActionStart : component.strings.Chat_BusinessBotPanel_ActionStop, font: Font.semibold(13.0), textColor: component.theme.list.itemCheckColors.foregroundColor))
                        )),
                        background: AnyComponent(RoundedRectangle(
                            color: component.theme.list.itemCheckColors.fillColor,
                            cornerRadius: nil
                        )),
                        effectAlignment: .center,
                        contentInsets: UIEdgeInsets(top: 4.0, left: 9.0, bottom: 4.0, right: 9.0),
                        action: { [weak self] in
                            guard let self, let component = self.component else {
                                return
                            }
                            component.toggleIsPaused()
                        },
                        animateAlpha: true,
                        animateScale: false,
                        animateContents: false
                    )),
                    environment: {},
                    containerSize: CGSize(width: 120.0, height: 100.0)
                )
                settingsButtonSize = self.settingsButton.update(
                    transition: transition,
                    component: AnyComponent(PlainButtonComponent(
                        content: AnyComponent(BundleIconComponent(
                            name: "Chat/Context Menu/Customize",
                            tintColor: component.theme.chat.inputPanel.panelControlColor
                        )),
                        effectAlignment: .center,
                        minSize: CGSize(width: 28.0, height: 40.0),
                        contentInsets: UIEdgeInsets(),
                        action: { [weak self] in
                            guard let self, let component = self.component, let settingsButtonView = self.settingsButton.view else {
                                return
                            }
                            component.openSettings(settingsButtonView)
                        },
                        animateAlpha: true,
                        animateScale: false,
                        animateContents: false
                    )),
                    environment: {},
                    containerSize: CGSize(width: 100.0, height: 100.0)
                )
                buttonsWidth = settingsButtonSize.width
                if component.managesChat {
                    buttonsWidth += actionButtonSize.width + buttonsSpacing
                }
            }
            
            let contentWidth = leftInset + avatarDiameter + (isIcon ? 0.0 : avatarButtonsSpacing + buttonsWidth) + rightInset
            var width = contentWidth
            
            var titleSize = CGSize()
            var textSize = CGSize()
            var displayText = false
            if showName && !isIcon {
                let maxTextWidth = availableSize.width - contentWidth - avatarTextSpacing + avatarButtonsSpacing
                if maxTextWidth >= 28.0 {
                    displayText = true
                    titleSize = self.title.update(
                        transition: .immediate,
                        component: AnyComponent(MultilineTextComponent(
                            text: .plain(NSAttributedString(string: component.peer.displayTitle(strings: component.strings, displayOrder: .firstLast), font: Font.semibold(14.0), textColor: component.theme.chat.inputPanel.panelControlColor))
                        )),
                        environment: {},
                        containerSize: CGSize(width: maxTextWidth, height: 100.0)
                    )
                    let textValue: String
                    if component.isPaused {
                        textValue = component.strings.Chat_BusinessBotPanel_StatusPaused
                    } else {
                        textValue = component.managesChat ? component.strings.Chat_BusinessBotPanel_StatusManages : component.strings.Chat_BusinessBotPanel_StatusHasAccess
                    }
                    textSize = self.text.update(
                        transition: .immediate,
                        component: AnyComponent(MultilineTextComponent(
                            text: .plain(NSAttributedString(string: textValue, font: Font.regular(12.0), textColor: component.theme.rootController.navigationBar.secondaryTextColor))
                        )),
                        environment: {},
                        containerSize: CGSize(width: maxTextWidth, height: 100.0)
                    )
                }
                width = max(contentWidth, availableSize.width)
            }
            let size = CGSize(width: width, height: height)
            
            let avatarFrame = CGRect(origin: CGPoint(x: leftInset, y: floor((height - avatarDiameter) * 0.5)), size: CGSize(width: avatarDiameter, height: avatarDiameter))
            self.shadowAvatarNode(component: component, frame: avatarFrame)
            
            self.title.view?.isHidden = !displayText
            self.text.view?.isHidden = !displayText
            if displayText {
                let textX = avatarFrame.maxX + avatarTextSpacing
                let titleFrame = CGRect(origin: CGPoint(x: textX, y: floor((height - titleSize.height - textSize.height) * 0.5)), size: titleSize)
                if let titleView = self.title.view {
                    if titleView.superview == nil {
                        titleView.layer.anchorPoint = CGPoint()
                        self.addSubview(titleView)
                    }
                    titleView.bounds = CGRect(origin: CGPoint(), size: titleFrame.size)
                    transition.setPosition(view: titleView, position: titleFrame.origin)
                }
                let textFrame = CGRect(origin: CGPoint(x: textX, y: titleFrame.maxY), size: textSize)
                if let textView = self.text.view {
                    if textView.superview == nil {
                        textView.layer.anchorPoint = CGPoint()
                        self.addSubview(textView)
                    }
                    textView.bounds = CGRect(origin: CGPoint(), size: textFrame.size)
                    transition.setPosition(view: textView, position: textFrame.origin)
                }
            }
            
            self.settingsButton.view?.isHidden = isIcon
            self.actionButton.view?.isHidden = isIcon
            if !isIcon {
                let settingsButtonFrame = CGRect(origin: CGPoint(x: size.width - rightInset - settingsButtonSize.width, y: floor((height - settingsButtonSize.height) * 0.5)), size: settingsButtonSize)
                if let settingsButtonView = self.settingsButton.view {
                    if settingsButtonView.superview == nil {
                        self.addSubview(settingsButtonView)
                    }
                    transition.setFrame(view: settingsButtonView, frame: settingsButtonFrame)
                }
                let actionButtonFrame = CGRect(origin: CGPoint(x: settingsButtonFrame.minX - buttonsSpacing - actionButtonSize.width, y: floor((height - actionButtonSize.height) * 0.5)), size: actionButtonSize)
                if let actionButtonView = self.actionButton.view {
                    if actionButtonView.superview == nil {
                        self.addSubview(actionButtonView)
                    }
                    transition.setFrame(view: actionButtonView, frame: actionButtonFrame)
                    transition.setAlpha(view: actionButtonView, alpha: component.managesChat ? 1.0 : 0.0)
                }
            }
            
            // Icon: green dot — the bot answers, gray — paused (avatar dimmed).
            let displayDot = isIcon && component.managesChat
            self.shadowStatusDot.isHidden = !displayDot
            if displayDot {
                let dotSize: CGFloat = 11.0
                self.shadowStatusDot.frame = CGRect(origin: CGPoint(x: avatarFrame.maxX - dotSize + 1.0, y: avatarFrame.maxY - dotSize + 1.0), size: CGSize(width: dotSize, height: dotSize))
                self.shadowStatusDot.layer.cornerRadius = dotSize * 0.5
                self.shadowStatusDot.layer.borderWidth = 1.5
                self.shadowStatusDot.layer.borderColor = component.theme.chat.inputPanel.panelBackgroundColor.withAlphaComponent(1.0).cgColor
                self.shadowStatusDot.backgroundColor = component.isPaused ? component.theme.chat.inputPanel.panelControlColor : UIColor(rgb: 0x34C759)
            }
            self.avatarNode?.view.alpha = (isIcon && component.isPaused) ? 0.5 : 1.0
            
            return size
        }
        
        private func updateFull(component: ChatManagingBotTitlePanelComponent, availableSize: CGSize, transition: ComponentTransition) -> CGSize {
            
            let topInset: CGFloat = 6.0
            let bottomInset: CGFloat = 6.0
            let avatarDiameter: CGFloat = 36.0
            let avatarTextSpacing: CGFloat = 8.0
            let titleTextSpacing: CGFloat = 1.0
            let leftInset: CGFloat = component.insets.left + 6.0
            let rightInset: CGFloat = component.insets.right + 10.0
            let actionAndSettingsButtonsSpacing: CGFloat = 8.0
            
            let actionButtonSize = self.actionButton.update(
                transition: transition,
                component: AnyComponent(PlainButtonComponent(
                    content: AnyComponent(MultilineTextComponent(
                        text: .plain(NSAttributedString(string: component.isPaused ? component.strings.Chat_BusinessBotPanel_ActionStart : component.strings.Chat_BusinessBotPanel_ActionStop, font: Font.semibold(15.0), textColor: component.theme.list.itemCheckColors.foregroundColor))
                    )),
                    background: AnyComponent(RoundedRectangle(
                        color: component.theme.list.itemCheckColors.fillColor,
                        cornerRadius: nil
                    )),
                    effectAlignment: .center,
                    contentInsets: UIEdgeInsets(top: 5.0, left: 12.0, bottom: 5.0, right: 12.0),
                    action: { [weak self] in
                        guard let self, let component = self.component else {
                            return
                        }
                        component.toggleIsPaused()
                    },
                    animateAlpha: true,
                    animateScale: false,
                    animateContents: false
                )),
                environment: {},
                containerSize: CGSize(width: 150.0, height: 100.0)
            )
            
            let settingsButtonSize = self.settingsButton.update(
                transition: transition,
                component: AnyComponent(PlainButtonComponent(
                    content: AnyComponent(BundleIconComponent(
                        name: "Chat/Context Menu/Customize",
                        tintColor: component.theme.chat.inputPanel.panelControlColor
                    )),
                    effectAlignment: .center,
                    minSize: CGSize(width: 1.0, height: 40.0),
                    contentInsets: UIEdgeInsets(top: 0.0, left: 2.0, bottom: 0.0, right: 2.0),
                    action: { [weak self] in
                        guard let self, let component = self.component else {
                            return
                        }
                        guard let settingsButtonView = self.settingsButton.view else {
                            return
                        }
                        component.openSettings(settingsButtonView)
                    },
                    animateAlpha: true,
                    animateScale: false,
                    animateContents: false
                )),
                environment: {},
                containerSize: CGSize(width: 150.0, height: 100.0)
            )
            
            var maxTextWidth: CGFloat = availableSize.width - leftInset - avatarDiameter - avatarTextSpacing - rightInset - settingsButtonSize.width - 8.0
            if component.managesChat {
                maxTextWidth -= actionButtonSize.width - actionAndSettingsButtonsSpacing
            }
            
            let titleSize = self.title.update(
                transition: .immediate,
                component: AnyComponent(MultilineTextComponent(
                    text: .plain(NSAttributedString(string: component.peer.displayTitle(strings: component.strings, displayOrder: .firstLast), font: Font.semibold(16.0), textColor: component.theme.chat.inputPanel.panelControlColor))
                )),
                environment: {},
                containerSize: CGSize(width: maxTextWidth, height: 100.0)
            )
            let textValue: String
            if component.isPaused {
                textValue = component.strings.Chat_BusinessBotPanel_StatusPaused
            } else {
                textValue = component.managesChat ? component.strings.Chat_BusinessBotPanel_StatusManages : component.strings.Chat_BusinessBotPanel_StatusHasAccess
            }
            let textSize = self.text.update(
                transition: .immediate,
                component: AnyComponent(MultilineTextComponent(
                    text: .plain(NSAttributedString(string: textValue, font: Font.regular(14.0), textColor: component.theme.rootController.navigationBar.secondaryTextColor))
                )),
                environment: {},
                containerSize: CGSize(width: maxTextWidth, height: 100.0)
            )
            
            let size = CGSize(width: availableSize.width, height: topInset + titleSize.height + titleTextSpacing + textSize.height + bottomInset)
            
            let titleFrame = CGRect(origin: CGPoint(x: leftInset + avatarDiameter + avatarTextSpacing, y: topInset), size: titleSize)
            if let titleView = self.title.view {
                if titleView.superview == nil {
                    titleView.layer.anchorPoint = CGPoint()
                    self.addSubview(titleView)
                }
                titleView.bounds = CGRect(origin: CGPoint(), size: titleFrame.size)
                transition.setPosition(view: titleView, position: titleFrame.origin)
            }
            
            let textFrame = CGRect(origin: CGPoint(x: titleFrame.minX, y: titleFrame.maxY + titleTextSpacing), size: textSize)
            if let textView = self.text.view {
                if textView.superview == nil {
                    textView.layer.anchorPoint = CGPoint()
                    self.addSubview(textView)
                }
                textView.bounds = CGRect(origin: CGPoint(), size: textFrame.size)
                transition.setPosition(view: textView, position: textFrame.origin)
            }
            
            let avatarFrame = CGRect(origin: CGPoint(x: leftInset, y: floor((size.height - avatarDiameter) * 0.5)), size: CGSize(width: avatarDiameter, height: avatarDiameter))
            let avatarNode: AvatarNode
            if let current = self.avatarNode {
                avatarNode = current
            } else {
                avatarNode = AvatarNode(font: avatarPlaceholderFont(size: 15.0))
                self.avatarNode = avatarNode
                self.insertSubview(avatarNode.view, belowSubview: self.shadowStatusDot)
            }
            avatarNode.frame = avatarFrame
            avatarNode.updateSize(size: avatarFrame.size)
            avatarNode.setPeer(context: component.context, theme: component.theme, peer: component.peer)
            
            let settingsButtonFrame = CGRect(origin: CGPoint(x: availableSize.width - rightInset - settingsButtonSize.width, y: floor((size.height - settingsButtonSize.height) * 0.5)), size: settingsButtonSize)
            if let settingsButtonView = self.settingsButton.view {
                if settingsButtonView.superview == nil {
                    self.addSubview(settingsButtonView)
                }
                transition.setFrame(view: settingsButtonView, frame: settingsButtonFrame)
            }
            
            let actionButtonFrame = CGRect(origin: CGPoint(x: settingsButtonFrame.minX - actionAndSettingsButtonsSpacing - actionButtonSize.width, y: floor((size.height - actionButtonSize.height) * 0.5)), size: actionButtonSize)
            if let actionButtonView = self.actionButton.view {
                if actionButtonView.superview == nil {
                    self.addSubview(actionButtonView)
                }
                transition.setFrame(view: actionButtonView, frame: actionButtonFrame)
                transition.setAlpha(view: actionButtonView, alpha: component.managesChat ? 1.0 : 0.0)
            }
            
            return size
        }
    }

    func makeView() -> View {
        return View(frame: CGRect())
    }

    func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}

final class ChatManagingBotTitlePanelNode: ChatTitleAccessoryPanelNode {
    private let context: AccountContext
    private let separatorNode: ASDisplayNode
    private let content = ComponentView<Empty>()
    
    private var chatLocation: ChatLocation?
    private var theme: PresentationTheme?
    private var managingBot: ChatManagingBot?
    
    // Shadow: set by ShadowBusinessBotPinnedTitlePanelNode. contentWidth is the
    // width the last layout drew (in the half style without the name: what the
    // avatar and buttons need).
    var shadowStyle: ShadowManagingBotPanelStyle = .full
    private(set) var shadowContentWidth: CGFloat = 0.0
    
    init(context: AccountContext) {
        self.context = context
        self.separatorNode = ASDisplayNode()
        self.separatorNode.isLayerBacked = true
        
        super.init()

        self.addSubnode(self.separatorNode)
    }
    
    private func toggleIsPaused() {
        guard let chatPeerId = self.chatLocation?.peerId else {
            return
        }
        
        let _ = self.context.engine.peers.toggleChatManagingBotIsPaused(chatId: chatPeerId)
    }
    
    private func openSettingsMenu(sourceView: UIView, includePauseToggle: Bool = false) {
        guard let interfaceInteraction = self.interfaceInteraction else {
            return
        }
        guard let chatController = interfaceInteraction.chatController() else {
            return
        }
        guard let chatPeerId = self.chatLocation?.peerId else {
            return
        }
        guard let managingBot = self.managingBot else {
            return
        }
            
        let strings = self.context.sharedContext.currentPresentationData.with { $0 }.strings
        
        var items: [ContextMenuItem] = []
        
        // Shadow: the icon style has no Стоп/Старт button, the menu has it.
        if includePauseToggle && (managingBot.canReply || managingBot.isPaused) {
            let isPaused = managingBot.isPaused
            items.append(.action(ContextMenuActionItem(text: isPaused ? strings.Chat_BusinessBotPanel_ActionStart : strings.Chat_BusinessBotPanel_ActionStop, icon: { theme in
                return generateTintedImage(image: UIImage(bundleImageName: isPaused ? "Chat/Context Menu/Play" : "Chat/Context Menu/Pause"), color: theme.contextMenu.primaryColor)
            }, action: { [weak self] _, a in
                a(.default)
                
                self?.toggleIsPaused()
            })))
        }
        
        items.append(.action(ContextMenuActionItem(text: strings.Chat_BusinessBotPanel_Menu_RemoveBot, textColor: .destructive, icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Clear"), color: theme.contextMenu.destructiveColor)
        }, action: { [weak self] _, a in
            a(.default)
            
            guard let self else {
                return
            }
            self.context.engine.peers.removeChatManagingBot(chatId: chatPeerId)
        })))
        if let url = managingBot.settingsUrl {
            items.append(.action(ContextMenuActionItem(text: strings.Chat_BusinessBotPanel_Menu_ManageBot, icon: { theme in
                return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Settings"), color: theme.contextMenu.primaryColor)
            }, action: { [weak self] _, a in
                a(.default)
                
                guard let self else {
                    return
                }
                let _ = (self.context.sharedContext.resolveUrl(context: self.context, peerId: nil, url: url, skipUrlAuth: false)
                |> deliverOnMainQueue).start(next: { [weak self] result in
                    guard let self else {
                        return
                    }
                    guard let chatController = interfaceInteraction.chatController() else {
                        return
                    }
                    self.context.sharedContext.openResolvedUrl(
                        result,
                        context: self.context,
                        urlContext: .generic,
                        navigationController: chatController.navigationController as? NavigationController,
                        forceExternal: false,
                        forceUpdate: false,
                        openPeer: { [weak self] peer, navigation in
                            guard let self, let chatController = interfaceInteraction.chatController() else {
                                return
                            }
                            guard let navigationController = chatController.navigationController as? NavigationController else {
                                return
                            }
                            switch navigation {
                            case let .chat(_, subject, peekData):
                                self.context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: self.context, chatLocation: .peer(peer), subject: subject, peekData: peekData))
                            case let .withBotStartPayload(botStart):
                                self.context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: self.context, chatLocation: .peer(peer), botStart: botStart, keepStack: .always))
                            case let .withAttachBot(attachBotStart):
                                self.context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: self.context, chatLocation: .peer(peer), attachBotStart: attachBotStart))
                            case let .withBotApp(botAppStart):
                                self.context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: self.context, chatLocation: .peer(peer), botAppStart: botAppStart))
                            case .info:
                                let _ = (self.context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peer.id))
                                |> deliverOnMainQueue).start(next: { [weak self] peer in
                                    guard let self, let peer, let chatController = interfaceInteraction.chatController() else {
                                        return
                                    }
                                    guard let navigationController = chatController.navigationController as? NavigationController else {
                                        return
                                    }
                                    if let controller = self.context.sharedContext.makePeerInfoController(context: self.context, updatedPresentationData: nil, peer: peer, mode: .generic, avatarInitiallyExpanded: false, fromChat: false, requestsContext: nil) {
                                        navigationController.pushViewController(controller)
                                    }
                                })
                            default:
                                break
                            }
                        },
                        sendFile: nil,
                        sendSticker: nil,
                        sendEmoji: nil,
                        requestMessageActionUrlAuth: nil,
                        joinVoiceChat: nil,
                        present: { [weak chatController] c, a in
                            chatController?.present(c, in: .window(.root), with: a)
                        },
                        dismissInput: {
                        },
                        contentContext: nil,
                        progress: nil,
                        completion: nil
                    )
                })
            })))
        }
        
        let presentationData = self.context.sharedContext.currentPresentationData.with { $0 }
        let contextController = makeContextController(presentationData: presentationData, source: .reference(HeaderContextReferenceContentSource(controller: chatController, sourceView: sourceView)), items: .single(ContextController.Items(content: .list(items))), gesture: nil)
        interfaceInteraction.presentController(contextController, nil)
    }
    
    override func updateLayout(width: CGFloat, leftInset: CGFloat, rightInset: CGFloat, transition: ContainedViewLayoutTransition, interfaceState: ChatPresentationInterfaceState) -> LayoutResult {
        self.chatLocation = interfaceState.chatLocation
        self.managingBot = interfaceState.contactStatus?.managingBot
        
        if interfaceState.theme !== self.theme {
            self.theme = interfaceState.theme
            
            self.separatorNode.backgroundColor = interfaceState.theme.rootController.navigationBar.separatorColor
        }

        transition.updateFrame(node: self.separatorNode, frame: CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: CGSize(width: width, height: UIScreenPixel)))
        self.separatorNode.isHidden = self.shadowStyle != .full

        if let managingBot = interfaceState.contactStatus?.managingBot {
            let contentSize = self.content.update(
                transition: ComponentTransition(transition),
                component: AnyComponent(ChatManagingBotTitlePanelComponent(
                    context: self.context,
                    theme: interfaceState.theme,
                    strings: interfaceState.strings,
                    insets: UIEdgeInsets(top: 0.0, left: leftInset, bottom: 0.0, right: rightInset),
                    peer: managingBot.bot,
                    managesChat: managingBot.canReply || managingBot.isPaused,
                    isPaused: managingBot.isPaused,
                    style: self.shadowStyle,
                    toggleIsPaused: { [weak self] in
                        guard let self else {
                            return
                        }
                        self.toggleIsPaused()
                    },
                    openSettings: { [weak self] sourceView in
                        guard let self else {
                            return
                        }
                        self.openSettingsMenu(sourceView: sourceView)
                    },
                    openBotMenu: { [weak self] sourceView in
                        guard let self else {
                            return
                        }
                        self.openSettingsMenu(sourceView: sourceView, includePauseToggle: true)
                    }
                )),
                environment: {},
                containerSize: CGSize(width: width, height: 1000.0)
            )
            if let contentView = self.content.view {
                if contentView.superview == nil {
                    self.view.addSubview(contentView)
                }
                transition.updateFrame(view: contentView, frame: CGRect(origin: CGPoint(), size: contentSize))
            }
            self.shadowContentWidth = contentSize.width

            return LayoutResult(backgroundHeight: contentSize.height, insetHeight: contentSize.height, hitTestSlop: 0.0)
        } else {
            self.shadowContentWidth = 0.0
            return LayoutResult(backgroundHeight: 0.0, insetHeight: 0.0, hitTestSlop: 0.0)
        }
        
    }
}

private final class HeaderContextReferenceContentSource: ContextReferenceContentSource {
    private let controller: ViewController
    private let sourceView: UIView

    init(controller: ViewController, sourceView: UIView) {
        self.controller = controller
        self.sourceView = sourceView
    }

    func transitionInfo() -> ContextControllerReferenceViewInfo? {
        return ContextControllerReferenceViewInfo(referenceView: self.sourceView, contentAreaInScreenSpace: mainWindowScreenBounds)
    }
}

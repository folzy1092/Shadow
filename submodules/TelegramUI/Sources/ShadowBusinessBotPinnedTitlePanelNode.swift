import Foundation
import UIKit
import Display
import AsyncDisplayKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import ChatPresentationInterfaceState
import LegacyChatHeaderPanelComponent
import AnimationCache
import MultiAnimationRenderer

// Shadow: the chat header when a business bot manages the chat and a message is
// pinned (ShadowBusinessBotPanel). Stock Telegram shows only the bot panel; this
// node holds the stock bot panel and the stock pinned panel side by side or
// one under the other, so both keep all their actions: Стоп/Старт and the
// settings menu of the bot, tap (next pinned message), long press (list of
// pinned messages), the list and close buttons of the pin.
final class ShadowBusinessBotPinnedTitlePanelNode: ChatTitleAccessoryPanelNode {
    struct Style: Equatable {
        var layout: ShadowBusinessBotPanel.Layout
        var pinnedFirst: Bool
        var compactBot: Bool
    }

    private let botPanel: ChatManagingBotTitlePanelNode
    private let pinnedPanel: ChatPinnedMessageTitlePanelNode
    private let separatorNode: ASDisplayNode

    var panelStyle = Style(layout: .split, pinnedFirst: false, compactBot: false)

    override var interfaceInteraction: ChatPanelInterfaceInteraction? {
        didSet {
            self.botPanel.interfaceInteraction = self.interfaceInteraction
            self.pinnedPanel.interfaceInteraction = self.interfaceInteraction
        }
    }

    init(context: AccountContext, animationCache: AnimationCache?, animationRenderer: MultiAnimationRenderer?) {
        self.botPanel = ChatManagingBotTitlePanelNode(context: context)
        self.pinnedPanel = ChatPinnedMessageTitlePanelNode(context: context, animationCache: animationCache, animationRenderer: animationRenderer)
        self.separatorNode = ASDisplayNode()
        self.separatorNode.isLayerBacked = true

        super.init()

        self.addSubnode(self.pinnedPanel)
        self.addSubnode(self.botPanel)
        self.addSubnode(self.separatorNode)
    }

    override func updateLayout(width: CGFloat, leftInset: CGFloat, rightInset: CGFloat, transition: ContainedViewLayoutTransition, interfaceState: ChatPresentationInterfaceState) -> LayoutResult {
        self.separatorNode.backgroundColor = interfaceState.theme.list.itemPlainSeparatorColor

        switch self.panelStyle.layout {
        case .stacked, .pinnedOnly:
            self.botPanel.shadowStyle = .full
            let botResult = self.botPanel.updateLayout(width: width, leftInset: leftInset, rightInset: rightInset, transition: transition, interfaceState: interfaceState)
            let pinnedResult = self.pinnedPanel.updateLayout(width: width, leftInset: leftInset, rightInset: rightInset, transition: transition, interfaceState: interfaceState)
            let botHeight = botResult.backgroundHeight
            let pinnedHeight = pinnedResult.backgroundHeight

            let botFrame: CGRect
            let pinnedFrame: CGRect
            if self.panelStyle.pinnedFirst {
                pinnedFrame = CGRect(origin: CGPoint(), size: CGSize(width: width, height: pinnedHeight))
                botFrame = CGRect(origin: CGPoint(x: 0.0, y: pinnedFrame.maxY), size: CGSize(width: width, height: botHeight))
            } else {
                botFrame = CGRect(origin: CGPoint(), size: CGSize(width: width, height: botHeight))
                pinnedFrame = CGRect(origin: CGPoint(x: 0.0, y: botFrame.maxY), size: CGSize(width: width, height: pinnedHeight))
            }
            transition.updateFrame(node: self.botPanel, frame: botFrame)
            transition.updateFrame(node: self.pinnedPanel, frame: pinnedFrame)
            let separatorY = min(botFrame.maxY, pinnedFrame.maxY)
            transition.updateFrame(node: self.separatorNode, frame: CGRect(origin: CGPoint(x: leftInset, y: separatorY), size: CGSize(width: width - leftInset - rightInset, height: UIScreenPixel)))
            transition.updateAlpha(node: self.separatorNode, alpha: 1.0)

            let height = botHeight + pinnedHeight
            return LayoutResult(backgroundHeight: height, insetHeight: height, hitTestSlop: 0.0)
        case .split, .icon:
            let isIcon = self.panelStyle.layout == .icon
            let height: CGFloat = 50.0
            let contentWidth = width - leftInset - rightInset

            self.botPanel.shadowStyle = isIcon ? .icon : .half(showName: !self.panelStyle.compactBot)
            // The bot's content is laid out from its left edge, so its width
            // can be read off the first layout (icon / without the name).
            let botAvailableWidth = isIcon ? contentWidth : CGFloat(ShadowBusinessBotPanel.splitBotWidth(totalWidth: Double(contentWidth), compact: false, contentWidth: 0.0))
            // At the right edge of the capsule the bot keeps off the rounding.
            let botRightInset: CGFloat = self.panelStyle.pinnedFirst ? (isIcon ? 4.0 : 8.0) : 0.0
            let _ = self.botPanel.updateLayout(width: botAvailableWidth, leftInset: 0.0, rightInset: botRightInset, transition: transition, interfaceState: interfaceState)
            let botWidth: CGFloat
            if isIcon {
                botWidth = self.botPanel.shadowContentWidth
            } else {
                botWidth = CGFloat(ShadowBusinessBotPanel.splitBotWidth(totalWidth: Double(contentWidth), compact: self.panelStyle.compactBot, contentWidth: Double(self.botPanel.shadowContentWidth)))
            }
            let pinnedWidth = max(0.0, contentWidth - botWidth)

            let botFrame: CGRect
            let pinnedFrame: CGRect
            let separatorX: CGFloat
            if self.panelStyle.pinnedFirst {
                pinnedFrame = CGRect(origin: CGPoint(x: leftInset, y: 0.0), size: CGSize(width: pinnedWidth, height: height))
                botFrame = CGRect(origin: CGPoint(x: pinnedFrame.maxX, y: 0.0), size: CGSize(width: botWidth, height: height))
                separatorX = botFrame.minX
            } else {
                botFrame = CGRect(origin: CGPoint(x: leftInset, y: 0.0), size: CGSize(width: botWidth, height: height))
                pinnedFrame = CGRect(origin: CGPoint(x: botFrame.maxX, y: 0.0), size: CGSize(width: pinnedWidth, height: height))
                separatorX = botFrame.maxX
            }
            transition.updateFrame(node: self.botPanel, frame: botFrame)
            // After the bot the pin's stripe moves closer (the pin panel adds
            // 18 pt for the capsule edge it no longer touches).
            let pinnedLeftInset: CGFloat = self.panelStyle.pinnedFirst ? 0.0 : -6.0
            let _ = self.pinnedPanel.updateLayout(width: pinnedWidth, leftInset: pinnedLeftInset, rightInset: 0.0, transition: transition, interfaceState: interfaceState)
            transition.updateFrame(node: self.pinnedPanel, frame: pinnedFrame)

            // The icon sits right next to the pin's stripe, without a divider.
            let separatorInset: CGFloat = 10.0
            transition.updateFrame(node: self.separatorNode, frame: CGRect(origin: CGPoint(x: separatorX, y: separatorInset), size: CGSize(width: UIScreenPixel, height: height - separatorInset * 2.0)))
            transition.updateAlpha(node: self.separatorNode, alpha: isIcon ? 0.0 : 1.0)

            return LayoutResult(backgroundHeight: height, insetHeight: height, hitTestSlop: 0.0)
        }
    }
}

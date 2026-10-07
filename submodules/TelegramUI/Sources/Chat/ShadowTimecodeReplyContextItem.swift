import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import AppBundle
import ContextUI

// Shadow: «Ответить с тайм-кодом» in the message menu of a voice message or
// round video. The second line shows the live position ("0:53") while the voice
// message keeps playing under the menu; tapping replies with that timecode.
final class ShadowTimecodeReplyContextItem: ContextMenuCustomItem {
    fileprivate let timecode: () -> String?
    fileprivate let action: (ContextControllerProtocol, String) -> Void

    // `timecode` is read every half second; nil keeps the last value.
    init(timecode: @escaping () -> String?, action: @escaping (ContextControllerProtocol, String) -> Void) {
        self.timecode = timecode
        self.action = action
    }

    func node(presentationData: PresentationData, getController: @escaping () -> ContextControllerProtocol?, actionSelected: @escaping (ContextMenuActionResult) -> Void) -> ContextMenuCustomNode {
        return ShadowTimecodeReplyContextItemNode(presentationData: presentationData, item: self, getController: getController)
    }
}

private final class ShadowTimecodeReplyContextItemNode: ASDisplayNode, ContextMenuCustomNode {
    private let item: ShadowTimecodeReplyContextItem
    private var presentationData: PresentationData
    private let getController: () -> ContextControllerProtocol?

    private let backgroundNode: ASDisplayNode
    private let highlightedBackgroundNode: ASDisplayNode
    private let textNode: ImmediateTextNode
    private let statusNode: ImmediateTextNode
    private let iconNode: ASImageNode
    private let buttonNode: HighlightTrackingButtonNode

    private var timer: SwiftSignalKit.Timer?
    private var currentTimecode: String
    private var validLayout: CGSize?

    var needsSeparator: Bool {
        return true
    }

    var needsPadding: Bool {
        return false
    }

    init(presentationData: PresentationData, item: ShadowTimecodeReplyContextItem, getController: @escaping () -> ContextControllerProtocol?) {
        self.item = item
        self.presentationData = presentationData
        self.getController = getController
        self.currentTimecode = item.timecode() ?? "0:00"

        self.backgroundNode = ASDisplayNode()
        self.backgroundNode.isAccessibilityElement = false
        self.backgroundNode.backgroundColor = presentationData.theme.contextMenu.itemBackgroundColor

        self.highlightedBackgroundNode = ASDisplayNode()
        self.highlightedBackgroundNode.isAccessibilityElement = false
        self.highlightedBackgroundNode.backgroundColor = presentationData.theme.contextMenu.itemHighlightedBackgroundColor
        self.highlightedBackgroundNode.alpha = 0.0

        self.textNode = ImmediateTextNode()
        self.textNode.isUserInteractionEnabled = false
        self.textNode.displaysAsynchronously = false
        self.textNode.maximumNumberOfLines = 1

        self.statusNode = ImmediateTextNode()
        self.statusNode.isUserInteractionEnabled = false
        self.statusNode.displaysAsynchronously = false
        self.statusNode.maximumNumberOfLines = 1

        self.iconNode = ASImageNode()
        self.iconNode.isUserInteractionEnabled = false
        self.iconNode.displaysAsynchronously = false

        self.buttonNode = HighlightTrackingButtonNode()
        self.buttonNode.isAccessibilityElement = true
        self.buttonNode.accessibilityLabel = "Ответить с тайм-кодом"

        super.init()

        self.addSubnode(self.backgroundNode)
        self.addSubnode(self.highlightedBackgroundNode)
        self.addSubnode(self.textNode)
        self.addSubnode(self.statusNode)
        self.addSubnode(self.iconNode)
        self.addSubnode(self.buttonNode)

        self.applyTheme()

        self.buttonNode.highligthedChanged = { [weak self] highlighted in
            self?.setIsHighlighted(highlighted)
        }
        self.buttonNode.addTarget(self, action: #selector(self.buttonPressed), forControlEvents: .touchUpInside)
    }

    deinit {
        self.timer?.invalidate()
    }

    override func didLoad() {
        super.didLoad()

        let timer = SwiftSignalKit.Timer(timeout: 0.5, repeat: true, completion: { [weak self] in
            self?.updateTimecode()
        }, queue: Queue.mainQueue())
        self.timer = timer
        timer.start()
    }

    private var textFont: UIFont {
        return Font.regular(self.presentationData.listsFontSize.baseDisplaySize)
    }

    private var statusFont: UIFont {
        return Font.regular(self.presentationData.listsFontSize.baseDisplaySize * 13.0 / 17.0)
    }

    private func applyTheme() {
        let theme = self.presentationData.theme.contextMenu
        self.backgroundNode.backgroundColor = theme.itemBackgroundColor
        self.highlightedBackgroundNode.backgroundColor = theme.itemHighlightedBackgroundColor
        self.textNode.attributedText = NSAttributedString(string: "Ответить с тайм-кодом", font: self.textFont, textColor: theme.primaryColor)
        self.statusNode.attributedText = NSAttributedString(string: self.currentTimecode, font: self.statusFont, textColor: theme.secondaryColor)
        self.iconNode.image = generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Reply"), color: theme.primaryColor)
    }

    private func updateTimecode() {
        guard let timecode = self.item.timecode(), timecode != self.currentTimecode else {
            return
        }
        self.currentTimecode = timecode
        self.statusNode.attributedText = NSAttributedString(string: timecode, font: self.statusFont, textColor: self.presentationData.theme.contextMenu.secondaryColor)
        if let size = self.validLayout {
            let statusSize = self.statusNode.updateLayout(CGSize(width: size.width - 80.0, height: .greatestFiniteMagnitude))
            self.statusNode.frame = CGRect(origin: self.statusNode.frame.origin, size: statusSize)
        }
    }

    func updateLayout(constrainedWidth: CGFloat, constrainedHeight: CGFloat) -> (CGSize, (CGSize, ContainedViewLayoutTransition) -> Void) {
        let sideInset: CGFloat = 16.0
        let iconSideInset: CGFloat = 12.0
        let verticalInset: CGFloat = 11.0
        let standardIconWidth: CGFloat = 32.0
        let rightTextInset: CGFloat = sideInset + standardIconWidth + iconSideInset

        let textSize = self.textNode.updateLayout(CGSize(width: constrainedWidth - sideInset - rightTextInset, height: .greatestFiniteMagnitude))
        let statusSize = self.statusNode.updateLayout(CGSize(width: constrainedWidth - sideInset - rightTextInset, height: .greatestFiniteMagnitude))

        let verticalSpacing: CGFloat = 2.0
        let combinedTextHeight = textSize.height + verticalSpacing + statusSize.height
        return (CGSize(width: max(textSize.width, statusSize.width) + sideInset + rightTextInset, height: verticalInset * 2.0 + combinedTextHeight), { [weak self] size, transition in
            guard let self else {
                return
            }
            self.validLayout = size
            let verticalOrigin = floor((size.height - combinedTextHeight) / 2.0)
            transition.updateFrameAdditive(node: self.textNode, frame: CGRect(origin: CGPoint(x: sideInset, y: verticalOrigin), size: textSize))
            transition.updateFrameAdditive(node: self.statusNode, frame: CGRect(origin: CGPoint(x: sideInset, y: verticalOrigin + verticalSpacing + textSize.height), size: statusSize))
            if let image = self.iconNode.image {
                let iconFrame = CGRect(origin: CGPoint(x: size.width - standardIconWidth - iconSideInset + floor((standardIconWidth - image.size.width) / 2.0), y: floor((size.height - image.size.height) / 2.0)), size: image.size)
                transition.updateFrame(node: self.iconNode, frame: iconFrame)
            }
            let bounds = CGRect(origin: CGPoint(), size: size)
            transition.updateFrame(node: self.backgroundNode, frame: bounds)
            transition.updateFrame(node: self.highlightedBackgroundNode, frame: bounds)
            transition.updateFrame(node: self.buttonNode, frame: bounds)
        })
    }

    func updateTheme(presentationData: PresentationData) {
        self.presentationData = presentationData
        self.applyTheme()
    }

    @objc private func buttonPressed() {
        self.performAction()
    }

    func canBeHighlighted() -> Bool {
        return true
    }

    func updateIsHighlighted(isHighlighted: Bool) {
        self.setIsHighlighted(isHighlighted)
    }

    private func setIsHighlighted(_ value: Bool) {
        self.highlightedBackgroundNode.alpha = value ? 1.0 : 0.0
    }

    func performAction() {
        guard let controller = self.getController() else {
            return
        }
        self.item.action(controller, self.item.timecode() ?? self.currentTimecode)
    }
}

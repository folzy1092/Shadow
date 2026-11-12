import Foundation
import UIKit
import Display
import MediaEditor
import TooltipUI
import ChatMediaSend

// Shadow: «отправить кружком» in 13.2's chat gallery editor, as the old gallery had it
// (TGMediaPickerGalleryInterfaceView `_roundButton`, SHADOW_AGENT_MAP §5e): a ring button above the
// mute button for a gallery video, and while it is on the preview is clipped to the circle that will be
// sent. The mark lives in `ChatMediaEditorItemStore.shadowRoundVideoIds`; the picker turns it into the
// VideoMessage preset when sending (MediaPickerUI `shadowApplyRoundVideoAdjustments`).

private let shadowRoundButtonSpacing: CGFloat = 10.0

private func shadowRoundVideoIcon(active: Bool) -> UIImage? {
    return generateImage(CGSize(width: 24.0, height: 24.0), rotatedContext: { size, context in
        context.clear(CGRect(origin: .zero, size: size))
        context.setStrokeColor(UIColor.white.cgColor)
        context.setFillColor(UIColor.white.cgColor)
        context.setLineWidth(2.0)
        context.strokeEllipse(in: CGRect(x: 3.0, y: 3.0, width: 18.0, height: 18.0))
        if active {
            context.fillEllipse(in: CGRect(x: 7.0, y: 7.0, width: 10.0, height: 10.0))
        }
    })
}

private let shadowRoundVideoIconOff = shadowRoundVideoIcon(active: false)
private let shadowRoundVideoIconOn = shadowRoundVideoIcon(active: true)

private let shadowRoundButtonBackground: UIImage? = generateImage(CGSize(width: chatMediaEditorMuteButtonSize, height: chatMediaEditorMuteButtonSize), rotatedContext: { size, context in
    context.clear(CGRect(origin: .zero, size: size))
    context.setFillColor(UIColor(white: 0.0, alpha: 0.5).cgColor)
    context.fillEllipse(in: CGRect(origin: .zero, size: size))
})

extension ChatMediaEditorScreen.Node {
    var shadowIsRoundButtonVisible: Bool {
        guard self.controller?.gallery != nil else {
            return false
        }
        return shadowRoundVideoButtonIsVisible(isGallery: self.isGallery, isVideo: self.subject.isVideo, isAnimation: self.pageModel.currentItem.isAnimation, isFilePreview: self.isFilePreview)
    }

    var shadowIsCurrentRoundVideo: Bool {
        guard let store = self.controller?.store else {
            return false
        }
        return store.shadowIsRoundVideo(self.pageModel.currentItem.uniqueId)
    }

    /// Called right after `updateMuteButton`: the round button sits above the mute button and is shown
    /// and hidden with it.
    func shadowUpdateRoundVideo(transition: ContainedViewLayoutTransition) {
        self.shadowUpdateRoundMask()

        guard self.shadowIsRoundButtonVisible, let muteButton = self.muteButton else {
            self.shadowRoundButton?.removeFromSuperview()
            self.shadowRoundButton = nil
            self.shadowDismissRoundTooltip()
            return
        }
        let frame = muteButton.frame.offsetBy(dx: 0.0, dy: -(muteButton.frame.height + shadowRoundButtonSpacing))
        let button: UIButton
        if let current = self.shadowRoundButton {
            button = current
        } else {
            button = UIButton(type: .custom)
            button.setBackgroundImage(shadowRoundButtonBackground, for: .normal)
            button.accessibilityLabel = "Кружок"
            button.addTarget(self, action: #selector(self.shadowRoundButtonPressed), for: .touchUpInside)
            self.shadowRoundButton = button
            self.view.insertSubview(button, aboveSubview: self.pagerView)
            button.frame = frame
            button.alpha = 0.0
        }
        let isRound = self.shadowIsCurrentRoundVideo
        button.setImage(isRound ? shadowRoundVideoIconOn : shadowRoundVideoIconOff, for: .normal)
        button.accessibilityTraits = isRound ? [.button, .selected] : .button
        transition.updateFrame(view: button, frame: frame)
        // Hidden exactly when the mute button is (scrubber not shown, a tool open, caption editing, keyboard, sending).
        let isHidden = !muteButton.isUserInteractionEnabled
        transition.updateAlpha(layer: button.layer, alpha: isHidden ? 0.0 : 1.0)
        button.isUserInteractionEnabled = !isHidden
        if isHidden {
            self.shadowDismissRoundTooltip()
        }
    }

    private func shadowUpdateRoundMask() {
        let isActive = self.shadowIsRoundButtonVisible && self.shadowIsCurrentRoundVideo && self.activeTool == nil
        if isActive {
            let bounds = self.previewContainerView.bounds
            let mask = self.shadowRoundMaskLayer ?? CAShapeLayer()
            mask.frame = bounds
            mask.path = UIBezierPath(ovalIn: shadowRoundVideoPreviewCircle(in: bounds)).cgPath
            if self.previewContainerView.layer.mask !== mask {
                self.previewContainerView.layer.mask = mask
            }
            self.shadowRoundMaskLayer = mask
        } else if let mask = self.shadowRoundMaskLayer {
            if self.previewContainerView.layer.mask === mask {
                self.previewContainerView.layer.mask = nil
            }
            self.shadowRoundMaskLayer = nil
        }
    }

    @objc func shadowRoundButtonPressed() {
        guard self.shadowIsRoundButtonVisible, self.activeTool == nil, !self.isSending, !self.isInvalidated, let store = self.controller?.store else {
            return
        }
        let uniqueId = self.pageModel.currentItem.uniqueId
        let isRound = !store.shadowIsRoundVideo(uniqueId)
        store.shadowSetRoundVideo(isRound, for: uniqueId)
        if isRound {
            // A round video keeps its sound, as in the old gallery.
            if self.mediaEditor.values.videoIsMuted {
                self.mediaEditor.setVideoIsMuted(false)
            }
            self.shadowPresentRoundTooltip()
        } else {
            self.shadowDismissRoundTooltip()
        }
        self.requestLayout(transition: .animated(duration: 0.2, curve: .easeInOut))
    }

    private func shadowPresentRoundTooltip() {
        guard let controller = self.controller, let button = self.shadowRoundButton, !controller.isDismissing, self.view.window != nil else {
            return
        }
        self.shadowDismissRoundTooltip()
        self.dismissMuteTooltip()
        var text = "Отправится кружком: квадрат по центру, до 1 минуты, без подписи."
        if shadowRoundVideoDropsEdits(self.mediaEditor.values) {
            text += " Рисунки, фильтры и поворот в кружок не попадут."
        }
        let sourceRect = button.convert(button.bounds, to: nil)
        let tooltipController = TooltipScreen(
            account: self.context.account,
            sharedContext: self.context.sharedContext,
            text: .plain(text: text),
            balancedTextLayout: true,
            style: .customBlur(UIColor(rgb: 0x18181a), 0.0),
            arrowStyle: .small,
            location: .point(sourceRect, .bottom),
            displayDuration: .default,
            inset: 16.0,
            cornerRadius: 10.0,
            shouldDismissOnTouch: { _, _ in
                return .dismiss(consume: false)
            }
        )
        self.shadowRoundTooltipController = tooltipController
        self.context.sharedContext.presentGlobalController(tooltipController, nil)
    }

    func shadowDismissRoundTooltip() {
        if let tooltipController = self.shadowRoundTooltipController {
            self.shadowRoundTooltipController = nil
            tooltipController.dismiss()
        }
    }
}

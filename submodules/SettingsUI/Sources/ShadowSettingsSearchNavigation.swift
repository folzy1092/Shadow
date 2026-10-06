import UIKit
import Display
import ItemListUI
import TelegramPresentationData

func shadowSettingsFocusIndex(stableIds: [Int32], target: ShadowSettingsSearchItem?) -> Int? {
    guard let target else { return nil }
    if let index = stableIds.firstIndex(of: target.entryId) { return index }
    // Dependent controls may be hidden. Focus the parent without toggling it.
    if let parent = target.parentEntryId { return stableIds.firstIndex(of: parent) }
    return nil
}

// The screen opens at the top; shadowSettingsInstallFocus then scrolls to the
// row smoothly, so the user sees where the setting lives.
func shadowSettingsInitialScroll(index: Int?) -> ListViewScrollToItem? {
    return nil
}

// Shadow: one soft pulse over the focused row — white on a dark theme, gray on a
// light one — so the row stands out without looking like a selection.
func shadowSettingsPulseColor(_ theme: PresentationTheme) -> UIColor {
    return theme.overallDarkAppearance ? UIColor(white: 1.0, alpha: 1.0) : UIColor(white: 0.45, alpha: 1.0)
}

func shadowSettingsInstallFocus(controller: ItemListController, index: @escaping () -> Int?, color: UIColor) {
    var started = false
    var highlighted = false
    let pulse: () -> Void = { [weak controller] in
        guard !highlighted, let controller, let index = index() else { return }
        controller.forEachItemNode { node in
            guard !highlighted, node.index == index else { return }
            highlighted = true
            let overlay = UIView(frame: node.bounds)
            overlay.backgroundColor = color.withAlphaComponent(0.28)
            overlay.isUserInteractionEnabled = false
            overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            overlay.layer.cornerRadius = 10.0
            overlay.alpha = 0.0
            node.view.addSubview(overlay)
            if UIAccessibility.isReduceMotionEnabled {
                overlay.alpha = 1.0
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak overlay] in
                    overlay?.removeFromSuperview()
                }
            } else {
                UIView.animate(withDuration: 0.35, delay: 0.0, options: [.curveEaseOut], animations: {
                    overlay.alpha = 1.0
                }, completion: { _ in
                    UIView.animate(withDuration: 0.9, delay: 0.15, options: [.curveEaseInOut], animations: {
                        overlay.alpha = 0.0
                    }, completion: { _ in
                        overlay.removeFromSuperview()
                    })
                })
            }
        }
    }
    let start: () -> Void = { [weak controller] in
        guard !started, let controller, controller.viewIfLoaded?.window != nil, let index = index() else { return }
        started = true
        controller.shadowScrollToItem(index: index, completion: {
            DispatchQueue.main.asyncAfter(deadline: .now() + (UIAccessibility.isReduceMotionEnabled ? 0.05 : 0.5)) {
                pulse()
            }
        })
    }
    let previous = controller.didAppear
    controller.didAppear = { [weak controller] animated in
        previous?(animated)
        controller?.afterLayout(start)
    }
    controller.visibleEntriesUpdated = { _ in
        if started && !highlighted {
            pulse()
        }
    }
}

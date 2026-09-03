import UIKit
import Display
import ItemListUI

func shadowSettingsFocusIndex(stableIds: [Int32], target: ShadowSettingsSearchItem?) -> Int? {
    guard let target else { return nil }
    if let index = stableIds.firstIndex(of: target.entryId) { return index }
    // Dependent controls may be hidden. Focus the parent without toggling it.
    if let parent = target.parentEntryId { return stableIds.firstIndex(of: parent) }
    return nil
}

func shadowSettingsInitialScroll(index: Int?) -> ListViewScrollToItem? {
    guard let index else { return nil }
    return ListViewScrollToItem(index: index, position: .top(8.0), animated: false, curve: .Default(duration: nil), directionHint: .Down)
}

func shadowSettingsInstallFocus(controller: ItemListController, index: @escaping () -> Int?, color: UIColor) {
    var highlighted = false
    let highlight: () -> Void = { [weak controller] in
        guard !highlighted, let controller, controller.viewIfLoaded?.window != nil,
              let index = index() else { return }
        controller.forEachItemNode { node in
            guard !highlighted, node.index == index else { return }
            highlighted = true
            let overlay = UIView(frame: node.bounds)
            overlay.backgroundColor = color.withAlphaComponent(0.16)
            overlay.isUserInteractionEnabled = false
            overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            overlay.layer.cornerRadius = 10.0
            node.view.addSubview(overlay)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak overlay] in
                guard let overlay else { return }
                if UIAccessibility.isReduceMotionEnabled {
                    overlay.removeFromSuperview()
                } else {
                    UIView.animate(withDuration: 0.2, animations: { overlay.alpha = 0.0 }, completion: { _ in overlay.removeFromSuperview() })
                }
            }
        }
    }
    controller.didAppear = { [weak controller] _ in controller?.afterLayout(highlight) }
    controller.visibleEntriesUpdated = { _ in highlight() }
}

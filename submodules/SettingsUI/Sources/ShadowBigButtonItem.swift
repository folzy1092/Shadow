import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import SolidRoundedButtonNode

// Shadow: a full-width rounded button inside a settings list ("Проверить
// обновления", "Скачать IPA", the self-update actions). The title never
// changes with state; status text goes into a separate row below.
final class ShadowBigButtonItem: ListViewItem, ItemListItem {
    enum Style {
        // Accent fill: the main action.
        case filled
        // List background, accent title.
        case plain
        // List background, red title.
        case destructive
    }

    let presentationData: ItemListPresentationData
    let title: String
    let enabled: Bool
    let style: Style
    let sectionId: ItemListSectionId
    let action: () -> Void

    init(presentationData: ItemListPresentationData, title: String, enabled: Bool, style: Style = .filled, sectionId: ItemListSectionId, action: @escaping () -> Void) {
        self.presentationData = presentationData
        self.title = title
        self.enabled = enabled
        self.style = style
        self.sectionId = sectionId
        self.action = action
    }

    let selectable = false

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = ShadowBigButtonItemNode()
            let (layout, apply) = node.asyncLayout()(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            Queue.mainQueue().async {
                completion(node, {
                    return (nil, { _ in apply() })
                })
            }
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, previousItem: ListViewItem?, nextItem: ListViewItem?, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? ShadowBigButtonItemNode {
                let makeLayout = nodeValue.asyncLayout()
                async {
                    let (layout, apply) = makeLayout(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
                    Queue.mainQueue().async {
                        completion(layout, { _ in
                            apply()
                        })
                    }
                }
            }
        }
    }
}

private final class ShadowBigButtonItemNode: ListViewItemNode, ItemListItemNode {
    private var buttonNode: SolidRoundedButtonNode?
    private var item: ShadowBigButtonItem?

    var tag: ItemListItemTag? {
        return nil
    }

    override var canBeSelected: Bool {
        return false
    }

    init() {
        super.init(layerBacked: false)
    }

    func asyncLayout() -> (_ item: ShadowBigButtonItem, _ params: ListViewItemLayoutParams, _ neighbors: ItemListNeighbors) -> (ListViewItemNodeLayout, () -> Void) {
        return { item, params, neighbors in
            let buttonHeight: CGFloat = 50.0
            let verticalInset: CGFloat = 6.0
            let contentSize = CGSize(width: params.width, height: buttonHeight + verticalInset * 2.0)
            var insets = itemListNeighborsGroupedInsets(neighbors, params)
            insets.top = min(insets.top, 12.0)
            insets.bottom = 0.0
            let layout = ListViewItemNodeLayout(contentSize: contentSize, insets: insets)

            return (layout, { [weak self] in
                guard let self else {
                    return
                }
                self.item = item
                let theme = item.presentationData.theme
                let buttonTheme: SolidRoundedButtonTheme
                switch item.style {
                case .filled:
                    buttonTheme = SolidRoundedButtonTheme(backgroundColor: theme.list.itemCheckColors.fillColor, foregroundColor: theme.list.itemCheckColors.foregroundColor)
                case .plain:
                    buttonTheme = SolidRoundedButtonTheme(backgroundColor: theme.list.itemBlocksBackgroundColor, foregroundColor: theme.list.itemAccentColor)
                case .destructive:
                    buttonTheme = SolidRoundedButtonTheme(backgroundColor: theme.list.itemBlocksBackgroundColor, foregroundColor: theme.list.itemDestructiveColor)
                }
                let buttonNode: SolidRoundedButtonNode
                if let current = self.buttonNode {
                    buttonNode = current
                    buttonNode.updateTheme(buttonTheme)
                } else {
                    buttonNode = SolidRoundedButtonNode(theme: buttonTheme, height: buttonHeight, cornerRadius: 12.0)
                    self.buttonNode = buttonNode
                    self.addSubnode(buttonNode)
                }
                buttonNode.title = item.title
                buttonNode.isEnabled = item.enabled
                buttonNode.alpha = item.enabled ? 1.0 : 0.6
                buttonNode.pressed = { [weak self] in
                    guard let item = self?.item, item.enabled else {
                        return
                    }
                    item.action()
                }
                let sideInset: CGFloat = 16.0
                let width = params.width - params.leftInset - params.rightInset - sideInset * 2.0
                let height = buttonNode.updateLayout(width: width, transition: .immediate)
                buttonNode.frame = CGRect(x: params.leftInset + sideInset, y: verticalInset, width: width, height: height)
            })
        }
    }

    override func animateInsertion(_ currentTimestamp: Double, duration: Double, options: ListViewItemAnimationOptions) {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.4)
    }

    override func animateRemoved(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.15, removeOnCompletion: false)
    }
}

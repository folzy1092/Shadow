import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI

// Shadow: a status line with a progress bar under it ("Загрузка IPA · 45%").
// progress nil = indeterminate step (the bar is hidden).
final class ShadowProgressItem: ListViewItem, ItemListItem {
    let presentationData: ItemListPresentationData
    let title: String
    let detail: String
    let progress: Double?
    let sectionId: ItemListSectionId

    init(presentationData: ItemListPresentationData, title: String, detail: String, progress: Double?, sectionId: ItemListSectionId) {
        self.presentationData = presentationData
        self.title = title
        self.detail = detail
        self.progress = progress
        self.sectionId = sectionId
    }

    let selectable = false

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = ShadowProgressItemNode()
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
            if let nodeValue = node() as? ShadowProgressItemNode {
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

private final class ShadowProgressItemNode: ListViewItemNode, ItemListItemNode {
    private let titleNode = ImmediateTextNode()
    private let detailNode = ImmediateTextNode()
    private let trackNode = ASDisplayNode()
    private let fillNode = ASDisplayNode()

    var tag: ItemListItemTag? {
        return nil
    }

    override var canBeSelected: Bool {
        return false
    }

    init() {
        super.init(layerBacked: false)
        self.titleNode.maximumNumberOfLines = 0
        self.detailNode.maximumNumberOfLines = 0
        self.trackNode.cornerRadius = 3.0
        self.trackNode.clipsToBounds = true
        self.fillNode.cornerRadius = 3.0
        self.addSubnode(self.titleNode)
        self.addSubnode(self.detailNode)
        self.addSubnode(self.trackNode)
        self.trackNode.addSubnode(self.fillNode)
    }

    func asyncLayout() -> (_ item: ShadowProgressItem, _ params: ListViewItemLayoutParams, _ neighbors: ItemListNeighbors) -> (ListViewItemNodeLayout, () -> Void) {
        return { item, params, neighbors in
            let sideInset: CGFloat = 16.0
            let width = params.width - params.leftInset - params.rightInset - sideInset * 2.0
            let theme = item.presentationData.theme
            let titleFont = Font.medium(floor(item.presentationData.fontSize.itemListBaseFontSize * 15.0 / 17.0))
            let detailFont = Font.regular(floor(item.presentationData.fontSize.itemListBaseFontSize * 13.0 / 17.0))

            // Measured off the main thread; the text nodes are touched only in apply.
            let title = NSAttributedString(string: item.title, font: titleFont, textColor: theme.list.itemPrimaryTextColor)
            let detail = NSAttributedString(string: item.detail, font: detailFont, textColor: theme.list.freeTextColor)
            func measure(_ text: NSAttributedString) -> CGSize {
                if text.length == 0 {
                    return CGSize()
                }
                let rect = text.boundingRect(with: CGSize(width: width, height: 1000.0), options: [.usesLineFragmentOrigin], context: nil)
                return CGSize(width: ceil(rect.width), height: ceil(rect.height))
            }
            let titleSize = measure(title)
            let detailSize = measure(detail)

            let barHeight: CGFloat = 6.0
            var height: CGFloat = 8.0 + titleSize.height
            if item.progress != nil {
                height += 8.0 + barHeight
            }
            if !item.detail.isEmpty {
                height += 6.0 + detailSize.height
            }
            height += 8.0

            var insets = itemListNeighborsGroupedInsets(neighbors, params)
            insets.top = min(insets.top, 8.0)
            insets.bottom = 0.0
            let layout = ListViewItemNodeLayout(contentSize: CGSize(width: params.width, height: height), insets: insets)

            return (layout, { [weak self] in
                guard let self else {
                    return
                }
                let x = params.leftInset + sideInset
                var y: CGFloat = 8.0
                self.titleNode.attributedText = title
                self.detailNode.attributedText = detail
                let _ = self.titleNode.updateLayout(CGSize(width: width, height: 1000.0))
                let _ = self.detailNode.updateLayout(CGSize(width: width, height: 1000.0))
                self.titleNode.frame = CGRect(origin: CGPoint(x: x, y: y), size: titleSize)
                y += titleSize.height
                if let progress = item.progress {
                    y += 8.0
                    self.trackNode.isHidden = false
                    self.trackNode.backgroundColor = theme.list.itemPlainSeparatorColor
                    self.fillNode.backgroundColor = theme.list.itemAccentColor
                    self.trackNode.frame = CGRect(x: x, y: y, width: width, height: barHeight)
                    let fraction = CGFloat(max(0.0, min(1.0, progress)))
                    self.fillNode.frame = CGRect(x: 0.0, y: 0.0, width: max(barHeight, width * fraction), height: barHeight)
                    y += barHeight
                } else {
                    self.trackNode.isHidden = true
                }
                if !item.detail.isEmpty {
                    y += 6.0
                    self.detailNode.isHidden = false
                    self.detailNode.frame = CGRect(origin: CGPoint(x: x, y: y), size: detailSize)
                } else {
                    self.detailNode.isHidden = true
                }
            })
        }
    }
}

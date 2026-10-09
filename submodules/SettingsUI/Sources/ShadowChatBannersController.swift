import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext
import AvatarNode
import ChatListUI
import LocalizedPeerData

// Shadow: «Фоны чатов» settings (Кастомизация → Чаты и звонки → Фото и чаты).
// The list of photos; a photo opens its editor: live preview of a chat row with
// dimming and vertical position, the chats it is bound to, delete. Model and
// storage — TelegramCore ShadowChatBanners.swift / ShadowChatBannerStore.swift,
// drawing in the chat list — ChatListUI ShadowChatBannerRendering.swift.

// The account's photos, live.
func shadowChatBannersIndex(context: AccountContext) -> Signal<ShadowChatBannersIndex, NoError> {
    let basePath = context.account.postbox.mediaBox.basePath
    return Signal { subscriber in
        subscriber.putNext(ShadowChatBannerStore.shared.index(basePath: basePath))
        let observer = NotificationCenter.default.addObserver(forName: ShadowChatBannerStore.didChangeNotification, object: nil, queue: .main, using: { notification in
            if let changed = notification.userInfo?["basePath"] as? String, changed != basePath {
                return
            }
            subscriber.putNext(ShadowChatBannerStore.shared.index(basePath: basePath))
        })
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

func shadowChatBannersCount(context: AccountContext) -> Signal<Int, NoError> {
    return shadowChatBannersIndex(context: context)
    |> map { $0.banners.count }
    |> distinctUntilChanged
}

private func shadowChatBannerChatsLabel(_ count: Int) -> String {
    if count == 0 {
        return "Нет чатов"
    }
    let a = count % 100
    let b = a % 10
    if a > 10 && a < 20 {
        return "\(count) чатов"
    } else if b == 1 {
        return "\(count) чат"
    } else if b > 1 && b < 5 {
        return "\(count) чата"
    } else {
        return "\(count) чатов"
    }
}

// Photos from the camera roll can be huge: keep at most 2000 px on the long side.
private func shadowChatBannerJpegData(_ image: UIImage) -> Data? {
    let maxSide: CGFloat = 2000.0
    let size = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    var target = size
    if max(size.width, size.height) > maxSide {
        let factor = maxSide / max(size.width, size.height)
        target = CGSize(width: floor(size.width * factor), height: floor(size.height * factor))
    }
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1.0
    format.opaque = true
    let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
        image.draw(in: CGRect(origin: CGPoint(), size: target))
    }
    return rendered.jpegData(compressionQuality: 0.9)
}

private func shadowChatBannerThumbnail(_ image: UIImage) -> UIImage {
    let size = CGSize(width: 44.0, height: 30.0)
    let format = UIGraphicsImageRendererFormat()
    format.opaque = false
    return UIGraphicsImageRenderer(size: size, format: format).image { _ in
        UIBezierPath(roundedRect: CGRect(origin: CGPoint(), size: size), cornerRadius: 6.0).addClip()
        let aspect = image.size.width / max(1.0, image.size.height)
        var rect = CGRect(origin: CGPoint(), size: size)
        if aspect > size.width / size.height {
            let width = size.height * aspect
            rect = CGRect(x: (size.width - width) / 2.0, y: 0.0, width: width, height: size.height)
        } else {
            let height = size.width / aspect
            rect = CGRect(x: 0.0, y: (size.height - height) / 2.0, width: size.width, height: height)
        }
        image.draw(in: rect)
    }
}

private func shadowPresentChatBannerPicker(from controller: ViewController?, context: AccountContext, completion: @escaping (ShadowChatBanner) -> Void) {
    guard let controller else {
        return
    }
    let picker = UIImagePickerController()
    picker.sourceType = .photoLibrary
    picker.mediaTypes = ["public.image"]
    let delegate = BannerImagePickerDelegate(completion: { image in
        guard let image, let data = shadowChatBannerJpegData(image) else {
            return
        }
        if let banner = ShadowChatBannerStore.shared.add(basePath: context.account.postbox.mediaBox.basePath, jpegData: data) {
            completion(banner)
        }
    })
    delegate.retainSelf()
    picker.delegate = delegate
    controller.view.window?.rootViewController?.present(picker, animated: true)
}

// MARK: - List of photos

private final class ShadowChatBannersArguments {
    let open: (String) -> Void
    let add: () -> Void

    init(open: @escaping (String) -> Void, add: @escaping () -> Void) {
        self.open = open
        self.add = add
    }
}

private enum ShadowChatBannersEntry: ItemListNodeEntry {
    case info
    case photo(index: Int, id: String, thumbnail: UIImage?, chats: Int)
    case add
    case footer

    var section: ItemListSectionId {
        switch self {
        case .info:
            return 0
        case .photo, .add, .footer:
            return 1
        }
    }

    var stableId: String {
        switch self {
        case .info: return "info"
        case let .photo(_, id, _, _): return "photo-" + id
        case .add: return "add"
        case .footer: return "footer"
        }
    }

    private var sortIndex: Int {
        switch self {
        case .info: return 0
        case let .photo(index, _, _, _): return 1 + index
        case .add: return 100000
        case .footer: return 100001
        }
    }

    static func ==(lhs: ShadowChatBannersEntry, rhs: ShadowChatBannersEntry) -> Bool {
        switch lhs {
        case .info:
            if case .info = rhs { return true } else { return false }
        case let .photo(index, id, thumbnail, chats):
            if case let .photo(rhsIndex, rhsId, rhsThumbnail, rhsChats) = rhs {
                return index == rhsIndex && id == rhsId && thumbnail === rhsThumbnail && chats == rhsChats
            } else {
                return false
            }
        case .add:
            if case .add = rhs { return true } else { return false }
        case .footer:
            if case .footer = rhs { return true } else { return false }
        }
    }

    static func <(lhs: ShadowChatBannersEntry, rhs: ShadowChatBannersEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ShadowChatBannersArguments
        switch self {
        case .info:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Своё фото под строкой чата в списке — во всех папках и в архиве. У каждого фото свои чаты, затемнение и положение; цвет текста подстраивается под фото сам. Фото хранятся только на этом устройстве."), sectionId: self.section)
        case let .photo(index, id, thumbnail, chats):
            return ItemListDisclosureItem(presentationData: presentationData, icon: thumbnail, title: "Фото \(index + 1)", label: shadowChatBannerChatsLabel(chats), labelStyle: .detailText, sectionId: self.section, style: .blocks, action: {
                arguments.open(id)
            })
        case .add:
            return ItemListActionItem(presentationData: presentationData, title: "Загрузить фото", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.add()
            })
        case .footer:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Чат может быть привязан только к одному фото: если выбрать его для другого фото, он переедет туда."), sectionId: self.section)
        }
    }
}

public func shadowChatBannersController(context: AccountContext) -> ViewController {
    let basePath = context.account.postbox.mediaBox.basePath
    var pushImpl: ((ViewController) -> Void)?
    var addImpl: (() -> Void)?
    // Thumbnails by photo id (a photo's file never changes).
    var thumbnails: [String: UIImage] = [:]

    let arguments = ShadowChatBannersArguments(open: { id in
        pushImpl?(shadowChatBannerEditorController(context: context, bannerId: id))
    }, add: {
        addImpl?()
    })

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, shadowChatBannersIndex(context: context))
    |> map { presentationData, index -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [ShadowChatBannersEntry] = [.info]
        for (i, banner) in index.banners.enumerated() {
            let thumbnailKey = banner.id + (banner.mirrored ? "|m" : "")
            var thumbnail = thumbnails[thumbnailKey]
            if thumbnail == nil, let image = ShadowChatBannerImageCache.shared.image(path: ShadowChatBannerStore.shared.imagePath(basePath: basePath, id: banner.id)) {
                let made = shadowChatBannerThumbnail(image.image(mirrored: banner.mirrored))
                thumbnails[thumbnailKey] = made
                thumbnail = made
            }
            entries.append(.photo(index: i, id: banner.id, thumbnail: thumbnail, chats: banner.peerIds.count))
        }
        entries.append(.add)
        entries.append(.footer)
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Фоны чатов"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushImpl = { [weak controller] c in
        controller?.push(c)
    }
    addImpl = { [weak controller] in
        shadowPresentChatBannerPicker(from: controller, context: context, completion: { banner in
            pushImpl?(shadowChatBannerEditorController(context: context, bannerId: banner.id))
        })
    }
    return controller
}

// MARK: - Editor of one photo

private final class ShadowChatBannerEditorArguments {
    let context: AccountContext
    let commit: (Double, Double) -> Void
    let chooseChats: () -> Void
    let delete: () -> Void
    var setMirrored: (Bool) -> Void = { _ in }

    init(context: AccountContext, commit: @escaping (Double, Double) -> Void, chooseChats: @escaping () -> Void, delete: @escaping () -> Void) {
        self.context = context
        self.commit = commit
        self.chooseChats = chooseChats
        self.delete = delete
    }
}

private enum ShadowChatBannerEditorEntry: ItemListNodeEntry {
    case preview(image: ShadowChatBannerImage, banner: ShadowChatBanner, peer: EnginePeer?)
    case mirrored(Bool)
    case chats(count: Int)
    case chatsFooter(String)
    case delete

    var section: ItemListSectionId {
        switch self {
        case .preview, .mirrored: return 0
        case .chats, .chatsFooter: return 1
        case .delete: return 2
        }
    }

    var stableId: Int {
        switch self {
        case .preview: return 0
        case .chats: return 1
        case .chatsFooter: return 2
        case .delete: return 3
        case .mirrored: return 4
        }
    }

    private var sortIndex: Int {
        switch self {
        case .preview: return 0
        case .mirrored: return 1
        case .chats: return 2
        case .chatsFooter: return 3
        case .delete: return 4
        }
    }

    static func ==(lhs: ShadowChatBannerEditorEntry, rhs: ShadowChatBannerEditorEntry) -> Bool {
        switch lhs {
        case let .preview(image, banner, peer):
            if case let .preview(rhsImage, rhsBanner, rhsPeer) = rhs {
                return image === rhsImage && banner == rhsBanner && peer == rhsPeer
            } else {
                return false
            }
        case let .mirrored(value):
            if case let .mirrored(rhsValue) = rhs { return value == rhsValue } else { return false }
        case let .chats(count):
            if case let .chats(rhsCount) = rhs { return count == rhsCount } else { return false }
        case let .chatsFooter(text):
            if case let .chatsFooter(rhsText) = rhs { return text == rhsText } else { return false }
        case .delete:
            if case .delete = rhs { return true } else { return false }
        }
    }

    static func <(lhs: ShadowChatBannerEditorEntry, rhs: ShadowChatBannerEditorEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ShadowChatBannerEditorArguments
        switch self {
        case let .preview(image, banner, peer):
            return ShadowChatBannerPreviewItem(presentationData: presentationData, context: arguments.context, image: image, banner: banner, peer: peer, sectionId: self.section, commit: arguments.commit)
        case let .mirrored(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Отразить по горизонтали", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.setMirrored(value)
            })
        case let .chats(count):
            return ItemListDisclosureItem(presentationData: presentationData, title: "Чаты с этим фоном", label: count == 0 ? "Выбрать" : shadowChatBannerChatsLabel(count), labelStyle: .detailText, sectionId: self.section, style: .blocks, action: {
                arguments.chooseChats()
            })
        case let .chatsFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case .delete:
            return ItemListActionItem(presentationData: presentationData, title: "Удалить фото", kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.delete()
            })
        }
    }
}

func shadowChatBannerEditorController(context: AccountContext, bannerId: String) -> ViewController {
    let basePath = context.account.postbox.mediaBox.basePath
    var presentImpl: ((ViewController) -> Void)?
    var pushImpl: ((ViewController) -> Void)?
    var dismissImpl: (() -> Void)?

    let arguments = ShadowChatBannerEditorArguments(context: context, commit: { dim, offset in
        guard var banner = ShadowChatBannerStore.shared.index(basePath: basePath).banner(id: bannerId) else {
            return
        }
        if banner.dim == dim && banner.offset == offset {
            return
        }
        banner.dim = dim
        banner.offset = offset
        ShadowChatBannerStore.shared.update(basePath: basePath, banner: banner)
    }, chooseChats: {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let current = ShadowChatBannerStore.shared.index(basePath: basePath).banner(id: bannerId)?.peerIds ?? []
        let picker = context.sharedContext.makeContactMultiselectionController(ContactMultiselectionControllerParams(context: context, mode: .chatSelection(ContactMultiselectionControllerMode.ChatSelection(
            title: "Чаты с этим фоном",
            searchPlaceholder: presentationData.strings.ChatListFilter_AddChatsSearchPlaceholder,
            selectedChats: Set(current.map { EnginePeer.Id($0) }),
            additionalCategories: nil,
            chatListFilters: nil
        )), filters: [], alwaysEnabled: true))
        picker.navigationPresentation = .modal
        let _ = (picker.result
        |> take(1)
        |> deliverOnMainQueue).start(next: { [weak picker] result in
            guard case let .result(peerIds, _) = result else {
                picker?.dismiss()
                return
            }
            var selected: [Int64] = []
            for peerId in peerIds {
                if case let .peer(id) = peerId {
                    selected.append(id.toInt64())
                }
            }
            ShadowChatBannerStore.shared.setPeers(basePath: basePath, bannerId: bannerId, peerIds: selected)
            picker?.dismiss()
        })
        pushImpl?(picker)
    }, delete: {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let sheet = ActionSheetController(presentationData: presentationData)
        sheet.setItemGroups([
            ActionSheetItemGroup(items: [
                ActionSheetTextItem(title: "Фото пропадёт со строк всех привязанных чатов.", parseMarkdown: false),
                ActionSheetButtonItem(title: "Удалить фото", color: .destructive, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                    let path = ShadowChatBannerStore.shared.imagePath(basePath: basePath, id: bannerId)
                    ShadowChatBannerStore.shared.remove(basePath: basePath, id: bannerId)
                    ShadowChatBannerImageCache.shared.remove(path: path)
                    dismissImpl?()
                })
            ]),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, action: { [weak sheet] in
                sheet?.dismissAnimated()
            })])
        ])
        presentImpl?(sheet)
    })

    arguments.setMirrored = { value in
        guard var banner = ShadowChatBannerStore.shared.index(basePath: basePath).banner(id: bannerId), banner.mirrored != value else {
            return
        }
        banner.mirrored = value
        ShadowChatBannerStore.shared.update(basePath: basePath, banner: banner)
    }

    let accountPeer: Signal<EnginePeer?, NoError> = context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: context.account.peerId))

    let chatNames: Signal<(ShadowChatBannersIndex, [String]), NoError> = shadowChatBannersIndex(context: context)
    |> mapToSignal { index -> Signal<(ShadowChatBannersIndex, [String]), NoError> in
        let ids = (index.banner(id: bannerId)?.peerIds ?? []).map { EnginePeer.Id($0) }
        if ids.isEmpty {
            return .single((index, []))
        }
        return context.engine.data.get(EngineDataMap(ids.map(TelegramEngine.EngineData.Item.Peer.Peer.init)))
        |> map { peers -> (ShadowChatBannersIndex, [String]) in
            let strings = context.sharedContext.currentPresentationData.with { $0 }.strings
            var names: [String] = []
            for id in ids {
                if let maybePeer = peers[id], let peer = maybePeer {
                    names.append(id == context.account.peerId ? "Избранное" : peer.displayTitle(strings: strings, displayOrder: .firstLast))
                }
            }
            return (index, names)
        }
    }

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, chatNames, accountPeer)
    |> map { presentationData, chatNames, accountPeer -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let (index, names) = chatNames
        var entries: [ShadowChatBannerEditorEntry] = []
        if let banner = index.banner(id: bannerId), let image = ShadowChatBannerImageCache.shared.image(path: ShadowChatBannerStore.shared.imagePath(basePath: basePath, id: bannerId)) {
            entries.append(.preview(image: image, banner: banner, peer: accountPeer))
            entries.append(.mirrored(banner.mirrored))
            entries.append(.chats(count: banner.peerIds.count))
            entries.append(.chatsFooter(names.isEmpty ? "Выберите чаты, под строкой которых будет это фото." : names.joined(separator: ", ")))
            entries.append(.delete)
        }
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Фон"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    pushImpl = { [weak controller] c in
        controller?.push(c)
    }
    dismissImpl = { [weak controller] in
        let _ = controller?.navigationController?.popViewController(animated: true)
    }
    return controller
}

// MARK: - Preview with sliders

// A chat row as it will look in the list («Folzy · Привет! Как тебе фон? 👀»)
// over the photo, then «Затемнение» and «Положение». Sliders and dragging the
// photo on the preview update it at once; the store is written when the finger
// lifts (every write re-renders the chat list).
private final class ShadowChatBannerPreviewItem: ListViewItem, ItemListItem {
    let presentationData: ItemListPresentationData
    let context: AccountContext
    let image: ShadowChatBannerImage
    let banner: ShadowChatBanner
    let peer: EnginePeer?
    let sectionId: ItemListSectionId
    let commit: (Double, Double) -> Void

    init(presentationData: ItemListPresentationData, context: AccountContext, image: ShadowChatBannerImage, banner: ShadowChatBanner, peer: EnginePeer?, sectionId: ItemListSectionId, commit: @escaping (Double, Double) -> Void) {
        self.presentationData = presentationData
        self.context = context
        self.image = image
        self.banner = banner
        self.peer = peer
        self.sectionId = sectionId
        self.commit = commit
    }

    let selectable = false

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = ShadowChatBannerPreviewItemNode()
            let (layout, apply) = node.asyncLayout()(self, params)
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
            if let nodeValue = node() as? ShadowChatBannerPreviewItemNode {
                let makeLayout = nodeValue.asyncLayout()
                async {
                    let (layout, apply) = makeLayout(self, params)
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

private final class ShadowChatBannerPreviewItemNode: ListViewItemNode, ItemListItemNode {
    private static let rowHeight: CGFloat = 76.0
    private static let sideInset: CGFloat = 16.0

    // The node is created off the main thread: UIKit views are made in didLoad.
    private let avatarNode = AvatarNode(font: avatarPlaceholderFont(size: 26.0))
    private var cardView: UIView!
    private var photoLayer: CALayer!
    private var dimLayer: CALayer!
    private var titleLabel: UILabel!
    private var textLabel: UILabel!
    private var timeLabel: UILabel!
    private var dimTitleLabel: UILabel!
    private var dimValueLabel: UILabel!
    private var dimSlider: UISlider!
    private var offsetTitleLabel: UILabel!
    private var offsetSlider: UISlider!
    private var hintLabel: UILabel!

    private var item: ShadowChatBannerPreviewItem?
    private var dim: Double = ShadowChatBanners.defaultDim
    private var offset: Double = 0.5
    private var isEditing = false
    private var panStartOffset: Double = 0.5
    private var cardSize = CGSize()
    private var avatarPeerId: EnginePeer.Id?

    var tag: ItemListItemTag? {
        return nil
    }

    override var canBeSelected: Bool {
        return false
    }

    init() {
        super.init(layerBacked: false)
    }

    override func didLoad() {
        super.didLoad()

        self.cardView = UIView()
        self.photoLayer = CALayer()
        self.dimLayer = CALayer()
        self.titleLabel = UILabel()
        self.textLabel = UILabel()
        self.timeLabel = UILabel()
        self.dimTitleLabel = UILabel()
        self.dimValueLabel = UILabel()
        self.dimSlider = UISlider()
        self.offsetTitleLabel = UILabel()
        self.offsetSlider = UISlider()
        self.hintLabel = UILabel()

        self.cardView.clipsToBounds = true
        self.cardView.layer.cornerRadius = 12.0
        self.photoLayer.contentsGravity = .resize
        self.photoLayer.masksToBounds = true
        self.dimLayer.backgroundColor = UIColor.black.cgColor
        self.cardView.layer.addSublayer(self.photoLayer)
        self.cardView.layer.addSublayer(self.dimLayer)
        self.cardView.addSubview(self.avatarNode.view)
        self.titleLabel.font = Font.medium(16.0)
        self.textLabel.font = Font.regular(15.0)
        self.textLabel.numberOfLines = 2
        self.timeLabel.font = Font.regular(14.0)
        self.timeLabel.textAlignment = .right
        self.cardView.addSubview(self.titleLabel)
        self.cardView.addSubview(self.textLabel)
        self.cardView.addSubview(self.timeLabel)
        self.view.addSubview(self.cardView)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(self.panGesture(_:)))
        self.cardView.addGestureRecognizer(pan)

        self.dimTitleLabel.text = "Затемнение"
        self.offsetTitleLabel.text = "Положение фото"
        self.hintLabel.text = "Фото можно двигать пальцем прямо по превью."
        self.hintLabel.numberOfLines = 0
        let labels: [UILabel] = [self.dimTitleLabel, self.dimValueLabel, self.offsetTitleLabel]
        for label in labels {
            label.font = Font.regular(15.0)
        }
        self.hintLabel.font = Font.regular(13.0)
        self.dimValueLabel.textAlignment = .right
        self.dimSlider.minimumValue = 0.0
        self.dimSlider.maximumValue = Float(ShadowChatBanners.maxDim)
        self.offsetSlider.minimumValue = 0.0
        self.offsetSlider.maximumValue = 1.0
        let sliders: [UISlider] = [self.dimSlider, self.offsetSlider]
        for slider in sliders {
            slider.addTarget(self, action: #selector(self.sliderBegan), for: .touchDown)
            slider.addTarget(self, action: #selector(self.sliderChanged), for: .valueChanged)
            slider.addTarget(self, action: #selector(self.sliderEnded), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        }
        let controls: [UIView] = [self.dimTitleLabel, self.dimValueLabel, self.dimSlider, self.offsetTitleLabel, self.offsetSlider, self.hintLabel]
        for view in controls {
            self.view.addSubview(view)
        }
    }

    func asyncLayout() -> (_ item: ShadowChatBannerPreviewItem, _ params: ListViewItemLayoutParams) -> (ListViewItemNodeLayout, () -> Void) {
        return { item, params in
            let height: CGFloat = 8.0 + ShadowChatBannerPreviewItemNode.rowHeight + 16.0 + 24.0 + 34.0 + 10.0 + 24.0 + 34.0 + 6.0 + 36.0
            let layout = ListViewItemNodeLayout(contentSize: CGSize(width: params.width, height: height), insets: UIEdgeInsets(top: 8.0, left: 0.0, bottom: 0.0, right: 0.0))
            return (layout, { [weak self] in
                self?.apply(item: item, params: params)
            })
        }
    }

    private func apply(item: ShadowChatBannerPreviewItem, params: ListViewItemLayoutParams) {
        // Loads the view (didLoad makes the UIKit parts) if it is not yet.
        let _ = self.view
        let previous = self.item
        self.item = item
        if !self.isEditing {
            self.dim = item.banner.dim
            self.offset = item.banner.offset
        }
        let theme = item.presentationData.theme
        let left = params.leftInset + ShadowChatBannerPreviewItemNode.sideInset
        let width = params.width - params.leftInset - params.rightInset - ShadowChatBannerPreviewItemNode.sideInset * 2.0
        var y: CGFloat = 8.0
        self.cardSize = CGSize(width: width, height: ShadowChatBannerPreviewItemNode.rowHeight)
        self.cardView.frame = CGRect(origin: CGPoint(x: left, y: y), size: self.cardSize)
        self.cardView.backgroundColor = theme.list.plainBackgroundColor
        y += ShadowChatBannerPreviewItemNode.rowHeight + 16.0

        let labelColor = theme.list.itemPrimaryTextColor
        self.dimTitleLabel.textColor = labelColor
        self.dimValueLabel.textColor = theme.list.itemSecondaryTextColor
        self.offsetTitleLabel.textColor = labelColor
        self.hintLabel.textColor = theme.list.freeTextColor
        let sliders: [UISlider] = [self.dimSlider, self.offsetSlider]
        for slider in sliders {
            slider.minimumTrackTintColor = theme.list.itemAccentColor
        }

        self.dimTitleLabel.frame = CGRect(x: left, y: y, width: width * 0.6, height: 24.0)
        self.dimValueLabel.frame = CGRect(x: left + width * 0.6, y: y, width: width * 0.4, height: 24.0)
        y += 24.0
        self.dimSlider.frame = CGRect(x: left, y: y, width: width, height: 34.0)
        y += 34.0 + 10.0
        self.offsetTitleLabel.frame = CGRect(x: left, y: y, width: width, height: 24.0)
        y += 24.0
        self.offsetSlider.frame = CGRect(x: left, y: y, width: width, height: 34.0)
        y += 34.0 + 6.0
        self.hintLabel.frame = CGRect(x: left, y: y, width: width, height: 36.0)
        // A photo wider than the row has no vertical position to choose.
        let movable = item.image.aspect < Double(self.cardSize.width / self.cardSize.height)
        self.offsetSlider.isEnabled = movable
        self.offsetTitleLabel.alpha = movable ? 1.0 : 0.5
        self.hintLabel.isHidden = !movable

        if previous?.image !== item.image || previous?.banner.mirrored != item.banner.mirrored {
            self.photoLayer.contents = item.image.image(mirrored: item.banner.mirrored).cgImage
        }
        let peerId = item.peer?.id
        if let peer = item.peer, self.avatarPeerId != peerId {
            self.avatarPeerId = peerId
            self.avatarNode.setPeer(context: item.context, theme: theme, peer: peer, synchronousLoad: false, displayDimensions: CGSize(width: 60.0, height: 60.0))
        }
        let name = item.peer?.compactDisplayTitle ?? "Folzy"
        self.titleLabel.text = name
        self.textLabel.text = "Привет! Как тебе фон? 👀"
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        self.timeLabel.text = formatter.string(from: Date())
        self.updatePreview()
    }

    private func updatePreview() {
        guard self.isNodeLoaded, let item = self.item, self.cardSize.width > 0.0 else {
            return
        }
        let size = self.cardSize
        let rect = ShadowChatBanners.visibleRect(imageAspect: item.image.aspect, rowAspect: Double(size.width / size.height), offset: self.offset)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.photoLayer.frame = CGRect(origin: CGPoint(), size: size)
        self.photoLayer.contentsRect = CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
        self.dimLayer.frame = CGRect(origin: CGPoint(), size: size)
        self.dimLayer.opacity = Float(self.dim)
        CATransaction.commit()

        let avatarSize: CGFloat = 60.0
        self.avatarNode.frame = CGRect(x: 10.0, y: floor((size.height - avatarSize) / 2.0), width: avatarSize, height: avatarSize)
        let textLeft: CGFloat = 10.0 + avatarSize + 10.0
        let timeWidth: CGFloat = 56.0
        self.titleLabel.frame = CGRect(x: textLeft, y: 9.0, width: size.width - textLeft - timeWidth - 10.0, height: 22.0)
        self.timeLabel.frame = CGRect(x: size.width - timeWidth - 10.0, y: 10.0, width: timeWidth, height: 20.0)
        self.textLabel.frame = CGRect(x: textLeft, y: 31.0, width: size.width - textLeft - 12.0, height: 40.0)

        // Same rule as the chat list: light text on a dark result.
        let lightText = item.image.prefersLightText(rowAspect: Double(size.width / size.height), offset: self.offset, dim: self.dim)
        self.titleLabel.textColor = lightText ? .white : .black
        self.textLabel.textColor = lightText ? UIColor(white: 1.0, alpha: 0.72) : UIColor(white: 0.0, alpha: 0.62)
        self.timeLabel.textColor = lightText ? UIColor(white: 1.0, alpha: 0.72) : UIColor(white: 0.0, alpha: 0.62)

        if !self.dimSlider.isTracking {
            self.dimSlider.value = Float(self.dim)
        }
        if !self.offsetSlider.isTracking {
            self.offsetSlider.value = Float(self.offset)
        }
        self.dimValueLabel.text = "\(Int((self.dim * 100.0).rounded()))%"
    }

    @objc private func sliderBegan() {
        self.isEditing = true
    }

    @objc private func sliderChanged() {
        self.dim = ShadowChatBanners.clampDim(Double(self.dimSlider.value))
        self.offset = ShadowChatBanners.clampOffset(Double(self.offsetSlider.value))
        self.updatePreview()
    }

    @objc private func sliderEnded() {
        self.sliderChanged()
        self.isEditing = false
        self.item?.commit(self.dim, self.offset)
    }

    @objc private func panGesture(_ recognizer: UIPanGestureRecognizer) {
        guard let item = self.item, self.cardSize.width > 0.0 else {
            return
        }
        // Height of the photo scaled to the row width; the band can travel
        // (photo height − row height) points.
        let scaledHeight = Double(self.cardSize.width) / item.image.aspect
        let travel = scaledHeight - Double(self.cardSize.height)
        guard travel > 1.0 else {
            return
        }
        switch recognizer.state {
        case .began:
            self.isEditing = true
            self.panStartOffset = self.offset
        case .changed:
            let translation = Double(recognizer.translation(in: self.cardView).y)
            // Finger down shows more of the top of the photo.
            self.offset = ShadowChatBanners.clampOffset(self.panStartOffset - translation / travel)
            self.updatePreview()
        case .ended, .cancelled, .failed:
            self.isEditing = false
            item.commit(self.dim, self.offset)
        default:
            break
        }
    }
}

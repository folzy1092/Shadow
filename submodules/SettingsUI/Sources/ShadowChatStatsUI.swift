import Foundation
import UIKit
import WebKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import ItemListPeerItem
import PresentationDataUtils
import AccountContext
import UndoUI

// Shadow: «Итоги чатов» — the list in Shadow settings (one report per chat),
// the period sheet, the computing job (keeps running when the screen closes)
// and the report screen: ShadowChatStatsPage in a WKWebView, whose buttons
// share a picture or an .html file, recalculate or open the chat.

// MARK: - Jobs

final class ShadowChatStatsJobs {
    static let shared = ShadowChatStatsJobs()

    struct State: Equatable {
        var fraction: Double
        var text: String
        var finished: Bool
        var failed: Bool
    }

    private var disposables: [String: DisposableSet] = [:]
    private(set) var states: [String: State] = [:]
    let updates = ValuePromise<[String: State]>([:], ignoreRepeated: false)

    static func key(accountPeerId: EnginePeer.Id, peerId: EnginePeer.Id) -> String {
        return "\(accountPeerId.toInt64()):\(peerId.toInt64())"
    }

    func isRunning(_ key: String) -> Bool {
        if let state = self.states[key] {
            return !state.finished && !state.failed
        }
        return false
    }

    private func set(_ key: String, _ state: State?) {
        self.states[key] = state
        self.updates.set(self.states)
    }

    func clear(_ key: String) {
        if let state = self.states[key], state.finished || state.failed {
            self.set(key, nil)
        }
    }

    func start(context: AccountContext, peerId: EnginePeer.Id, period: ShadowChatStats.Period) {
        let key = ShadowChatStatsJobs.key(accountPeerId: context.account.peerId, peerId: peerId)
        self.disposables[key]?.dispose()
        let disposables = DisposableSet()
        self.disposables[key] = disposables
        let now = Int32(Date().timeIntervalSince1970)
        let since = period.start(now: now)
        self.set(key, State(fraction: 0.02, text: "Загружаю переписку…", finished: false, failed: false))

        let account = context.account
        let compute: () -> Void = { [weak self] in
            self?.set(key, State(fraction: 0.97, text: "Считаю итоги…", finished: false, failed: false))
            disposables.add((ShadowChatStatsCollect.report(account: account, peerId: peerId, period: period, now: now)
            |> deliverOnMainQueue).start(next: { [weak self] report in
                guard let self else {
                    return
                }
                if let report {
                    ShadowChatStatsStore.shared.save(report)
                    self.set(key, State(fraction: 1.0, text: "Готово", finished: true, failed: false))
                } else {
                    self.set(key, State(fraction: 1.0, text: "Для этого чата итоги не считаются.", finished: false, failed: true))
                }
            }))
        }
        disposables.add((ShadowChatStatsCollect.loadHistory(account: account, peerId: peerId, since: since)
        |> deliverOnMainQueue).start(next: { [weak self] progress in
            guard let self else {
                return
            }
            if progress.done {
                compute()
                return
            }
            var fraction = 0.05
            var text = "Загружено \(progress.downloaded) \(shadowPlural(progress.downloaded, "сообщение", "сообщения", "сообщений"))"
            if progress.reachedTimestamp > 0 {
                fraction = max(0.05, min(0.95, Double(now - progress.reachedTimestamp) / Double(max(1, now - since))))
                text += " · дошли до \(shadowStatsDate(progress.reachedTimestamp))"
            }
            self.set(key, State(fraction: fraction, text: text, finished: false, failed: false))
        }))
    }
}

func shadowStatsDate(_ timestamp: Int32) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ru_RU")
    formatter.dateFormat = "d MMMM yyyy"
    return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
}

private func shadowStatsShortDate(_ timestamp: Int32) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ru_RU")
    formatter.dateFormat = "d MMM"
    return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
}

// MARK: - Entry points

// The period sheet, then the report screen (which shows the progress first).
public func shadowPresentChatStatsPeriod(context: AccountContext, peerId: EnginePeer.Id, title: String, from controller: ViewController, pushScreen: Bool = true) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let actionSheet = ActionSheetController(presentationData: presentationData)
    var items: [ActionSheetItem] = [
        ActionSheetTextItem(title: "Итоги с «\(title)». Чем длиннее период, тем дольше загрузка истории: она идёт так же, как при прокрутке чата вверх.", parseMarkdown: false)
    ]
    for period in ShadowChatStats.Period.allCases {
        items.append(ActionSheetButtonItem(title: period.title, color: .accent, action: { [weak actionSheet, weak controller] in
            actionSheet?.dismissAnimated()
            ShadowChatStatsJobs.shared.start(context: context, peerId: peerId, period: period)
            if pushScreen, let controller {
                controller.push(ShadowChatStatsController(context: context, peerId: peerId, title: title))
            }
        }))
    }
    actionSheet.setItemGroups([
        ActionSheetItemGroup(items: items),
        ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
            actionSheet?.dismissAnimated()
        })])
    ])
    controller.present(actionSheet, in: .window(.root))
}

// MARK: - List

private enum ShadowChatStatsListEntry: ItemListNodeEntry {
    case add
    case countDeleted(Bool)
    case header
    case report(Int32, EnginePeer, String, Bool)
    case missing(Int32, Int64, String, String)
    case empty
    case info

    var section: ItemListSectionId {
        switch self {
        case .add, .countDeleted:
            return 0
        case .header, .report, .missing, .empty, .info:
            return 1
        }
    }

    var stableId: Int64 {
        switch self {
        case .add: return 0
        case .countDeleted: return 2
        case .header: return 3
        case let .report(index, _, _, _): return 100 + Int64(index)
        case let .missing(index, _, _, _): return 100 + Int64(index)
        case .empty: return 100_000
        case .info: return 100_001
        }
    }

    static func < (lhs: ShadowChatStatsListEntry, rhs: ShadowChatStatsListEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ShadowChatStatsListArguments
        switch self {
        case .add:
            return ItemListActionItem(presentationData: presentationData, title: "Новые итоги", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.add()
            })
        case let .countDeleted(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Считать удалённые сообщения", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.setCountDeleted(value)
            })
        case .header:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ГОТОВЫЕ", sectionId: self.section)
        case let .report(_, peer, text, revealed):
            let revealOptions = ItemListPeerItemRevealOptions(options: [ItemListPeerItemRevealOption(type: .destructive, title: "Удалить", action: {
                arguments.remove(peer.id.toInt64())
            })])
            return ItemListPeerItem(presentationData: presentationData, dateTimeFormat: arguments.dateTimeFormat, nameDisplayOrder: arguments.nameDisplayOrder, context: arguments.context, peer: peer, presence: nil, text: .text(text, .secondary), label: .disclosure(""), editing: ItemListPeerItemEditing(editable: true, editing: false, revealed: revealed), revealOptions: revealOptions, switchValue: nil, enabled: true, selectable: true, sectionId: self.section, action: {
                arguments.open(peer.id, peer.compactDisplayTitle)
            }, setPeerIdWithRevealedOptions: { previousId, id in
                arguments.setRevealed(previousId, id)
            }, removePeer: { peerId in
                arguments.remove(peerId.toInt64())
            })
        case let .missing(_, peerId, title, text):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: text, labelStyle: .detailText, sectionId: self.section, style: .blocks, action: {
                arguments.open(EnginePeer.Id(peerId), title)
            })
        case .empty:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Итогов пока нет. Нажмите «Новые итоги» или откройте профиль собеседника → «…» → «Итоги чата»."), sectionId: self.section)
        case .info:
            return ItemListTextItem(presentationData: presentationData, text: .plain("У каждого чата одни итоги: если подвести их заново, старые заменяются. Смахните влево, чтобы удалить. Всё считается на телефоне. «Считать удалённые» — сообщения, сохранённые анти-удалением; выключено — их нет в итогах, новые итоги считаются без них."), sectionId: self.section)
        }
    }
}

private final class ShadowChatStatsListArguments {
    let context: AccountContext
    let dateTimeFormat: PresentationDateTimeFormat
    let nameDisplayOrder: PresentationPersonNameOrder
    let add: () -> Void
    let open: (EnginePeer.Id, String) -> Void
    let remove: (Int64) -> Void
    let setRevealed: (EnginePeer.Id?, EnginePeer.Id?) -> Void
    var setCountDeleted: (Bool) -> Void = { _ in }

    init(context: AccountContext, dateTimeFormat: PresentationDateTimeFormat, nameDisplayOrder: PresentationPersonNameOrder, add: @escaping () -> Void, open: @escaping (EnginePeer.Id, String) -> Void, remove: @escaping (Int64) -> Void, setRevealed: @escaping (EnginePeer.Id?, EnginePeer.Id?) -> Void) {
        self.context = context
        self.dateTimeFormat = dateTimeFormat
        self.nameDisplayOrder = nameDisplayOrder
        self.add = add
        self.open = open
        self.remove = remove
        self.setRevealed = setRevealed
    }
}

private struct ShadowChatStatsListRow {
    let peerId: Int64
    let title: String
    let text: String
}

public func shadowChatStatsListController(context: AccountContext) -> ViewController {
    let accountPeerId = context.account.peerId
    var pushControllerImpl: ((ViewController) -> Void)?
    var currentController: (() -> ViewController?)?
    let revision = ValuePromise<Int>(0, ignoreRepeated: false)
    var revisionValue = 0
    let revealedPeerId = ValuePromise<EnginePeer.Id?>(nil, ignoreRepeated: true)
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }

    let arguments = ShadowChatStatsListArguments(context: context, dateTimeFormat: presentationData.dateTimeFormat, nameDisplayOrder: presentationData.nameDisplayOrder, add: {
        let picker = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(context: context, filter: [.excludeSavedMessages, .excludeChannels, .excludeRecent, .doNotSearchMessages], hasContactSelector: false, title: "Выберите чат"))
        picker.peerSelected = { [weak picker] peer, _ in
            guard let picker else {
                return
            }
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let title = peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
            let parent = currentController?()
            picker.dismiss()
            if let parent {
                shadowPresentChatStatsPeriod(context: context, peerId: peer.id, title: title, from: parent)
            }
        }
        pushControllerImpl?(picker)
    }, open: { peerId, title in
        pushControllerImpl?(ShadowChatStatsController(context: context, peerId: peerId, title: title))
    }, remove: { peerId in
        ShadowChatStatsStore.shared.remove(accountPeerId: accountPeerId.toInt64(), peerId: peerId)
        revisionValue += 1
        revision.set(revisionValue)
    }, setRevealed: { previousId, id in
        revealedPeerId.set(id)
    })

    let rows: Signal<[ShadowChatStatsListRow], NoError> = combineLatest(revision.get(), ShadowChatStatsJobs.shared.updates.get())
    |> map { _, jobs -> [ShadowChatStatsListRow] in
        var rows: [ShadowChatStatsListRow] = []
        var seen = Set<Int64>()
        let prefix = "\(accountPeerId.toInt64()):"
        for (key, state) in jobs where key.hasPrefix(prefix) && !state.finished && !state.failed {
            if let peerId = Int64(key.dropFirst(prefix.count)) {
                seen.insert(peerId)
                rows.append(ShadowChatStatsListRow(peerId: peerId, title: "", text: "Считаю… \(Int(state.fraction * 100))%"))
            }
        }
        for report in ShadowChatStatsStore.shared.reports(accountPeerId: accountPeerId.toInt64()) where !seen.contains(report.peerId) {
            let kind = report.isGroup ? "Группа · " : ""
            rows.append(ShadowChatStatsListRow(peerId: report.peerId, title: report.title, text: "\(kind)\(report.period.title) · посчитано \(shadowStatsShortDate(report.generated))"))
        }
        return rows
    }
    let rowsWithPeers: Signal<([ShadowChatStatsListRow], [EnginePeer.Id: EnginePeer]), NoError> = rows
    |> mapToSignal { rows -> Signal<([ShadowChatStatsListRow], [EnginePeer.Id: EnginePeer]), NoError> in
        let peerIds = rows.map { EnginePeer.Id($0.peerId) }
        return context.engine.data.get(EngineDataMap(peerIds.map(TelegramEngine.EngineData.Item.Peer.Peer.init(id:))))
        |> map { peers -> ([ShadowChatStatsListRow], [EnginePeer.Id: EnginePeer]) in
            var result: [EnginePeer.Id: EnginePeer] = [:]
            for (id, peer) in peers {
                if let peer {
                    result[id] = peer
                }
            }
            return (rows, result)
        }
    }

    arguments.setCountDeleted = { value in
        let _ = updateAyuGramSettings(postbox: context.account.postbox) { current in
            var current = current
            current.chatStatsCountDeleted = value
            return current
        }.startStandalone()
    }
    let linkRows = ShadowSettingsLinkRows()
    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, rowsWithPeers, revealedPeerId.get(), ayuGramSettings(postbox: context.account.postbox))
    |> map { presentationData, data, revealed, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let (rows, peers) = data
        var entries: [ShadowChatStatsListEntry] = [.add, .countDeleted(settings.chatStatsCountDeleted), .header]
        for (index, row) in rows.enumerated() {
            if let peer = peers[EnginePeer.Id(row.peerId)] {
                entries.append(.report(Int32(index), peer, row.text, revealed == peer.id))
            } else {
                entries.append(.missing(Int32(index), row.peerId, row.title.isEmpty ? "Чат" : row.title, row.text))
            }
        }
        entries.append(rows.isEmpty ? .empty : .info)
        linkRows.stableIds = entries.map { Int32(clamping: $0.stableId) }
        let state = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Итоги чатов"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (state, (ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true), arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    shadowSettingsInstallLinkMenu(controller: controller, context: context, screen: "stats", rows: linkRows)
    pushControllerImpl = { [weak controller] c in
        controller?.push(c)
    }
    currentController = { [weak controller] in
        return controller
    }
    return controller
}

// MARK: - Report screen

private final class ShadowWeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        self.target?.userContentController(userContentController, didReceive: message)
    }
}

// Renders the share card off screen and snapshots it.
private final class ShadowStatsCardRenderer: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private var completion: ((UIImage?) -> Void)?

    init(html: String, in container: UIView, completion: @escaping (UIImage?) -> Void) {
        self.webView = WKWebView(frame: CGRect(x: -2000.0, y: 0.0, width: 360.0, height: 640.0))
        self.completion = completion
        super.init()
        self.webView.isOpaque = false
        self.webView.backgroundColor = .clear
        self.webView.scrollView.isScrollEnabled = false
        self.webView.navigationDelegate = self
        container.addSubview(self.webView)
        self.webView.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Emoji and images settle after the load event.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else {
                return
            }
            let configuration = WKSnapshotConfiguration()
            configuration.rect = CGRect(x: 0.0, y: 0.0, width: 360.0, height: 640.0)
            configuration.snapshotWidth = NSNumber(value: 1080.0)
            self.webView.takeSnapshot(with: configuration) { [weak self] image, _ in
                self?.finish(image)
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.finish(nil)
    }

    private func finish(_ image: UIImage?) {
        self.webView.removeFromSuperview()
        let completion = self.completion
        self.completion = nil
        completion?(image)
    }
}

final class ShadowChatStatsController: ViewController, WKScriptMessageHandler {
    private let context: AccountContext
    private let peerId: EnginePeer.Id
    private let key: String
    private var presentationData: PresentationData
    private var webView: WKWebView?
    private var shownPage: String = ""
    private var jobsDisposable: Disposable?
    private var cardRenderer: ShadowStatsCardRenderer?
    private var report: ShadowChatStats.Report?

    init(context: AccountContext, peerId: EnginePeer.Id, title: String) {
        self.context = context
        self.peerId = peerId
        self.key = ShadowChatStatsJobs.key(accountPeerId: context.account.peerId, peerId: peerId)
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))
        self.title = "Итоги"
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.jobsDisposable?.dispose()
        self.webView?.configuration.userContentController.removeScriptMessageHandler(forName: "shadow")
    }

    override func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNode.backgroundColor = self.presentationData.theme.list.blocksBackgroundColor
        self.displayNodeDidLoad()

        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(ShadowWeakScriptHandler(self), name: "shadow")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        self.displayNode.view.addSubview(webView)
        self.webView = webView

        self.jobsDisposable = (ShadowChatStatsJobs.shared.updates.get()
        |> deliverOnMainQueue).start(next: { [weak self] states in
            self?.update(state: states[self?.key ?? ""])
        })
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let top = self.navigationLayout(layout: layout).navigationFrame.maxY
        self.webView?.frame = CGRect(x: 0.0, y: top, width: layout.size.width, height: max(0.0, layout.size.height - top))
    }

    private var isDark: Bool {
        return self.presentationData.theme.overallDarkAppearance
    }

    private func update(state: ShadowChatStatsJobs.State?) {
        guard let webView = self.webView else {
            return
        }
        if let state, !state.finished {
            if state.failed {
                self.showPage("failed", html: self.progressHTML(fraction: 1.0, text: state.text, failed: true))
                return
            }
            if self.shownPage != "progress" {
                self.showPage("progress", html: self.progressHTML(fraction: state.fraction, text: state.text, failed: false))
            } else {
                let text = state.text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
                webView.evaluateJavaScript("update(\(state.fraction), '\(text)')", completionHandler: nil)
            }
            return
        }
        if state?.finished == true {
            ShadowChatStatsJobs.shared.clear(self.key)
            self.shownPage = ""
        }
        if self.shownPage == "report" {
            return
        }
        if let report = ShadowChatStatsStore.shared.report(accountPeerId: self.context.account.peerId.toInt64(), peerId: self.peerId.toInt64()) {
            self.report = report
            self.showPage("report", html: ShadowChatStatsPage.render(report, options: ShadowChatStatsPage.Options(mode: .app, dark: self.isDark)))
        } else {
            self.showPage("none", html: self.progressHTML(fraction: 0.0, text: "Итогов пока нет.", failed: true))
        }
    }

    private func showPage(_ name: String, html: String) {
        self.shownPage = name
        self.webView?.loadHTMLString(html, baseURL: nil)
    }

    private func progressHTML(fraction: Double, text: String, failed: Bool) -> String {
        let escaped = ShadowChatStatsPage.htmlEscaped(text)
        let theme = self.isDark ? "dark" : "light"
        return """
        <!doctype html><html lang="ru" data-theme="\(theme)"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        :root { --page: #000; --text: #fff; --sub: #8e8e93; --track: #2c2c2e; --accent: #3e9bff; }
        :root[data-theme="light"] { --page: #f2f2f7; --text: #000; --sub: #6d6d72; --track: #e5e5ea; }
        body { margin: 0; background: var(--page); color: var(--text); font: 15px/1.4 -apple-system, sans-serif; text-align: center; padding: 48px 28px; }
        .ring { width: 150px; height: 150px; margin: 10px auto 18px; position: relative; }
        .ring svg { transform: rotate(-90deg); }
        .pct { position: absolute; inset: 0; display: grid; place-items: center; font-size: 30px; font-weight: 700; }
        .big { font-size: 17px; font-weight: 600; }
        .sm { color: var(--sub); font-size: 14px; margin-top: 18px; }
        </style></head><body>
        \(failed ? "" : "<div class=\"ring\"><svg width=\"150\" height=\"150\" viewBox=\"0 0 150 150\"><circle cx=\"75\" cy=\"75\" r=\"66\" fill=\"none\" stroke=\"var(--track)\" stroke-width=\"10\"/><circle id=\"arc\" cx=\"75\" cy=\"75\" r=\"66\" fill=\"none\" stroke=\"var(--accent)\" stroke-width=\"10\" stroke-linecap=\"round\" stroke-dasharray=\"414.7\" stroke-dashoffset=\"414.7\"/></svg><div class=\"pct\" id=\"pct\">0%</div></div>")
        <div class="big" id="text">\(escaped)</div>
        \(failed ? "" : "<div class=\"sm\">История грузится так же, как при прокрутке чата вверх. Можно выйти с экрана: подсчёт продолжится, а итоги появятся в списке «Итоги чатов».</div>")
        <script>
        function update(f, t) {
          var arc = document.getElementById('arc'); if (arc) arc.setAttribute('stroke-dashoffset', 414.7 * (1 - f));
          var p = document.getElementById('pct'); if (p) p.textContent = Math.round(f * 100) + '%';
          document.getElementById('text').textContent = t;
        }
        update(\(fraction), document.getElementById('text').textContent);
        </script></body></html>
        """
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let action = body["action"] as? String, let report = self.report else {
            return
        }
        switch action {
        case "shareImage":
            let kind = ShadowChatStatsPage.CardKind(rawValue: body["kind"] as? String ?? "cmp") ?? .compare
            let hideName = body["hideName"] as? Bool ?? false
            self.shareImage(report: report, kind: kind, hideName: hideName)
        case "shareFile":
            self.askShareFile(report: report)
        case "recalculate":
            shadowPresentChatStatsPeriod(context: self.context, peerId: self.peerId, title: report.title, from: self, pushScreen: false)
            self.shownPage = ""
        case "openChat":
            self.openChat()
        default:
            break
        }
    }

    private func shareImage(report: ShadowChatStats.Report, kind: ShadowChatStatsPage.CardKind, hideName: Bool) {
        let html = ShadowChatStatsPage.render(report, options: ShadowChatStatsPage.Options(mode: .card, dark: true, card: kind, hideName: hideName))
        self.cardRenderer = ShadowStatsCardRenderer(html: html, in: self.view, completion: { [weak self] image in
            guard let self else {
                return
            }
            self.cardRenderer = nil
            guard let image else {
                self.toast("Не получилось сделать картинку.")
                return
            }
            self.presentShare([image])
        })
    }

    private func askShareFile(report: ShadowChatStats.Report) {
        let actionSheet = ActionSheetController(presentationData: self.presentationData)
        let share: (Bool) -> Void = { [weak self] anonymous in
            self?.shareFile(report: anonymous ? ShadowChatStats.anonymized(report) : report)
        }
        actionSheet.setItemGroups([
            ActionSheetItemGroup(items: [
                ActionSheetTextItem(title: "HTML-страница с вкладками и графиками. Открывается в любом браузере, без интернета.", parseMarkdown: false),
                ActionSheetButtonItem(title: "С именами", color: .accent, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    share(false)
                }),
                ActionSheetButtonItem(title: "Анонимно", color: .accent, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    share(true)
                })
            ]),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: self.presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
            })])
        ])
        self.present(actionSheet, in: .window(.root))
    }

    private func shareFile(report: ShadowChatStats.Report) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("shadow-chat-stats-" + UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: nil)
            let url = directory.appendingPathComponent(ShadowChatStatsPage.fileName(report))
            try ShadowChatStatsPage.render(report, options: ShadowChatStatsPage.Options(mode: .file)).write(to: url, atomically: true, encoding: .utf8)
            self.presentShare([url], cleanup: directory)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            self.toast("Не получилось сохранить файл.")
        }
    }

    private func presentShare(_ items: [Any], cleanup: URL? = nil) {
        guard let window = self.view.window, var presenter = window.rootViewController else {
            if let cleanup {
                try? FileManager.default.removeItem(at: cleanup)
            }
            return
        }
        while let next = presenter.presentedViewController {
            presenter = next
        }
        let share = UIActivityViewController(activityItems: items, applicationActivities: nil)
        share.completionWithItemsHandler = { _, _, _, _ in
            if let cleanup {
                try? FileManager.default.removeItem(at: cleanup)
            }
        }
        if let popover = share.popoverPresentationController {
            popover.sourceView = self.view
            popover.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 1.0, height: 1.0)
            popover.permittedArrowDirections = []
        }
        presenter.present(share, animated: true)
    }

    private func openChat() {
        let context = self.context
        let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: self.peerId))
        |> deliverOnMainQueue).start(next: { [weak self] peer in
            guard let self, let peer, let navigationController = self.navigationController as? NavigationController else {
                return
            }
            context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(peer)))
        })
    }

    private func toast(_ text: String) {
        self.present(UndoOverlayController(presentationData: self.presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), in: .current)
    }
}

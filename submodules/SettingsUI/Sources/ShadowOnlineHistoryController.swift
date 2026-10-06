import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext

// Shadow: «История в сети» for one contact (spec 7.4), from ShadowOnlineHistory.

private enum ShadowOnlineHistoryEntry: ItemListNodeEntry {
    case summary(String)
    case dayHeader(index: Int, title: String)
    case dayText(index: Int, text: String)
    case hoursHeader
    case hoursText(String)
    case empty

    var section: ItemListSectionId {
        switch self {
        case .summary, .empty:
            return 0
        case let .dayHeader(index, _), let .dayText(index, _):
            return 1 + Int32(index)
        case .hoursHeader, .hoursText:
            return 100
        }
    }

    var stableId: Int32 {
        switch self {
        case .summary: return 0
        case .empty: return 1
        case let .dayHeader(index, _): return 10 + Int32(index) * 2
        case let .dayText(index, _): return 11 + Int32(index) * 2
        case .hoursHeader: return 1000
        case .hoursText: return 1001
        }
    }

    static func <(lhs: ShadowOnlineHistoryEntry, rhs: ShadowOnlineHistoryEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        switch self {
        case let .summary(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case .empty:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Пока нет записей. История копится, пока включена настройка Shadow → Сохранение → «Журнал «в сети»» и контакт заходит в Telegram."), sectionId: self.section)
        case let .dayHeader(_, title):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: title, sectionId: self.section)
        case let .dayText(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case .hoursHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ПО ЧАСАМ ЗА 30 ДНЕЙ", sectionId: self.section)
        case let .hoursText(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func shadowDurationText(_ seconds: Int) -> String {
    if seconds < 60 {
        return "<1 мин"
    }
    let minutes = seconds / 60
    if minutes < 60 {
        return "\(minutes) мин"
    }
    return "\(minutes / 60) ч \(minutes % 60) мин"
}

private func shadowOnlineHistoryEntries(sessions: [ShadowOnlineHistory.Session]) -> [ShadowOnlineHistoryEntry] {
    if sessions.isEmpty {
        return [.empty]
    }
    let calendar = Calendar.current
    let timeFormatter = DateFormatter()
    timeFormatter.locale = Locale(identifier: "ru_RU")
    timeFormatter.dateFormat = "HH:mm"
    let dayFormatter = DateFormatter()
    dayFormatter.locale = Locale(identifier: "ru_RU")
    dayFormatter.dateFormat = "EEEE, d MMMM"

    var entries: [ShadowOnlineHistoryEntry] = []
    let total = sessions.reduce(0) { $0 + Int($1.end - $1.start) }
    entries.append(.summary("За 30 дней: \(sessions.count) заходов, всего \(shadowDurationText(total)) в сети."))

    // Last 7 days, newest first.
    var byDay: [Date: [ShadowOnlineHistory.Session]] = [:]
    for session in sessions {
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(session.start)))
        byDay[day, default: []].append(session)
    }
    for (index, day) in byDay.keys.sorted(by: >).prefix(7).enumerated() {
        let daySessions = (byDay[day] ?? []).sorted(by: { $0.start < $1.start })
        let dayTotal = daySessions.reduce(0) { $0 + Int($1.end - $1.start) }
        var title = dayFormatter.string(from: day).uppercased()
        if calendar.isDateInToday(day) {
            title = "СЕГОДНЯ"
        } else if calendar.isDateInYesterday(day) {
            title = "ВЧЕРА"
        }
        entries.append(.dayHeader(index: index, title: "\(title) · \(shadowDurationText(dayTotal))"))
        let lines = daySessions.map { session -> String in
            let start = timeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(session.start)))
            let end = timeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(session.end)))
            return "\(start)–\(end) (\(shadowDurationText(Int(session.end - session.start))))"
        }
        entries.append(.dayText(index: index, text: lines.joined(separator: "\n")))
    }

    // Minutes online per hour of day over the whole period.
    var perHour = [Int](repeating: 0, count: 24)
    for session in sessions {
        var cursor = TimeInterval(session.start)
        let end = TimeInterval(session.end)
        while cursor < end {
            let date = Date(timeIntervalSince1970: cursor)
            let hour = calendar.component(.hour, from: date)
            let nextHour = calendar.date(byAdding: .hour, value: 1, to: calendar.dateInterval(of: .hour, for: date)?.start ?? date)?.timeIntervalSince1970 ?? end
            let sliceEnd = min(end, nextHour)
            perHour[hour] += Int(sliceEnd - cursor)
            cursor = max(sliceEnd, cursor + 1)
        }
    }
    let maxValue = max(1, perHour.max() ?? 1)
    let lines = (0 ..< 24).map { hour -> String in
        let bars = Int((Double(perHour[hour]) / Double(maxValue) * 10.0).rounded())
        let bar = String(repeating: "▇", count: bars) + String(repeating: "·", count: 10 - bars)
        return String(format: "%02d:00  ", hour) + bar + "  " + shadowDurationText(perHour[hour])
    }
    entries.append(.hoursHeader)
    entries.append(.hoursText(lines.joined(separator: "\n")))
    return entries
}

public func shadowOnlineHistoryController(context: AccountContext, peerId: EnginePeer.Id) -> ViewController {
    let sessions = ShadowOnlineHistory.shared.sessions(accountPeerId: context.account.peerId.toInt64(), peerId: peerId.toInt64())
    let entries = shadowOnlineHistoryEntries(sessions: sessions)
    let signal = context.sharedContext.presentationData
    |> deliverOnMainQueue
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("История в сети"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false)
        return (controllerState, (listState, Void()))
    }
    return ItemListController(context: context, state: signal)
}

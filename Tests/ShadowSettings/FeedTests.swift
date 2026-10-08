import Foundation

@main
struct FeedTests {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            count += 1
        }
        typealias F = ShadowFeed

        // Where the tab goes among contacts, (calls), chats, settings.
        check(F.Position.beforeContacts.index(otherTabs: 3) == 0, "A: first")
        check(F.Position.beforeSettings.index(otherTabs: 3) == 2, "B: before settings (3 tabs)")
        check(F.Position.beforeSettings.index(otherTabs: 4) == 3, "B: before settings (with calls)")
        check(F.Position.afterSettings.index(otherTabs: 4) == 4, "C: last")
        check(F.Position.normalized(7) == .beforeSettings && F.Position.normalized(0) == .beforeContacts, "Normalized")

        // Text.
        check(F.html(text: "a < b & \"c\"\nd", entities: []) == "a &lt; b &amp; &quot;c&quot;<br>d", "Escaped plain text")
        check(F.html(text: "Привет мир", entities: [F.Entity(location: 0, length: 6, kind: .bold)]) == "<b>Привет</b> мир", "Bold")
        let link = F.html(text: "читать тут", entities: [F.Entity(location: 7, length: 3, kind: .link("https://x.ru/?a=1&b=\"2\""))])
        check(link == "читать <a data-url=\"https://x.ru/?a=1&amp;b=&quot;2&quot;\">тут</a>", "Link with an escaped URL")
        let nested = F.html(text: "abcdef", entities: [F.Entity(location: 0, length: 4, kind: .bold), F.Entity(location: 2, length: 4, kind: .italic)])
        check(nested == "<b>ab</b><b><i>cd</i></b><i>ef</i>", "Overlapping entities nest")
        // UTF-16 offsets: the emoji takes two units.
        check(F.html(text: "😀 ok", entities: [F.Entity(location: 3, length: 2, kind: .code)]) == "😀 <code>ok</code>", "UTF-16 ranges")
        check(F.html(text: "x", entities: [F.Entity(location: 5, length: 2, kind: .bold)]) == "x", "Out of range entity ignored")
        check(F.html(text: "<script>", entities: [F.Entity(location: 0, length: 8, kind: .spoiler)]) == "<span class=\"spoiler\">&lt;script&gt;</span>", "Spoiler, escaped")
        check(F.initials("Горизонт новостей") == "ГН" && F.initials("!!!") == "#", "Initials")

        // Post JSON round trip (the page reads these names).
        let post = F.Post(id: "1:0:2", peerId: 1, namespace: 0, messageId: 2, channel: "Канал", color: 3, initials: "К", timestamp: 100, html: "<b>x</b>", textLength: 1, forwardFrom: nil, media: [F.Media(key: "m1", kind: "photo", width: 10, height: 20)], views: 5, reactions: [F.Reaction(key: "👍", count: 2, mine: true)], comments: nil, unread: true, edited: false)
        let json = String(data: try! JSONEncoder().encode(post), encoding: .utf8)!
        for field in ["\"peerId\"", "\"textLength\"", "\"media\"", "\"reactions\"", "\"unread\"", "\"mine\""] {
            check(json.contains(field), "Field \(field)")
        }

        // Store.
        let suite = "shadow-feed-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = ShadowFeedStore(defaults: defaults)
        store.setCollection(ShadowFeedStore.Collection(id: "a", title: "  СМИ  ", peerIds: [1, 2]), accountPeerId: 7)
        check(store.collections(accountPeerId: 7) == [ShadowFeedStore.Collection(id: "a", title: "СМИ", peerIds: [1, 2])], "Collection saved, title trimmed")
        check(store.collections(accountPeerId: 8).isEmpty, "Per account")
        store.setCollection(ShadowFeedStore.Collection(id: "a", title: "Игры", peerIds: [3]), accountPeerId: 7)
        check(store.collections(accountPeerId: 7).map { $0.title } == ["Игры"], "Same id replaces")
        store.setOrder(["col:a", "all"], accountPeerId: 7)
        store.setCollection(ShadowFeedStore.Collection(id: "a", title: "Игры", peerIds: []), accountPeerId: 7)
        check(store.collections(accountPeerId: 7).isEmpty && !store.order(accountPeerId: 7).contains("col:a"), "No channels removes it and its place")
        store.setChannelHidden(5, hidden: true, accountPeerId: 7)
        store.setChannelHidden(6, hidden: true, accountPeerId: 7)
        store.setChannelHidden(5, hidden: false, accountPeerId: 7)
        check(store.hiddenChannels(accountPeerId: 7) == [6], "Hidden channels")
        store.clearHiddenChannels(accountPeerId: 7)
        check(store.hiddenChannels(accountPeerId: 7).isEmpty, "Restore hidden")
        store.setLastSeen(50, accountPeerId: 7)
        store.setLastSeen(40, accountPeerId: 7)
        check(store.lastSeen(accountPeerId: 7) == 50, "Last seen only grows")
        defaults.removePersistentDomain(forName: suite)

        let chips = [F.Chip(id: "all", title: "Все", peerIds: nil), F.Chip(id: "unread", title: "Непрочитанные", peerIds: nil), F.Chip(id: "col:x", title: "X", peerIds: [1]), F.Chip(id: "folder:2", title: "Новости", peerIds: [2])]
        let ordered = ShadowFeedStore.orderedChips(chips, order: ["col:x", "gone", "unread"])
        check(ordered.map { $0.id } == ["col:x", "unread", "all", "folder:2"], "Saved order first, unknown dropped, new at the end")

        print("Shadow feed: \(count) checks passed")
    }
}

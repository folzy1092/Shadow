import Foundation

@main
struct ChatExportTests {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            count += 1
        }

        let chat = ShadowChatExport.Chat(title: "Анна <script>", exportDate: 1_790_000_000, records: [
            ShadowChatExport.Record(id: 1, date: 1_789_000_000, author: "Анна", text: "Привет\nкак дела?", isOutgoing: false),
            ShadowChatExport.Record(id: 2, date: 1_789_000_060, author: "Вы", text: "<b>норм</b> & ты", isOutgoing: true, editDate: 1_789_000_100, edits: [ShadowChatExport.Edit(date: 1_789_000_060, text: "норм")], replyToId: 1),
            ShadowChatExport.Record(id: 3, date: 1_789_000_120, author: "Анна", text: "секрет", isOutgoing: false, deletedDate: 1_789_000_200, media: "Фото", forwardedFrom: "Канал")
        ])
        check(chat.deletedCount == 1, "Deleted count")

        // JSON
        let json = try! JSONSerialization.jsonObject(with: ShadowChatExport.render(chat, format: .json)) as! [String: Any]
        check(json["chat"] as? String == "Анна <script>", "Chat title")
        check(json["message_count"] as? Int == 3, "Message count")
        check(json["deleted_count"] as? Int == 1, "Deleted count in JSON")
        let messages = json["messages"] as! [[String: Any]]
        check(messages.map { $0["id"] as? Int } == [1, 2, 3], "Order kept")
        check(messages[0]["deleted"] == nil && messages[0]["edits"] == nil, "Plain message has no extras")
        check(messages[1]["out"] as? Bool == true, "Outgoing flag")
        check(messages[1]["reply_to"] as? Int == 1, "Reply id")
        check((messages[1]["edits"] as? [[String: Any]])?.first?["text"] as? String == "норм", "Edit versions")
        check(messages[2]["deleted"] as? Bool == true, "Deleted flag")
        check(messages[2]["deleted_date"] as? Int == 1_789_000_200, "Deleted date")
        check(messages[2]["media"] as? String == "Фото", "Media description")
        check(messages[2]["forwarded_from"] as? String == "Канал", "Forward source")
        check((messages[0]["date_text"] as? String)?.hasSuffix("Z") == true, "ISO date")

        // HTML
        let html = ShadowChatExport.renderHTML(chat)
        check(html.hasPrefix("<!doctype html>"), "Doctype")
        check(!html.contains("<script>") && html.contains("Анна &lt;script&gt;"), "Title escaped")
        check(html.contains("&lt;b&gt;норм&lt;/b&gt; &amp; ты"), "Text escaped")
        check(html.contains("Привет<br>как дела?"), "Line breaks")
        check(html.contains("class=\"m del\" id=\"m3\""), "Deleted class")
        check(html.contains("class=\"m out\" id=\"m2\""), "Outgoing class")
        check(html.contains("href=\"#m1\""), "Reply anchor")
        check(html.contains("удалено"), "Deleted tag")
        check(html.contains("изменено"), "Edited tag")
        check(html.contains("Переслано от Канал"), "Forward line")
        check(html.contains("удалённых: 1"), "Header counters")
        check(ShadowChatExport.escapeHTML("\"'") == "&quot;&#39;", "Quotes escaped")

        // File names
        check(ShadowChatExport.fileName(title: "Анна", format: .html) == "Shadow — Анна.html", "Plain file name")
        check(ShadowChatExport.fileName(title: "a/b:c", format: .json) == "Shadow — a_b_c.json", "Forbidden characters replaced")
        check(ShadowChatExport.fileName(title: "  ", format: .json) == "Shadow — chat.json", "Empty title")
        check(ShadowChatExport.fileName(title: "..", format: .html) == "Shadow — chat.html", "Dots only")
        check(ShadowChatExport.fileName(title: String(repeating: "я", count: 200), format: .html).count == "Shadow — ".count + 80 + 5, "Long title trimmed")

        let empty = ShadowChatExport.Chat(title: "", exportDate: 0, records: [])
        check((try? JSONSerialization.jsonObject(with: ShadowChatExport.render(empty, format: .json))) != nil, "Empty chat is valid JSON")
        print("Shadow chat export: \(count) checks passed")
    }
}

import Foundation

// Shadow: chat export to JSON or a self-contained HTML page. It covers the
// messages stored on this device, including those kept after deletion
// (DeletedMessageAttribute) and their saved edit versions. Collection from
// Postbox lives in ShadowChatExportCollect.swift; this file only formats, so it
// is unit-tested by the Foundation suite.
public enum ShadowChatExport {
    public enum Format: CaseIterable {
        case html
        case json

        public var fileExtension: String {
            switch self {
            case .html:
                return "html"
            case .json:
                return "json"
            }
        }

        public var title: String {
            switch self {
            case .html:
                return "HTML (для чтения)"
            case .json:
                return "JSON (для программ)"
            }
        }
    }

    public struct Edit: Equatable {
        public let date: Int32
        public let text: String

        public init(date: Int32, text: String) {
            self.date = date
            self.text = text
        }
    }

    public struct Record: Equatable {
        public let id: Int32
        public let date: Int32
        public let author: String
        public let text: String
        public let isOutgoing: Bool
        // Date the server deleted it (kept by anti-delete); nil when not deleted.
        public let deletedDate: Int32?
        public let editDate: Int32?
        // Earlier versions saved by the fork, oldest first.
        public let edits: [Edit]
        // A short description such as «Фото» or «Файл: report.pdf».
        public let media: String?
        public let replyToId: Int32?
        public let forwardedFrom: String?

        public init(id: Int32, date: Int32, author: String, text: String, isOutgoing: Bool, deletedDate: Int32? = nil, editDate: Int32? = nil, edits: [Edit] = [], media: String? = nil, replyToId: Int32? = nil, forwardedFrom: String? = nil) {
            self.id = id
            self.date = date
            self.author = author
            self.text = text
            self.isOutgoing = isOutgoing
            self.deletedDate = deletedDate
            self.editDate = editDate
            self.edits = edits
            self.media = media
            self.replyToId = replyToId
            self.forwardedFrom = forwardedFrom
        }
    }

    public struct Chat: Equatable {
        public let title: String
        public let exportDate: Int32
        public let records: [Record]

        public init(title: String, exportDate: Int32, records: [Record]) {
            self.title = title
            self.exportDate = exportDate
            self.records = records
        }

        public var deletedCount: Int {
            return self.records.filter { $0.deletedDate != nil }.count
        }
    }

    public static func render(_ chat: Chat, format: Format) -> Data {
        switch format {
        case .html:
            return Data(renderHTML(chat).utf8)
        case .json:
            return renderJSON(chat)
        }
    }

    // A file name without characters that file systems or share targets reject.
    public static func fileName(title: String, format: Format) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r\t").union(.controlCharacters)
        var cleaned = String(title.unicodeScalars.map { forbidden.contains($0) ? "_" : Character($0) })
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        if cleaned.isEmpty || cleaned.allSatisfy({ $0 == "_" || $0 == "." }) {
            cleaned = "chat"
        }
        return "Shadow — " + String(cleaned.prefix(80)) + "." + format.fileExtension
    }

    // MARK: JSON

    public static func renderJSON(_ chat: Chat) -> Data {
        let messages: [[String: Any]] = chat.records.map { record in
            var item: [String: Any] = [
                "id": Int(record.id),
                "date": Int(record.date),
                "date_text": iso8601(record.date),
                "from": record.author,
                "out": record.isOutgoing,
                "text": record.text
            ]
            if let deletedDate = record.deletedDate {
                item["deleted"] = true
                if deletedDate > 0 {
                    item["deleted_date"] = Int(deletedDate)
                }
            }
            if let editDate = record.editDate {
                item["edit_date"] = Int(editDate)
            }
            if !record.edits.isEmpty {
                item["edits"] = record.edits.map { ["date": Int($0.date), "text": $0.text] as [String: Any] }
            }
            if let media = record.media {
                item["media"] = media
            }
            if let replyToId = record.replyToId {
                item["reply_to"] = Int(replyToId)
            }
            if let forwardedFrom = record.forwardedFrom {
                item["forwarded_from"] = forwardedFrom
            }
            return item
        }
        let root: [String: Any] = [
            "exporter": "Shadow",
            "chat": chat.title,
            "export_date": Int(chat.exportDate),
            "message_count": chat.records.count,
            "deleted_count": chat.deletedCount,
            "messages": messages
        ]
        return (try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
    }

    // MARK: HTML

    public static func escapeHTML(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.utf8.count)
        for character in value {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&#39;"
            default: result.append(character)
            }
        }
        return result
    }

    private static func htmlText(_ value: String) -> String {
        return escapeHTML(value).replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "<br>")
    }

    public static func renderHTML(_ chat: Chat) -> String {
        var body = ""
        for record in chat.records {
            var classes = ["m"]
            if record.isOutgoing {
                classes.append("out")
            }
            if record.deletedDate != nil {
                classes.append("del")
            }
            body += "<div class=\"\(classes.joined(separator: " "))\" id=\"m\(record.id)\">"
            body += "<div class=\"h\"><b>\(escapeHTML(record.author))</b> <span>\(escapeHTML(displayDate(record.date)))</span>"
            if record.editDate != nil || !record.edits.isEmpty {
                body += " <span class=\"tag\">изменено</span>"
            }
            if let deletedDate = record.deletedDate {
                let suffix = deletedDate > 0 ? " " + escapeHTML(displayDate(deletedDate)) : ""
                body += " <span class=\"tag d\">удалено\(suffix)</span>"
            }
            body += "</div>"
            if let forwardedFrom = record.forwardedFrom {
                body += "<div class=\"fw\">Переслано от \(escapeHTML(forwardedFrom))</div>"
            }
            if let replyToId = record.replyToId {
                body += "<div class=\"re\"><a href=\"#m\(replyToId)\">В ответ на сообщение</a></div>"
            }
            if let media = record.media {
                body += "<div class=\"md\">[\(escapeHTML(media))]</div>"
            }
            if !record.text.isEmpty {
                body += "<div class=\"t\">\(htmlText(record.text))</div>"
            }
            for edit in record.edits {
                body += "<div class=\"ed\"><span>\(escapeHTML(displayDate(edit.date)))</span> \(htmlText(edit.text))</div>"
            }
            body += "</div>\n"
        }
        let title = escapeHTML(chat.title)
        return """
        <!doctype html>
        <html lang="ru">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(title)</title>
        <style>
        :root{--bg:#f4f4f5;--card:#fff;--out:#e3f2d9;--text:#111;--muted:#6b6b70;--del:#c62828}
        @media (prefers-color-scheme:dark){:root{--bg:#111214;--card:#1d1e21;--out:#23351f;--text:#eee;--muted:#9a9aa0;--del:#ef6b6b}}
        body{margin:0;background:var(--bg);color:var(--text);font:15px/1.4 -apple-system,system-ui,sans-serif}
        main{max-width:760px;margin:0 auto;padding:16px}
        header{margin-bottom:16px}header h1{font-size:20px;margin:0 0 4px}header p{margin:0;color:var(--muted)}
        .m{background:var(--card);border-radius:12px;padding:8px 12px;margin:6px 0;word-wrap:break-word}
        .m.out{background:var(--out);margin-left:15%}.m:not(.out){margin-right:15%}
        .m.del{border-left:3px solid var(--del)}
        .h{font-size:13px;color:var(--muted)}.h b{color:var(--text)}
        .tag{font-size:12px}.tag.d{color:var(--del)}
        .fw,.re,.md{font-size:13px;color:var(--muted)}.re a{color:inherit}
        .t{margin-top:2px;white-space:normal}
        .ed{margin-top:4px;padding-left:8px;border-left:2px solid var(--muted);font-size:13px;color:var(--muted)}
        </style>
        </head>
        <body>
        <main>
        <header><h1>\(title)</h1><p>Экспорт Shadow · \(escapeHTML(displayDate(chat.exportDate))) · сообщений: \(chat.records.count), удалённых: \(chat.deletedCount)</p></header>
        \(body)</main>
        </body>
        </html>

        """
    }

    // MARK: Dates

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func iso8601(_ timestamp: Int32) -> String {
        return isoFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "dd.MM.yyyy HH:mm"
        return formatter
    }()

    static func displayDate(_ timestamp: Int32) -> String {
        return displayFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }
}

import Foundation

// Shadow: «Подарок для розыгрыша». In a private chat (chat list → долгое
// нажатие → Shadow) a link to any collectible gift (t.me/nft/PlushPepe-123)
// puts a gift card «from you» into the chat. Only on this device: nothing is
// sent, the friend sees nothing; delete it like any message.
// ShadowFakeGiftStore.swift stores the message.
//
// Foundation only, so it is unit-tested by the Foundation suite.
public enum ShadowFakeGift {
    // "PlushPepe-123" from "https://t.me/nft/PlushPepe-123", "t.me/nft/…",
    // "tg://nft?slug=…" or the slug itself; nil — not a gift link.
    public static func slug(from text: String) -> String? {
        var string = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = string.range(of: "slug=") {
            string = String(string[range.upperBound...])
        } else if let range = string.range(of: "/nft/") {
            string = String(string[range.upperBound...])
        }
        if let end = string.firstIndex(where: { $0 == "?" || $0 == "/" || $0 == "&" || $0 == "#" }) {
            string = String(string[..<end])
        }
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            return nil
        }
        let letters = CharacterSet.alphanumerics
        guard parts[0].unicodeScalars.allSatisfy({ letters.contains($0) && $0.isASCII }) else {
            return nil
        }
        guard parts[1].unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) && $0.isASCII }) else {
            return nil
        }
        return string
    }
}

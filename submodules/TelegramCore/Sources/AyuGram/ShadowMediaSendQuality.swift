import Foundation

// Shadow: «Качество фото» (Кастомизация → Медиа и камера) — how the media
// picker sends by default. AyuGramSettings.mediaSendQuality:
//
//   0 Как в Telegram  stock: the HD switch remembers the last choice
//   1 Всегда HD       every picker opens in HD
//   2 Без сжатия      the send button sends photos and videos as files (not
//                     with spoilers, a price or in secret chats)
//
// Foundation only.
public enum ShadowMediaSendQuality {
    public static let stock: Int32 = 0
    public static let alwaysHD: Int32 = 1
    public static let file: Int32 = 2
    public static let values: [Int32] = [stock, alwaysHD, file]

    public static func title(_ value: Int32) -> String {
        switch normalized(value) {
        case alwaysHD: return "Всегда HD"
        case file: return "Без сжатия"
        default: return "Как в Telegram"
        }
    }

    public static func normalized(_ value: Int32) -> Int32 {
        return values.contains(value) ? value : stock
    }
}

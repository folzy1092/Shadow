import Foundation

// Shadow: «Имитация активности» — the chat shows «печатает…», «записывает
// голосовое…» and so on while nothing is actually being written or sent
// (ShadowActivityImitation repeats messages.setTyping until stopped). Opened by
// holding the attachment (paperclip) button in a chat.
//
// The modes are every action Telegram 13 shows in a chat header, the same set
// as the Android «Imitator» plugin plus the ones it did not have (sending a
// video, sending a round video, importing history). «Случайно» switches action
// on every repeat. Foundation only, so it is unit-tested by the Foundation suite.
public enum ShadowActivityImitationMode: Int32, CaseIterable {
    case typing = 0
    case recordingVoice = 1
    case recordingRound = 2
    case recordingVideo = 3
    case sendingPhoto = 4
    case sendingVideo = 5
    case sendingRound = 6
    case sendingAudio = 7
    case sendingFile = 8
    case choosingSticker = 9
    case choosingLocation = 10
    case choosingContact = 11
    case playingGame = 12
    case importingHistory = 13
    case random = 14

    // What the menu says.
    public var title: String {
        switch self {
        case .typing: return "Печатает"
        case .recordingVoice: return "Записывает голосовое"
        case .recordingRound: return "Записывает кружок"
        case .recordingVideo: return "Записывает видео"
        case .sendingPhoto: return "Отправляет фото"
        case .sendingVideo: return "Отправляет видео"
        case .sendingRound: return "Отправляет кружок"
        case .sendingAudio: return "Отправляет аудио"
        case .sendingFile: return "Отправляет файл"
        case .choosingSticker: return "Выбирает стикер"
        case .choosingLocation: return "Отправляет геопозицию"
        case .choosingContact: return "Выбирает контакт"
        case .playingGame: return "Играет в игру"
        case .importingHistory: return "Импортирует историю"
        case .random: return "Случайно"
        }
    }

    // SF Symbol for the menu row.
    public var icon: String {
        switch self {
        case .typing: return "keyboard"
        case .recordingVoice: return "mic"
        case .recordingRound: return "video.circle"
        case .recordingVideo: return "video"
        case .sendingPhoto: return "photo"
        case .sendingVideo: return "film"
        case .sendingRound: return "circle.dashed"
        case .sendingAudio: return "music.note"
        case .sendingFile: return "doc"
        case .choosingSticker: return "face.smiling"
        case .choosingLocation: return "location"
        case .choosingContact: return "person.crop.circle"
        case .playingGame: return "gamecontroller"
        case .importingHistory: return "square.and.arrow.down"
        case .random: return "shuffle"
        }
    }

    // Upload actions carry a percentage; the others show no progress.
    public var hasProgress: Bool {
        switch self {
        case .sendingPhoto, .sendingVideo, .sendingRound, .sendingAudio, .sendingFile, .importingHistory:
            return true
        default:
            return false
        }
    }

    // Order in the menu.
    public static let menuOrder: [ShadowActivityImitationMode] = [
        .typing, .recordingVoice, .recordingRound, .recordingVideo,
        .sendingPhoto, .sendingVideo, .sendingRound, .sendingAudio, .sendingFile,
        .choosingSticker, .choosingLocation, .choosingContact, .playingGame,
        .importingHistory, .random
    ]

    // Every mode that is one concrete action (what «Случайно» picks from).
    public static let concrete: [ShadowActivityImitationMode] = menuOrder.filter { $0 != .random }

    // A secret chat can only show «печатает» (messages.setEncryptedTyping).
    public static func available(secretChat: Bool) -> [ShadowActivityImitationMode] {
        return secretChat ? [.typing] : menuOrder
    }

    // The concrete action for one repeat: «Случайно» takes `randomIndex`
    // (any integer, wrapped), the others are themselves.
    public func resolved(randomIndex: Int) -> ShadowActivityImitationMode {
        guard self == .random else {
            return self
        }
        let count = ShadowActivityImitationMode.concrete.count
        let index = ((randomIndex % count) + count) % count
        return ShadowActivityImitationMode.concrete[index]
    }

    // Upload progress for repeat number `tick`: climbs by 7% a repeat and
    // starts over, so the header looks like a real upload.
    public static func progress(tick: Int) -> Int32 {
        return Int32((max(0, tick) * 7) % 100)
    }

    // Seconds between two setTyping requests. Telegram clients hide an action
    // about 6 s after the last one, so a repeat every 4 s keeps it on screen.
    public static let repeatInterval: Double = 4.0
}

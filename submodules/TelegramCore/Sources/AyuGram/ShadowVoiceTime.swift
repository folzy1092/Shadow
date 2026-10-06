import Foundation

// Shadow: the time under a voice message (and, by the toggles, on round videos
// and in the top player). AyuGramSettings.voiceTimeFormat picks the format:
//
//   0 По умолчанию      1:14 → 0:52 (what is left; round videos keep Telegram's
//                       own elapsed time)
//   1 Текущий таймкод   0:22
//   2 Прошло / всего    0:22 / 1:14
//   3 Осталось / всего  -0:52 / 1:14
//   4 Прошло и процент  0:22 · 30%
//   5 Процент           30%
//
// While nothing plays (position nil) every format shows the plain length.
//
// Foundation only, so it is unit-tested by the Foundation suite.
public enum ShadowVoiceTime {
    public static let defaultFormat: Int32 = 0
    public static let formats: [Int32] = [0, 1, 2, 3, 4, 5]

    public static func title(_ format: Int32) -> String {
        switch format {
        case 1: return "Текущий таймкод"
        case 2: return "Прошло / всего"
        case 3: return "Осталось / всего"
        case 4: return "Прошло и процент"
        case 5: return "Процент"
        default: return "По умолчанию"
        }
    }

    // What the format looks like, for the picker: a 1:14 message at 0:22.
    public static func example(_ format: Int32) -> String {
        return text(format: format, duration: 74.0, position: 22.0)
    }

    public static func normalized(_ format: Int32) -> Int32 {
        return formats.contains(format) ? format : defaultFormat
    }

    public static func clock(_ seconds: Int32) -> String {
        let seconds = max(0, seconds)
        let hours = seconds / 3600
        let minutes = seconds / 60 % 60
        let rest = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, rest)
        }
        return String(format: "%d:%02d", minutes, rest)
    }

    // Was the player started on this message: playing, or paused mid-way.
    // A message that is not playing reports a paused status at 0.
    public static func position(isPlaying: Bool, timestamp: Double) -> Double? {
        if isPlaying || timestamp >= 1.0 {
            return max(0.0, timestamp)
        }
        return nil
    }

    // `position` nil: not playing, the plain length.
    public static func text(format: Int32, duration: Double, position: Double?) -> String {
        let total = Int32(max(0.0, duration))
        guard let position else {
            return clock(total)
        }
        let elapsed = min(total, Int32(max(0.0, position)))
        let remaining = max(0, total - elapsed)
        let percent = total > 0 ? Int(min(100, elapsed * 100 / total)) : 0
        switch normalized(format) {
        case 1:
            return clock(elapsed)
        case 2:
            return "\(clock(elapsed)) / \(clock(total))"
        case 3:
            return "-\(clock(remaining)) / \(clock(total))"
        case 4:
            return "\(clock(elapsed)) · \(percent)%"
        case 5:
            return "\(percent)%"
        default:
            return clock(remaining)
        }
    }

    // The widest text the format can show for this length, to reserve room.
    public static func widestText(format: Int32, duration: Double) -> String {
        let value = text(format: format, duration: duration, position: duration)
        return String(value.map { $0.isNumber ? "8" : $0 })
    }

    // Takes more room than Telegram's own "1:14".
    public static func isWide(_ format: Int32) -> Bool {
        return [2, 3, 4].contains(normalized(format))
    }
}

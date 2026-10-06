import Foundation

@main
struct VoiceTimeTests {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            count += 1
        }

        // A 1:14 voice message heard up to 0:22.
        check(ShadowVoiceTime.text(format: 0, duration: 74, position: 22) == "0:52", "Default: what is left")
        check(ShadowVoiceTime.text(format: 1, duration: 74, position: 22) == "0:22", "Current timecode")
        check(ShadowVoiceTime.text(format: 2, duration: 74, position: 22) == "0:22 / 1:14", "Elapsed / total")
        check(ShadowVoiceTime.text(format: 3, duration: 74, position: 22) == "-0:52 / 1:14", "Remaining / total")
        check(ShadowVoiceTime.text(format: 4, duration: 74, position: 22) == "0:22 · 29%", "Elapsed and percent")
        check(ShadowVoiceTime.text(format: 5, duration: 74, position: 22) == "29%", "Percent")

        // Not playing: every format shows the plain length.
        for format in ShadowVoiceTime.formats {
            check(ShadowVoiceTime.text(format: format, duration: 74, position: nil) == "1:14", "Idle shows the length (\(format))")
        }
        check(ShadowVoiceTime.position(isPlaying: false, timestamp: 0) == nil, "Not started is idle")
        check(ShadowVoiceTime.position(isPlaying: true, timestamp: 0) == 0, "Playing from 0 is a position")
        check(ShadowVoiceTime.position(isPlaying: false, timestamp: 22.5) == 22.5, "Paused mid-way keeps the position")

        check(ShadowVoiceTime.text(format: 2, duration: 74, position: 100) == "1:14 / 1:14", "Position is clamped to the length")
        check(ShadowVoiceTime.text(format: 5, duration: 0, position: 0) == "0%", "Zero length")
        check(ShadowVoiceTime.text(format: 2, duration: 3725, position: 61) == "1:01 / 1:02:05", "Hours")
        check(ShadowVoiceTime.text(format: 42, duration: 74, position: 22) == "0:52", "Unknown format falls back to default")
        check(ShadowVoiceTime.normalized(9) == 0 && ShadowVoiceTime.normalized(3) == 3, "Normalized")
        check(ShadowVoiceTime.widestText(format: 3, duration: 74) == "-8:88 / 8:88", "Widest text")
        check(ShadowVoiceTime.isWide(2) && ShadowVoiceTime.isWide(4) && !ShadowVoiceTime.isWide(1) && !ShadowVoiceTime.isWide(5), "Wide formats")
        check(ShadowVoiceTime.formats.count == 6 && Set(ShadowVoiceTime.formats.map { ShadowVoiceTime.title($0) }).count == 6, "Six titled formats")
        check(ShadowVoiceTime.example(2) == "0:22 / 1:14", "Example")

        print("Voice time: \(count) checks passed")
    }
}

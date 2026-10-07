import Foundation

@main
struct ReplyTimecodeTests {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            count += 1
        }

        // A 5:12 voice message heard up to 0:53.
        check(ShadowReplyTimecode.timecode(position: 53.7, duration: 312) == "0:53", "Timecode of a partly heard message")
        check(ShadowReplyTimecode.timecode(position: 3725, duration: 4000) == "1:02:05", "Hours")
        check(ShadowReplyTimecode.timecode(position: nil, duration: 312) == nil, "Not started: nothing")
        check(ShadowReplyTimecode.timecode(position: 0.4, duration: 312) == nil, "Under a second: nothing")
        check(ShadowReplyTimecode.timecode(position: 311.5, duration: 312) == nil, "Heard to the end: nothing")
        check(ShadowReplyTimecode.timecode(position: 1, duration: 1.5) == nil, "Too short a message")
        check(ShadowReplyTimecode.applying("0:53", to: "не согласен") == "0:53 не согласен", "Timecode goes first")

        // Modes.
        check(ShadowReplyTimecode.action(enabled: false, mode: 0, remembered: nil) == .skip, "Off")
        check(ShadowReplyTimecode.action(enabled: false, mode: 1, remembered: true) == .skip, "Off ignores the memory")
        check(ShadowReplyTimecode.action(enabled: true, mode: 0, remembered: false) == .add, "Always adds")
        check(ShadowReplyTimecode.action(enabled: true, mode: 1, remembered: nil) == .ask, "Ask")
        check(ShadowReplyTimecode.action(enabled: true, mode: 1, remembered: true) == .add, "Remembered yes")
        check(ShadowReplyTimecode.action(enabled: true, mode: 1, remembered: false) == .skip, "Remembered no")
        check(ShadowReplyTimecode.action(enabled: true, mode: 7, remembered: nil) == .add, "Unknown mode is Always")
        check(ShadowReplyTimecode.modeTitle(0) == "Всегда" && ShadowReplyTimecode.modeTitle(1) == "Спрашивать", "Mode titles")

        // The memory lasts 30 minutes per chat.
        let memory = ShadowReplyTimecode.Memory()
        let chat = ShadowReplyTimecode.chatKey(accountPeerId: 1, peerId: 2, threadId: nil)
        let other = ShadowReplyTimecode.chatKey(accountPeerId: 1, peerId: 3, threadId: nil)
        memory.remember(chat: chat, add: false, now: 100)
        check(memory.answer(chat: chat, now: 100 + 29 * 60) == false, "Remembered within 30 minutes")
        check(memory.answer(chat: chat, now: 100 + 30 * 60) == nil, "Forgotten after 30 minutes")
        check(memory.answer(chat: other, now: 200) == nil, "Other chats are not affected")
        check(chat != ShadowReplyTimecode.chatKey(accountPeerId: 9, peerId: 2, threadId: nil), "Accounts are separate")
        check(chat != ShadowReplyTimecode.chatKey(accountPeerId: 1, peerId: 2, threadId: 5), "Topics are separate")

        // Positions: playing extrapolates by the rate, freezing keeps where it stopped.
        let sample = ShadowReplyTimecode.PlaybackSample(timestamp: 10, duration: 60, rate: 2, isPlaying: true, generatedAt: 1000)
        check(sample.position(now: 1005) == 20, "Playing at 2x")
        check(sample.position(now: 2000) == 60, "Clamped to the length")
        let paused = ShadowReplyTimecode.PlaybackSample(timestamp: 10, duration: 60, rate: 1, isPlaying: false, generatedAt: 1000)
        check(paused.position(now: 5000) == 10, "Paused stays")

        let positions = ShadowReplyTimecode.Positions(limit: 2)
        positions.record(key: "a", sample: sample)
        positions.freeze(key: "a", now: 1003)
        check(positions.sample(key: "a")?.position(now: 9999) == 16, "Frozen where the player left it")
        check(positions.sample(key: "a")?.isPlaying == false, "Frozen is not playing")
        positions.record(key: "b", sample: paused)
        positions.record(key: "c", sample: paused)
        check(positions.sample(key: "a") == nil && positions.sample(key: "c") != nil, "Oldest dropped over the limit")
        positions.record(key: "c", sample: sample)
        check(positions.sample(key: "b") != nil, "Updating a key does not drop others")

        print("Reply timecode: \(count) checks passed")
    }
}

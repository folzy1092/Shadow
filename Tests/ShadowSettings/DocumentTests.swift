import Foundation

@main
struct DocumentTests {
    static func main() throws {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            count += 1
        }
        func expectFailure(_ name: String, _ action: () throws -> Void) {
            do { try action(); preconditionFailure(name) }
            catch { count += 1 }
        }
        func fixture(_ settings: String, version: Int = 1, format: String = "shadow-settings") -> Data {
            return Data("{\"format\":\"\(format)\",\"version\":\(version),\"exportedAt\":\"2026-09-03T12:00:00Z\",\"settings\":\(settings)}".utf8)
        }
        let document = try ShadowSettingsDocument(settings: [
            "ghostMode": .bool(true), "compactBottomBar": .bool(false),
            "editedIndicatorText": .text("✎"), "attachmentSizeLimit": .integer(12884901888)
        ], date: Date(timeIntervalSince1970: 0))
        let encoded = try document.encoded()
        let roundTrip = try ShadowSettingsDocument.decode(encoded)
        check(roundTrip == document, "Round trip must preserve all values")
        let object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        let settings = object["settings"] as! [String: Any]
        check(settings["ghostMode"] as? Bool == true, "JSON uses booleans, not Postbox's 0/1 encoding")
        check(object["format"] as? String == "shadow-settings", "Format marker")

        let ignored = try ShadowSettingsDocument.decode(fixture("{\"ghostMode\":true,\"futureOption\":{\"nested\":[1,2]},\"ghostLastSeenTimestamp\":5}"))
        check(ignored.settings.count == 1, "Unknown and state fields must be ignored")
        let full = try ShadowSettingsDocument.decode(fixture("{\"spoofProfilePhoneValue\":\"+7 000\",\"customBannerEnabled\":true,\"messageFilters\":\"[]\"}"))
        check(full.settings["spoofProfilePhoneValue"] == .text("+7 000") && full.settings["customBannerEnabled"] == .bool(true) && full.settings["messageFilters"] == .text("[]"), "Profile spoof, banner and lists are transferable")
        expectFailure("Lists must be JSON text") { _ = try ShadowSettingsDocument.decode(fixture("{\"messageFilters\":[1]}")) }
        let partial = try ShadowSettingsDocument.decode(fixture("{\"compactBottomBar\":true}"))
        check(partial.settings["ghostMode"] == nil, "Missing values must remain absent")
        let filterPlaceholder = try ShadowSettingsDocument.decode(fixture("{\"messageFilterShowPlaceholder\":false}"))
        check(filterPlaceholder.settings["messageFilterShowPlaceholder"] == .bool(false), "Filter placeholder toggle is transferable")
        expectFailure("Invalid format") { _ = try ShadowSettingsDocument.decode(fixture("{\"ghostMode\":true}", format: "other")) }
        expectFailure("Future version") { _ = try ShadowSettingsDocument.decode(fixture("{\"ghostMode\":true}", version: 2)) }
        expectFailure("Unsupported old version") { _ = try ShadowSettingsDocument.decode(fixture("{\"ghostMode\":true}", version: 0)) }
        expectFailure("Malformed JSON") { _ = try ShadowSettingsDocument.decode(Data("{".utf8)) }
        expectFailure("Invalid bool string") { _ = try ShadowSettingsDocument.decode(fixture("{\"ghostMode\":\"yes\"}")) }
        expectFailure("Numeric bool") { _ = try ShadowSettingsDocument.decode(fixture("{\"ghostMode\":1}")) }
        expectFailure("Null bool") { _ = try ShadowSettingsDocument.decode(fixture("{\"ghostMode\":null}")) }
        expectFailure("Negative cleanup interval") { _ = try ShadowSettingsDocument.decode(fixture("{\"mediaAutoCleanInterval\":-1}")) }
        expectFailure("Invalid cleanup interval") { _ = try ShadowSettingsDocument.decode(fixture("{\"mediaAutoCleanInterval\":42}")) }
        expectFailure("Integer overflow") { _ = try ShadowSettingsDocument.decode(fixture("{\"attachmentSizeLimit\":9223372036854775808}")) }
        expectFailure("Empty settings") { _ = try ShadowSettingsDocument.decode(fixture("{}")) }
        expectFailure("Only unknown fields") { _ = try ShadowSettingsDocument.decode(fixture("{\"token\":\"secret\"}")) }
        expectFailure("Large document") { _ = try ShadowSettingsDocument.decode(Data(repeating: 32, count: ShadowSettingsDocument.maximumBytes + 1)) }
        expectFailure("State fields cannot be exported") { _ = try ShadowSettingsDocument(settings: ["ghostLastSeenTimestamp": .integer(1)]) }
        expectFailure("Too long spoof value") { _ = try ShadowSettingsDocument(settings: ["spoofProfileIdValue": .text(String(repeating: "1", count: 65))]) }
        expectFailure("Wrong value type on export") { _ = try ShadowSettingsDocument(settings: ["ghostMode": .integer(1)]) }
        expectFailure("Overlong marker") { _ = try ShadowSettingsDocument(settings: ["editedIndicatorText": .text(String(repeating: "a", count: 65))]) }
        let marker = try ShadowSettingsDocument(settings: ["editedIndicatorText": .text(String(repeating: "a", count: 64))])
        check(marker.settings.count == 1, "64-character marker is accepted")
        let scroll = try ShadowSettingsDocument(settings: ["bottomBarScrollMode": .integer(2)])
        check(scroll.settings["bottomBarScrollMode"] == .integer(2), "Scroll mode is portable")
        let bothDirections = try ShadowSettingsDocument(settings: ["bottomBarScrollMode": .integer(3)])
        let restoredScroll = try ShadowSettingsDocument.decode(bothDirections.encoded())
        check(restoredScroll.settings["bottomBarScrollMode"] == .integer(3), "Bidirectional scroll mode is portable")
        expectFailure("Unsupported scroll mode") { _ = try ShadowSettingsDocument(settings: ["bottomBarScrollMode": .integer(4)]) }
        let voiceTime = try ShadowSettingsDocument(settings: ["voiceTimeFormat": .integer(5), "voiceTimeRoundVideos": .bool(false), "voiceTimeInPlayer": .bool(true)])
        let restoredVoiceTime = try ShadowSettingsDocument.decode(voiceTime.encoded())
        check(restoredVoiceTime.settings["voiceTimeFormat"] == .integer(5), "Voice time format is portable")
        check(restoredVoiceTime.settings["voiceTimeInPlayer"] == .bool(true), "Voice time in player is portable")
        expectFailure("Unsupported voice time format") { _ = try ShadowSettingsDocument(settings: ["voiceTimeFormat": .integer(6)]) }
        let replyTimecode = try ShadowSettingsDocument(settings: ["replyTimecode": .bool(true), "replyTimecodeMode": .integer(0)])
        let restoredReplyTimecode = try ShadowSettingsDocument.decode(replyTimecode.encoded())
        check(restoredReplyTimecode.settings["replyTimecode"] == .bool(true), "Reply timecode is portable")
        check(restoredReplyTimecode.settings["replyTimecodeMode"] == .integer(0), "Reply timecode mode is portable")
        let chatVoiceSpeed = try ShadowSettingsDocument.decode(ShadowSettingsDocument(settings: ["chatVoiceSpeed": .bool(true)]).encoded())
        check(chatVoiceSpeed.settings["chatVoiceSpeed"] == .bool(true), "Chat voice speed is portable")
        let ads = try ShadowSettingsDocument.decode(ShadowSettingsDocument(settings: ["adFilterChannels": .bool(false), "adFilterGroups": .bool(true), "adFilterForwarded": .bool(true), "adHideCompletely": .bool(false)]).encoded())
        check(ads.settings["adFilterChannels"] == .bool(false) && ads.settings["adFilterGroups"] == .bool(true), "Ad places are portable")
        check(ads.settings["adFilterForwarded"] == .bool(true) && ads.settings["adHideCompletely"] == .bool(false), "Ad hiding is portable")
        let streak = try ShadowSettingsDocument.decode(ShadowSettingsDocument(settings: ["showChatStreak": .bool(false)]).encoded())
        check(streak.settings["showChatStreak"] == .bool(false), "Chat streak toggle is portable")
        let feed = try ShadowSettingsDocument.decode(ShadowSettingsDocument(settings: ["feedEnabled": .bool(true), "feedPosition": .integer(2), "feedAutoplay": .bool(false)]).encoded())
        check(feed.settings["feedEnabled"] == .bool(true) && feed.settings["feedPosition"] == .integer(2) && feed.settings["feedAutoplay"] == .bool(false), "Feed settings are portable")
        expectFailure("Unsupported feed position") { _ = try ShadowSettingsDocument(settings: ["feedPosition": .integer(3)]) }
        expectFailure("Unsupported reply timecode mode") { _ = try ShadowSettingsDocument(settings: ["replyTimecodeMode": .integer(2)]) }
        let ghostPolicy = try ShadowSettingsDocument(settings: ["ghostAccountMode": .integer(3)])
        let restoredGhostPolicy = try ShadowSettingsDocument.decode(ghostPolicy.encoded())
        check(restoredGhostPolicy.settings["ghostAccountMode"] == .integer(3), "Ghost account policy is portable")
        expectFailure("Unsupported ghost account policy") { _ = try ShadowSettingsDocument(settings: ["ghostAccountMode": .integer(4)]) }
        let iconColors = try ShadowSettingsDocument(settings: ["monochromeSettingsIcons": .bool(true), "settingsIconBackgroundColor": .integer(0x1C1C1E), "settingsIconGlyphColor": .integer(0xFFFFFF)])
        let restoredIconColors = try ShadowSettingsDocument.decode(iconColors.encoded())
        check(restoredIconColors.settings["settingsIconBackgroundColor"] == .integer(0x1C1C1E), "Settings icon colors are portable")
        expectFailure("Icon color outside RGB") { _ = try ShadowSettingsDocument(settings: ["settingsIconGlyphColor": .integer(0x1000000)]) }
        let bots = try ShadowSettingsDocument(settings: ["preferUsernameForBots": .bool(true)])
        let restoredBots = try ShadowSettingsDocument.decode(bots.encoded())
        check(restoredBots.settings["preferUsernameForBots"] == .bool(true), "Bot names preference is portable")

        let screenshotColor = Int64(Int32(bitPattern: 0xFF12AB34))
        let screenshotDocument = try ShadowSettingsDocument(settings: [
            "screenshotBackground": .integer(2),
            "screenshotCustomColorARGB": .integer(screenshotColor)
        ])
        let restoredScreenshotDocument = try ShadowSettingsDocument.decode(screenshotDocument.encoded())
        check(restoredScreenshotDocument.settings["screenshotBackground"] == .integer(2), "Screenshot custom-color mode is portable")
        check(restoredScreenshotDocument.settings["screenshotCustomColorARGB"] == .integer(screenshotColor), "Screenshot custom color ARGB is portable")

        let legacyBlackScreenshot = try ShadowSettingsDocument(settings: ["screenshotBackground": .integer(3)])
        check(legacyBlackScreenshot.settings["screenshotBackground"] == .integer(3), "Legacy screenshot black background remains importable")
        expectFailure("Screenshot ARGB above Int32") {
            _ = try ShadowSettingsDocument(settings: ["screenshotCustomColorARGB": .integer(Int64(Int32.max) + 1)])
        }
        expectFailure("Screenshot ARGB below Int32") {
            _ = try ShadowSettingsDocument(settings: ["screenshotCustomColorARGB": .integer(Int64(Int32.min) - 1)])
        }

        print("Shadow settings document: \(count) checks passed")
    }
}

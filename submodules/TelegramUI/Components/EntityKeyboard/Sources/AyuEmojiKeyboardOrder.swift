import Foundation

// Shadow: "regular emoji first" — by default Telegram lists every custom-emoji
// pack (mostly premium sticker-set-backed) BEFORE the plain Unicode emoji group
// in the emoji keyboard, because emojiInputData (EmojiPagerContentSignals.swift)
// only appends the "static" Unicode group after all the custom-pack groups have
// been built. Reference: Swiftgram's SGEmojiKeyboardDefaultFirst, same idea —
// move the "static" group to sit right after "recent" instead of last.
//
// Pure array reorder, no I/O — called from EntityKeyboard.swift on the already-
// built panelItemGroups/contentItemGroups, gated on the fork's own setting.
func ayuReorderEmojiKeyboardItems(_ items: [EmojiPagerContentComponent.ItemGroup]) -> [EmojiPagerContentComponent.ItemGroup] {
    var items = items
    let staticEmojisIndex = items.firstIndex { item in
        if let groupId = item.groupId.base as? String, groupId == "static" {
            return true
        }
        return false
    }
    let recentEmojisIndex = items.firstIndex { item in
        if let groupId = item.groupId.base as? String, groupId == "recent" {
            return true
        }
        return false
    }
    if let staticEmojisIndex {
        let staticEmojiItem = items.remove(at: staticEmojisIndex)
        items.insert(staticEmojiItem, at: (recentEmojisIndex ?? -1) + 1)
    }
    return items
}

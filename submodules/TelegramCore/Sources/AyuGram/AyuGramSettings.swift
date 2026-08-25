import Foundation
import Postbox
import SwiftSignalKit

// AyuGram fork settings. Kept in a single, self-contained file so it can be
// re-applied on top of upstream with minimal merge friction. The preferences
// key uses a deliberately high raw value (well above upstream's range) to avoid
// colliding with keys that upstream may add over time.
public extension PreferencesKeys {
    static let ayuGramSettings: ValueBoxKey = {
        let key = ValueBoxKey(length: 4)
        key.setInt32(0, value: 1000)
        return key
    }()
}

public struct AyuGramSettings: Codable, Equatable {
    // Anti-deletion
    public var keepDeletedMessages: Bool
    public var saveEditHistory: Bool
    // Keep opened self-destruct / view-once media in the chat instead of letting
    // it expire (and don't tell the sender it was opened).
    public var keepSelfDestructMedia: Bool
    // GHOST MODE (master presence gate)
    // Single master toggle. When off, no Ghost feature can take effect no
    // matter what its own granular toggle is set to — every effective gate
    // below is `ghostMode && <granular flag>`. The recording / uploading /
    // consumed gates have no granular toggle and follow Ghost Mode directly.
    public var ghostMode: Bool
    // Presence hiding
    public var hideOnlineStatus: Bool
    public var hideTyping: Bool
    // Don't send read receipts to the server, so reading a chat never marks you
    // online and the sender never sees the "read" ticks.
    public var hideReadReceipts: Bool
    // Don't report viewed stories to their author.
    public var hideStoryViews: Bool
    // Before opening someone else's story while hideStoryViews is off, ask
    // whether to turn hideStoryViews on first. Never asked for own stories, and
    // never asked at all when hideStoryViews is already on.
    public var askBeforeStoryView: Bool
    // DELAYED SEND (Ghost)
    // Route outgoing messages through Telegram's native Scheduled Messages
    // (schedule_date) with a short delay instead of sending them immediately.
    // Scheduled sends are delivered by the server later and do NOT bump the
    // account's last-seen / online status — so the user never flashes online at
    // the moment of sending. Only effective while the full Ghost Mode is on.
    public var sendViaScheduled: Bool
    // Also re-assert "offline" right after a send completes, as an extra layer
    // for the (non-scheduled) fallback path. Only effective under Ghost Mode.
    public var sendWithoutOnline: Bool

    // MESSAGES
    // Render message timestamps as HH:MM:SS instead of HH:MM.
    public var showMessageSeconds: Bool
    // Replace the "Изменено" ("edited") text label next to the timestamp with a
    // small pencil icon, Swiftgram/exteraGram-style, instead of the localized word.
    public var editedIndicatorAsPencil: Bool
    // When editedIndicatorAsPencil is on, overrides the default "✎" with this
    // string instead (custom text or a single emoji). Empty = use the default.
    public var editedIndicatorText: String
    // Overrides the default "🗑" anti-delete badge (StringForMessageTimestampStatus)
    // with this string instead (custom text or a single emoji). Empty = default.
    // Unlike editedIndicatorAsPencil this has no separate on/off switch: the
    // anti-delete badge itself is always shown for a kept-deleted message, this
    // setting only changes what glyph it uses.
    public var deletedIndicatorText: String
    // In the emoji keyboard, list the plain Unicode emoji group right after
    // "recent" instead of after every custom/premium emoji pack (Swiftgram-style).
    public var regularEmojiFirst: Bool
    // Double-tapping one of your own messages opens the edit interface.
    public var doubleTapToEdit: Bool
    // Show the exact clock time of a peer's last-seen in the chat header
    // subtitle (e.g. "last seen at 12:10") instead of Telegram's fuzzy relative
    // phrase ("last seen 1 hour ago"), whenever the client actually has a
    // precise timestamp to show.
    public var showExactLastSeen: Bool
    // When showExactLastSeen is on, additionally append seconds to the exact
    // last-seen time (e.g. "last seen at 12:10:12" instead of "12:10"). Has no
    // effect unless showExactLastSeen is enabled.
    public var showExactLastSeenSeconds: Bool

    // Render channel (broadcast) posts at full bubble width so long articles and
    // news posts use more horizontal space. Only affects broadcast channels;
    // private chats and groups are untouched.
    public var wideChannelPosts: Bool

    // Show the exact view count on channel posts (e.g. "5678") instead of
    // Telegram's default abbreviated form ("5.6K"). Only affects post views;
    // reply/reaction/forward counts elsewhere are untouched.
    public var showExactViewCounts: Bool

    // Show how many times a message was forwarded, next to the timestamp (after
    // the view count). Server only provides this for channel posts, like views.
    public var showForwardCount: Bool

    // CHATS
    // Completely hide the "All Chats" folder tab from the chat list.
    public var hideAllChatsFolder: Bool
    // Move the chat-folder tab strip from below the search bar to a floating
    // panel above the bottom tab bar (Swiftgram-style). Independent of the
    // other two bottom-bar toggles below.
    public var foldersAtBottom: Bool
    // Hide the floating search button that normally sits in the bottom tab
    // bar next to Contacts/Chats/Settings. The main search field at the top
    // of the chat list is never affected.
    public var hideBottomSearch: Bool
    // Render the bottom tab bar (Contacts/Chats/Settings) without text labels
    // and at a reduced height, similar to a compact iOS tab bar.
    public var compactBottomBar: Bool
    // Neutralise copy-protection: allow copy / forward / save in protected
    // (copy-restricted) chats and private channels, exactly like AyuGram.
    public var allowSaveRestrictedContent: Bool

    // Start round-video ("кружки") recording with the rear camera by default
    // instead of the front camera.
    public var roundVideoUseBackCamera: Bool

    // Show the live-camera tile as the first cell of the default chat
    // attachment/gallery picker grid.
    public var showCameraTile: Bool
    // Start the camera tile's live viewfinder preview immediately instead of a
    // static icon until tapped. Only meaningful while showCameraTile is on.
    public var cameraTileLivePreview: Bool

    // Ask for confirmation before placing an outgoing audio/video call.
    // Protects against accidental taps; never affects incoming calls.
    public var confirmCalls: Bool

    // MEDIA PERSISTENCE (fork-local gallery)
    // Back up view-once / self-destruct media to the private AyuGram gallery
    // before it self-destructs, so it survives locally even after the sender's
    // copy expires. Independent of Ghost Master.
    public var saveDestructingMedia: Bool
    // Auto-save every incoming media (photos, videos, documents, voice, round
    // videos) into the private AyuGram gallery, independent of the system
    // "Save to Camera Roll" and of copy-protection.
    public var saveAllIncomingMedia: Bool
    // Periodic auto-clean of the private gallery by age. Value is the maximum age
    // in seconds; 0 disables the age limit. Allowed steps (days): 86400 (1),
    // 259200 (3), 604800 (7), 1209600 (14), 2592000 (30), 7776000 (90),
    // 15552000 (180), 31536000 (365).
    public var mediaAutoCleanInterval: Int32
    // Maximum total size of the private gallery in bytes; 0 means unlimited. When
    // the gallery exceeds this size the oldest files are removed until it fits.
    // Works together with the age limit — both can be active at once.
    public var attachmentSizeLimit: Int64
    // When auto-cleaning, never remove media that belongs to a pinned chat.
    public var mediaAutoCleanKeepPinned: Bool
    // When auto-cleaning, never remove media that belongs to a channel.
    public var mediaAutoCleanKeepChannels: Bool
    // When auto-cleaning, never remove media that belongs to a bot.
    public var mediaAutoCleanKeepBots: Bool

    // PROFILES
    // Show the peer's numeric ID (Bot API form) on the profile screen.
    public var showProfileId: Bool
    // Show the data-center (DC) the peer's profile photo is served from.
    public var showProfileDC: Bool
    // Show an estimated account registration date on the profile screen.
    public var showRegistrationDate: Bool
    // Completely hide the own phone-number row from the Settings/profile screen.
    // Unlike the visual phone spoof, this removes the plate entirely.
    public var hideOwnPhoneNumber: Bool

    // MISC — visual-only profile spoofing, intended for screenshots. These NEVER
    // touch real account data: not UserConfig, AccountState, PeerId, the real
    // phone number, nor anything sent to the server / used in API calls. They
    // only override what the profile UI renders locally.
    public var spoofProfileIdEnabled: Bool
    public var spoofProfileIdValue: String
    public var spoofProfileDcEnabled: Bool
    public var spoofProfileDcValue: String
    public var spoofProfilePhoneEnabled: Bool
    public var spoofProfilePhoneValue: String

    // CUSTOM BANNER — when on, a user-picked image (stored via AyuSavedMedia
    // under a fixed name) is drawn behind the chat-list top region. Off by
    // default; when off, or when no image is stored, the chat list looks stock.
    public var customBannerEnabled: Bool

    // CUSTOM PROFILE BACKGROUND — visual-only, like the misc profile spoofs
    // above: a user-picked image (stored via AyuSavedMedia) drawn behind the
    // avatar/name on the LOCAL "Мой профиль" screen only. Never sent to the
    // server, never seen by other users or on other Shadow instances. When on,
    // it replaces Telegram's own profile-color/status cover for that screen.
    public var customProfileBackgroundEnabled: Bool

    // Применять кастомный фон профиля для ВСЕХ профилей (друзей, контактов),
    // а не только для "Мой профиль". Работает только когда customProfileBackgroundEnabled = true.
    public var customProfileBackgroundForOthers: Bool

    // Применять кастомный фон профиля в экране Settings (где переключение аккаунтов, сверху мини-профиль).
    // Работает только когда customProfileBackgroundEnabled = true.
    public var customProfileBackgroundForSettings: Bool

    public static var defaultSettings: AyuGramSettings {
        return AyuGramSettings(
            keepDeletedMessages: true,
            saveEditHistory: true,
            keepSelfDestructMedia: true,
            ghostMode: false,
            hideOnlineStatus: true,
            hideTyping: false,
            hideReadReceipts: true,
            hideStoryViews: true,
            askBeforeStoryView: false,
            sendViaScheduled: false,
            sendWithoutOnline: false,
            showMessageSeconds: false,
            editedIndicatorAsPencil: false,
            editedIndicatorText: "",
            deletedIndicatorText: "",
            regularEmojiFirst: false,
            doubleTapToEdit: false,
            showExactLastSeen: false,
            showExactLastSeenSeconds: false,
            wideChannelPosts: false,
            showExactViewCounts: false,
            showForwardCount: false,
            hideAllChatsFolder: false,
            foldersAtBottom: false,
            hideBottomSearch: false,
            compactBottomBar: false,
            allowSaveRestrictedContent: true,
            roundVideoUseBackCamera: false,
            showCameraTile: true,
            cameraTileLivePreview: true,
            confirmCalls: false,
            saveDestructingMedia: true,
            saveAllIncomingMedia: false,
            mediaAutoCleanInterval: 0,
            attachmentSizeLimit: 0,
            mediaAutoCleanKeepPinned: true,
            mediaAutoCleanKeepChannels: false,
            mediaAutoCleanKeepBots: false,
            showProfileId: true,
            showProfileDC: true,
            showRegistrationDate: true,
            hideOwnPhoneNumber: false,
            spoofProfileIdEnabled: false,
            spoofProfileIdValue: "",
            spoofProfileDcEnabled: false,
            spoofProfileDcValue: "",
            spoofProfilePhoneEnabled: false,
            spoofProfilePhoneValue: "",
            customBannerEnabled: false,
            customProfileBackgroundEnabled: false,
            customProfileBackgroundForOthers: false,
            customProfileBackgroundForSettings: false
        )
    }

    // Reading a chat sends a read receipt, which the server also treats as
    // activity and flips you "online". So whenever online is hidden we must also
    // suppress read receipts — otherwise opening a message would reveal you.
    // Ghost Mode is the master switch: with it off, no granular toggle below
    // can suppress anything on its own.
    public var suppressReadReceipts: Bool {
        return self.ghostMode && (self.hideReadReceipts || self.hideOnlineStatus)
    }

    // MARK: - Effective presence gates
    //
    // Ghost Mode is the master switch; each effective gate is
    // `ghostMode && <granular flag>`. Low-level interception points read these
    // effective properties, never the raw flags, so the master toggle can gate
    // everything at once — turning Ghost Mode off disables every Ghost feature
    // regardless of the state of its own granular toggle.
    public var effectiveHideOnline: Bool {
        return self.ghostMode && self.hideOnlineStatus
    }
    public var effectiveHideTyping: Bool {
        return self.ghostMode && self.hideTyping
    }
    public var effectiveHideRecording: Bool {
        return self.ghostMode
    }
    public var effectiveHideUploading: Bool {
        return self.ghostMode
    }
    public var effectiveHideConsumed: Bool {
        return self.ghostMode
    }
    // Story-view hiding and its confirmation prompt are also gated by Ghost
    // Mode: with the master switch off, viewing a story must behave exactly
    // like stock Telegram (report the view, never prompt), regardless of what
    // the granular toggles are set to.
    public var effectiveHideStoryViews: Bool {
        return self.ghostMode && self.hideStoryViews
    }
    public var effectiveAskBeforeStoryView: Bool {
        return self.ghostMode && self.askBeforeStoryView
    }
    // Delayed send only arms under the full Ghost Mode (per spec: "работает
    // только при включённом полном режиме призрака"). The stored `sendViaScheduled`
    // flag lets the user opt out even while Ghost Mode is on.
    public var effectiveSendViaScheduled: Bool {
        return self.ghostMode && self.sendViaScheduled
    }
    public var effectiveSendWithoutOnline: Bool {
        return self.ghostMode && self.sendWithoutOnline
    }

    public init(
        keepDeletedMessages: Bool,
        saveEditHistory: Bool,
        keepSelfDestructMedia: Bool,
        ghostMode: Bool,
        hideOnlineStatus: Bool,
        hideTyping: Bool,
        hideReadReceipts: Bool,
        hideStoryViews: Bool,
        askBeforeStoryView: Bool,
        sendViaScheduled: Bool,
        sendWithoutOnline: Bool,
        showMessageSeconds: Bool,
        editedIndicatorAsPencil: Bool,
        editedIndicatorText: String,
        deletedIndicatorText: String,
        regularEmojiFirst: Bool,
        doubleTapToEdit: Bool,
        showExactLastSeen: Bool,
        showExactLastSeenSeconds: Bool,
        wideChannelPosts: Bool,
        showExactViewCounts: Bool,
        showForwardCount: Bool,
        hideAllChatsFolder: Bool,
        foldersAtBottom: Bool,
        hideBottomSearch: Bool,
        compactBottomBar: Bool,
        allowSaveRestrictedContent: Bool,
        roundVideoUseBackCamera: Bool,
        showCameraTile: Bool,
        cameraTileLivePreview: Bool,
        confirmCalls: Bool,
        saveDestructingMedia: Bool,
        saveAllIncomingMedia: Bool,
        mediaAutoCleanInterval: Int32,
        attachmentSizeLimit: Int64,
        mediaAutoCleanKeepPinned: Bool,
        mediaAutoCleanKeepChannels: Bool,
        mediaAutoCleanKeepBots: Bool,
        showProfileId: Bool,
        showProfileDC: Bool,
        showRegistrationDate: Bool,
        hideOwnPhoneNumber: Bool,
        spoofProfileIdEnabled: Bool,
        spoofProfileIdValue: String,
        spoofProfileDcEnabled: Bool,
        spoofProfileDcValue: String,
        spoofProfilePhoneEnabled: Bool,
        spoofProfilePhoneValue: String,
        customBannerEnabled: Bool,
        customProfileBackgroundEnabled: Bool,
        customProfileBackgroundForOthers: Bool,
        customProfileBackgroundForSettings: Bool
    ) {
        self.keepDeletedMessages = keepDeletedMessages
        self.saveEditHistory = saveEditHistory
        self.keepSelfDestructMedia = keepSelfDestructMedia
        self.ghostMode = ghostMode
        self.hideOnlineStatus = hideOnlineStatus
        self.hideTyping = hideTyping
        self.hideReadReceipts = hideReadReceipts
        self.hideStoryViews = hideStoryViews
        self.askBeforeStoryView = askBeforeStoryView
        self.sendViaScheduled = sendViaScheduled
        self.sendWithoutOnline = sendWithoutOnline
        self.showMessageSeconds = showMessageSeconds
        self.editedIndicatorAsPencil = editedIndicatorAsPencil
        self.editedIndicatorText = editedIndicatorText
        self.deletedIndicatorText = deletedIndicatorText
        self.regularEmojiFirst = regularEmojiFirst
        self.doubleTapToEdit = doubleTapToEdit
        self.showExactLastSeen = showExactLastSeen
        self.showExactLastSeenSeconds = showExactLastSeenSeconds
        self.wideChannelPosts = wideChannelPosts
        self.showExactViewCounts = showExactViewCounts
        self.showForwardCount = showForwardCount
        self.hideAllChatsFolder = hideAllChatsFolder
        self.foldersAtBottom = foldersAtBottom
        self.hideBottomSearch = hideBottomSearch
        self.compactBottomBar = compactBottomBar
        self.allowSaveRestrictedContent = allowSaveRestrictedContent
        self.roundVideoUseBackCamera = roundVideoUseBackCamera
        self.showCameraTile = showCameraTile
        self.cameraTileLivePreview = cameraTileLivePreview
        self.confirmCalls = confirmCalls
        self.saveDestructingMedia = saveDestructingMedia
        self.saveAllIncomingMedia = saveAllIncomingMedia
        self.mediaAutoCleanInterval = mediaAutoCleanInterval
        self.attachmentSizeLimit = attachmentSizeLimit
        self.mediaAutoCleanKeepPinned = mediaAutoCleanKeepPinned
        self.mediaAutoCleanKeepChannels = mediaAutoCleanKeepChannels
        self.mediaAutoCleanKeepBots = mediaAutoCleanKeepBots
        self.showProfileId = showProfileId
        self.showProfileDC = showProfileDC
        self.showRegistrationDate = showRegistrationDate
        self.hideOwnPhoneNumber = hideOwnPhoneNumber
        self.spoofProfileIdEnabled = spoofProfileIdEnabled
        self.spoofProfileIdValue = spoofProfileIdValue
        self.spoofProfileDcEnabled = spoofProfileDcEnabled
        self.spoofProfileDcValue = spoofProfileDcValue
        self.spoofProfilePhoneEnabled = spoofProfilePhoneEnabled
        self.spoofProfilePhoneValue = spoofProfilePhoneValue
        self.customBannerEnabled = customBannerEnabled
        self.customProfileBackgroundEnabled = customProfileBackgroundEnabled
        self.customProfileBackgroundForOthers = customProfileBackgroundForOthers
        self.customProfileBackgroundForSettings = customProfileBackgroundForSettings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)
        self.keepDeletedMessages = ((try container.decodeIfPresent(Int32.self, forKey: "keepDeletedMessages")) ?? 1) != 0
        self.saveEditHistory = ((try container.decodeIfPresent(Int32.self, forKey: "saveEditHistory")) ?? 1) != 0
        self.keepSelfDestructMedia = ((try container.decodeIfPresent(Int32.self, forKey: "keepSelfDestructMedia")) ?? 1) != 0
        self.ghostMode = ((try container.decodeIfPresent(Int32.self, forKey: "ghostMode")) ?? 0) != 0
        self.hideOnlineStatus = ((try container.decodeIfPresent(Int32.self, forKey: "hideOnlineStatus")) ?? 0) != 0
        self.hideTyping = ((try container.decodeIfPresent(Int32.self, forKey: "hideTyping")) ?? 0) != 0
        self.hideReadReceipts = ((try container.decodeIfPresent(Int32.self, forKey: "hideReadReceipts")) ?? 0) != 0
        self.hideStoryViews = ((try container.decodeIfPresent(Int32.self, forKey: "hideStoryViews")) ?? 0) != 0
        self.askBeforeStoryView = ((try container.decodeIfPresent(Int32.self, forKey: "askBeforeStoryView")) ?? 0) != 0
        self.sendViaScheduled = ((try container.decodeIfPresent(Int32.self, forKey: "sendViaScheduled")) ?? 0) != 0
        self.sendWithoutOnline = ((try container.decodeIfPresent(Int32.self, forKey: "sendWithoutOnline")) ?? 0) != 0
        self.showMessageSeconds = ((try container.decodeIfPresent(Int32.self, forKey: "showMessageSeconds")) ?? 0) != 0
        self.editedIndicatorAsPencil = ((try container.decodeIfPresent(Int32.self, forKey: "editedIndicatorAsPencil")) ?? 0) != 0
        self.editedIndicatorText = (try container.decodeIfPresent(String.self, forKey: "editedIndicatorText")) ?? ""
        self.deletedIndicatorText = (try container.decodeIfPresent(String.self, forKey: "deletedIndicatorText")) ?? ""
        self.regularEmojiFirst = ((try container.decodeIfPresent(Int32.self, forKey: "regularEmojiFirst")) ?? 0) != 0
        self.doubleTapToEdit = ((try container.decodeIfPresent(Int32.self, forKey: "doubleTapToEdit")) ?? 0) != 0
        self.showExactLastSeen = ((try container.decodeIfPresent(Int32.self, forKey: "showExactLastSeen")) ?? 0) != 0
        self.showExactLastSeenSeconds = ((try container.decodeIfPresent(Int32.self, forKey: "showExactLastSeenSeconds")) ?? 0) != 0
        self.wideChannelPosts = ((try container.decodeIfPresent(Int32.self, forKey: "wideChannelPosts")) ?? 0) != 0
        self.showExactViewCounts = ((try container.decodeIfPresent(Int32.self, forKey: "showExactViewCounts")) ?? 0) != 0
        self.showForwardCount = ((try container.decodeIfPresent(Int32.self, forKey: "showForwardCount")) ?? 0) != 0
        self.hideAllChatsFolder = ((try container.decodeIfPresent(Int32.self, forKey: "hideAllChatsFolder")) ?? 0) != 0
        self.foldersAtBottom = ((try container.decodeIfPresent(Int32.self, forKey: "foldersAtBottom")) ?? 0) != 0
        self.hideBottomSearch = ((try container.decodeIfPresent(Int32.self, forKey: "hideBottomSearch")) ?? 0) != 0
        self.compactBottomBar = ((try container.decodeIfPresent(Int32.self, forKey: "compactBottomBar")) ?? 0) != 0
        self.allowSaveRestrictedContent = ((try container.decodeIfPresent(Int32.self, forKey: "allowSaveRestrictedContent")) ?? 1) != 0
        self.roundVideoUseBackCamera = ((try container.decodeIfPresent(Int32.self, forKey: "roundVideoUseBackCamera")) ?? 0) != 0
        self.showCameraTile = ((try container.decodeIfPresent(Int32.self, forKey: "showCameraTile")) ?? 1) != 0
        self.cameraTileLivePreview = ((try container.decodeIfPresent(Int32.self, forKey: "cameraTileLivePreview")) ?? 1) != 0
        self.confirmCalls = ((try container.decodeIfPresent(Int32.self, forKey: "confirmCalls")) ?? 0) != 0
        self.saveDestructingMedia = ((try container.decodeIfPresent(Int32.self, forKey: "saveDestructingMedia")) ?? 1) != 0
        self.saveAllIncomingMedia = ((try container.decodeIfPresent(Int32.self, forKey: "saveAllIncomingMedia")) ?? 0) != 0
        self.mediaAutoCleanInterval = (try container.decodeIfPresent(Int32.self, forKey: "mediaAutoCleanInterval")) ?? 0
        self.attachmentSizeLimit = (try container.decodeIfPresent(Int64.self, forKey: "attachmentSizeLimit")) ?? 0
        self.mediaAutoCleanKeepPinned = ((try container.decodeIfPresent(Int32.self, forKey: "mediaAutoCleanKeepPinned")) ?? 1) != 0
        self.mediaAutoCleanKeepChannels = ((try container.decodeIfPresent(Int32.self, forKey: "mediaAutoCleanKeepChannels")) ?? 0) != 0
        self.mediaAutoCleanKeepBots = ((try container.decodeIfPresent(Int32.self, forKey: "mediaAutoCleanKeepBots")) ?? 0) != 0
        self.showProfileId = ((try container.decodeIfPresent(Int32.self, forKey: "showProfileId")) ?? 1) != 0
        self.showProfileDC = ((try container.decodeIfPresent(Int32.self, forKey: "showProfileDC")) ?? 1) != 0
        self.showRegistrationDate = ((try container.decodeIfPresent(Int32.self, forKey: "showRegistrationDate")) ?? 1) != 0
        self.hideOwnPhoneNumber = ((try container.decodeIfPresent(Int32.self, forKey: "hideOwnPhoneNumber")) ?? 0) != 0
        self.spoofProfileIdEnabled = ((try container.decodeIfPresent(Int32.self, forKey: "spoofProfileIdEnabled")) ?? 0) != 0
        self.spoofProfileIdValue = (try container.decodeIfPresent(String.self, forKey: "spoofProfileIdValue")) ?? ""
        self.spoofProfileDcEnabled = ((try container.decodeIfPresent(Int32.self, forKey: "spoofProfileDcEnabled")) ?? 0) != 0
        self.spoofProfileDcValue = (try container.decodeIfPresent(String.self, forKey: "spoofProfileDcValue")) ?? ""
        self.spoofProfilePhoneEnabled = ((try container.decodeIfPresent(Int32.self, forKey: "spoofProfilePhoneEnabled")) ?? 0) != 0
        self.spoofProfilePhoneValue = (try container.decodeIfPresent(String.self, forKey: "spoofProfilePhoneValue")) ?? ""
        self.customBannerEnabled = ((try container.decodeIfPresent(Int32.self, forKey: "customBannerEnabled")) ?? 0) != 0
        self.customProfileBackgroundEnabled = ((try container.decodeIfPresent(Int32.self, forKey: "customProfileBackgroundEnabled")) ?? 0) != 0
        self.customProfileBackgroundForOthers = ((try container.decodeIfPresent(Int32.self, forKey: "customProfileBackgroundForOthers")) ?? 0) != 0
        self.customProfileBackgroundForSettings = ((try container.decodeIfPresent(Int32.self, forKey: "customProfileBackgroundForSettings")) ?? 0) != 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        try container.encode((self.keepDeletedMessages ? 1 : 0) as Int32, forKey: "keepDeletedMessages")
        try container.encode((self.saveEditHistory ? 1 : 0) as Int32, forKey: "saveEditHistory")
        try container.encode((self.keepSelfDestructMedia ? 1 : 0) as Int32, forKey: "keepSelfDestructMedia")
        try container.encode((self.ghostMode ? 1 : 0) as Int32, forKey: "ghostMode")
        try container.encode((self.hideOnlineStatus ? 1 : 0) as Int32, forKey: "hideOnlineStatus")
        try container.encode((self.hideTyping ? 1 : 0) as Int32, forKey: "hideTyping")
        try container.encode((self.hideReadReceipts ? 1 : 0) as Int32, forKey: "hideReadReceipts")
        try container.encode((self.hideStoryViews ? 1 : 0) as Int32, forKey: "hideStoryViews")
        try container.encode((self.askBeforeStoryView ? 1 : 0) as Int32, forKey: "askBeforeStoryView")
        try container.encode((self.sendViaScheduled ? 1 : 0) as Int32, forKey: "sendViaScheduled")
        try container.encode((self.sendWithoutOnline ? 1 : 0) as Int32, forKey: "sendWithoutOnline")
        try container.encode((self.showMessageSeconds ? 1 : 0) as Int32, forKey: "showMessageSeconds")
        try container.encode((self.editedIndicatorAsPencil ? 1 : 0) as Int32, forKey: "editedIndicatorAsPencil")
        try container.encode(self.editedIndicatorText, forKey: "editedIndicatorText")
        try container.encode(self.deletedIndicatorText, forKey: "deletedIndicatorText")
        try container.encode((self.regularEmojiFirst ? 1 : 0) as Int32, forKey: "regularEmojiFirst")
        try container.encode((self.doubleTapToEdit ? 1 : 0) as Int32, forKey: "doubleTapToEdit")
        try container.encode((self.showExactLastSeen ? 1 : 0) as Int32, forKey: "showExactLastSeen")
        try container.encode((self.showExactLastSeenSeconds ? 1 : 0) as Int32, forKey: "showExactLastSeenSeconds")
        try container.encode((self.wideChannelPosts ? 1 : 0) as Int32, forKey: "wideChannelPosts")
        try container.encode((self.showExactViewCounts ? 1 : 0) as Int32, forKey: "showExactViewCounts")
        try container.encode((self.showForwardCount ? 1 : 0) as Int32, forKey: "showForwardCount")
        try container.encode((self.hideAllChatsFolder ? 1 : 0) as Int32, forKey: "hideAllChatsFolder")
        try container.encode((self.foldersAtBottom ? 1 : 0) as Int32, forKey: "foldersAtBottom")
        try container.encode((self.hideBottomSearch ? 1 : 0) as Int32, forKey: "hideBottomSearch")
        try container.encode((self.compactBottomBar ? 1 : 0) as Int32, forKey: "compactBottomBar")
        try container.encode((self.allowSaveRestrictedContent ? 1 : 0) as Int32, forKey: "allowSaveRestrictedContent")
        try container.encode((self.roundVideoUseBackCamera ? 1 : 0) as Int32, forKey: "roundVideoUseBackCamera")
        try container.encode((self.showCameraTile ? 1 : 0) as Int32, forKey: "showCameraTile")
        try container.encode((self.cameraTileLivePreview ? 1 : 0) as Int32, forKey: "cameraTileLivePreview")
        try container.encode((self.confirmCalls ? 1 : 0) as Int32, forKey: "confirmCalls")
        try container.encode((self.saveDestructingMedia ? 1 : 0) as Int32, forKey: "saveDestructingMedia")
        try container.encode((self.saveAllIncomingMedia ? 1 : 0) as Int32, forKey: "saveAllIncomingMedia")
        try container.encode(self.mediaAutoCleanInterval, forKey: "mediaAutoCleanInterval")
        try container.encode(self.attachmentSizeLimit, forKey: "attachmentSizeLimit")
        try container.encode((self.mediaAutoCleanKeepPinned ? 1 : 0) as Int32, forKey: "mediaAutoCleanKeepPinned")
        try container.encode((self.mediaAutoCleanKeepChannels ? 1 : 0) as Int32, forKey: "mediaAutoCleanKeepChannels")
        try container.encode((self.mediaAutoCleanKeepBots ? 1 : 0) as Int32, forKey: "mediaAutoCleanKeepBots")
        try container.encode((self.showProfileId ? 1 : 0) as Int32, forKey: "showProfileId")
        try container.encode((self.showProfileDC ? 1 : 0) as Int32, forKey: "showProfileDC")
        try container.encode((self.showRegistrationDate ? 1 : 0) as Int32, forKey: "showRegistrationDate")
        try container.encode((self.hideOwnPhoneNumber ? 1 : 0) as Int32, forKey: "hideOwnPhoneNumber")
        try container.encode((self.spoofProfileIdEnabled ? 1 : 0) as Int32, forKey: "spoofProfileIdEnabled")
        try container.encode(self.spoofProfileIdValue, forKey: "spoofProfileIdValue")
        try container.encode((self.spoofProfileDcEnabled ? 1 : 0) as Int32, forKey: "spoofProfileDcEnabled")
        try container.encode(self.spoofProfileDcValue, forKey: "spoofProfileDcValue")
        try container.encode((self.spoofProfilePhoneEnabled ? 1 : 0) as Int32, forKey: "spoofProfilePhoneEnabled")
        try container.encode(self.spoofProfilePhoneValue, forKey: "spoofProfilePhoneValue")
        try container.encode((self.customBannerEnabled ? 1 : 0) as Int32, forKey: "customBannerEnabled")
        try container.encode((self.customProfileBackgroundEnabled ? 1 : 0) as Int32, forKey: "customProfileBackgroundEnabled")
        try container.encode((self.customProfileBackgroundForOthers ? 1 : 0) as Int32, forKey: "customProfileBackgroundForOthers")
        try container.encode((self.customProfileBackgroundForSettings ? 1 : 0) as Int32, forKey: "customProfileBackgroundForSettings")
    }
}

extension AyuGramSettings {
    // Display-only override for the profile numeric ID. Returns the spoofed
    // string when enabled and non-empty, otherwise the real id as a string.
    // NEVER used for anything but rendering.
    public func effectiveProfileIdForDisplay(realId: Int64) -> String {
        if self.spoofProfileIdEnabled {
            let trimmed = self.spoofProfileIdValue.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return "\(realId)"
    }

    // Display-only override for the profile data-center number.
    public func effectiveProfileDcForDisplay(realDc: Int) -> String {
        if self.spoofProfileDcEnabled {
            let trimmed = self.spoofProfileDcValue.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return "\(realDc)"
    }

    // Returns spoofed raw phone digits (no plus) when enabled and non-empty, so
    // the caller can run them through the normal phone formatter. Returns nil to
    // mean "use the real number". Display-only.
    public func spoofedPhoneDigitsForDisplay() -> String? {
        if self.spoofProfilePhoneEnabled {
            let trimmed = self.spoofProfilePhoneValue.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }
}

// MARK: - Global synchronous snapshot
//
// Some AyuGram features live deep in the UI render path (message-timestamp
// formatting, copy-protection gating, profile rendering) where there is no
// Postbox transaction and no reactive Signal to subscribe to. For those we keep
// a process-wide snapshot of the current settings, refreshed on every write and
// via a per-account subscription (see `keepAyuGramSettingsUpdated`). Reads are
// lock-guarded and cheap; writes are rare.
private let ayuGramSettingsStateLock = NSLock()
// nil until the first read/write of this process. The first read restores the
// last persisted settings from the UserDefaults mirror (see below) instead of
// falling back to defaults — the postbox-backed snapshot only arrives
// asynchronously and every UI-render-path consumer would otherwise render the
// default state on cold start.
private var ayuGramSettingsStateValue: AyuGramSettings?

public var ayuGramSettingsCurrent: AyuGramSettings {
    ayuGramSettingsStateLock.lock()
    defer { ayuGramSettingsStateLock.unlock() }
    if let value = ayuGramSettingsStateValue {
        return value
    }
    let restored = readAyuSettingsMirror() ?? AyuGramSettings.defaultSettings
    ayuGramSettingsStateValue = restored
    return restored
}

private func setAyuGramSettingsCurrent(_ settings: AyuGramSettings) {
    ayuGramSettingsStateLock.lock()
    let previous = ayuGramSettingsStateValue
    ayuGramSettingsStateValue = settings
    let alreadyMirrored = ayuHasMirroredBottomBarDefaults
    let alreadyMirroredSettings = ayuHasMirroredSettings
    ayuGramSettingsStateLock.unlock()
    // Full-settings mirror: same idea as the bottom-bar keys below, but for the
    // whole value, so the very first synchronous read in the next cold start
    // sees the user's real settings rather than the defaults.
    if previous != settings || !alreadyMirroredSettings {
        writeAyuSettingsMirror(settings)
    }
    // Mirror the bottom-bar toggles into UserDefaults so the low-level tab-bar
    // modules (TabBarUI / TabBarComponent) can read them without taking a
    // dependency on TelegramCore. Keys are shared with those modules; see
    // AyuBottomBarDefaultsKeys below. This function is called very frequently
    // (on every settings read inside a transaction), so normally only write when
    // one of the mirrored values actually changed — BUT the very first mirror
    // must always be written, even when the settings equal the defaults. Without
    // this the low-level tab bar could read an absent key (== false) at cold
    // start and render the wrong bottom-bar state until the next change, which is
    // exactly the compact/folders desync seen after a restart. See also
    // ayuSyncBottomBarDefaults(), called early from the root controller.
    let changed = previous?.foldersAtBottom != settings.foldersAtBottom
        || previous?.hideBottomSearch != settings.hideBottomSearch
        || previous?.compactBottomBar != settings.compactBottomBar
    if changed || !alreadyMirrored {
        writeAyuBottomBarDefaults(settings)
    }
}

// Whether the bottom-bar UserDefaults mirror has been written at least once this
// process. Guards the "always write the first mirror" rule in
// setAyuGramSettingsCurrent. Access is guarded by ayuGramSettingsStateLock.
private var ayuHasMirroredBottomBarDefaults = false

// Same flag for the full-settings mirror below.
private var ayuHasMirroredSettings = false

// UserDefaults key holding the JSON-encoded last known settings value.
private let ayuSettingsMirrorKey = "shadow.settingsMirror"

private func writeAyuSettingsMirror(_ settings: AyuGramSettings) {
    if let data = try? JSONEncoder().encode(settings) {
        UserDefaults.standard.set(data, forKey: ayuSettingsMirrorKey)
    }
    ayuGramSettingsStateLock.lock()
    ayuHasMirroredSettings = true
    ayuGramSettingsStateLock.unlock()
}

// Reads the mirror. Called with ayuGramSettingsStateLock HELD — it must not take
// the lock itself.
private func readAyuSettingsMirror() -> AyuGramSettings? {
    guard let data = UserDefaults.standard.data(forKey: ayuSettingsMirrorKey) else {
        return nil
    }
    return try? JSONDecoder().decode(AyuGramSettings.self, from: data)
}

private func writeAyuBottomBarDefaults(_ settings: AyuGramSettings) {
    let defaults = UserDefaults.standard
    defaults.set(settings.foldersAtBottom, forKey: AyuBottomBarDefaultsKeys.foldersAtBottom)
    defaults.set(settings.hideBottomSearch, forKey: AyuBottomBarDefaultsKeys.hideBottomSearch)
    defaults.set(settings.compactBottomBar, forKey: AyuBottomBarDefaultsKeys.compactBottomBar)
    ayuGramSettingsStateLock.lock()
    ayuHasMirroredBottomBarDefaults = true
    ayuGramSettingsStateLock.unlock()
}

// Shadow: synchronously flush the current bottom-bar toggles into their
// UserDefaults mirror from the process-wide snapshot. Call this once, early
// (before the tab bar is created), so the low-level tab-bar modules never read a
// stale/absent mirror on cold start. Safe to call repeatedly; it just rewrites
// the same three keys.
public func ayuSyncBottomBarDefaults() {
    writeAyuBottomBarDefaults(ayuGramSettingsCurrent)
}

// Shared UserDefaults keys for the three "bottom interface" toggles. Duplicated
// (as string literals) in the low-level tab-bar modules that cannot import
// TelegramCore. Keep the raw string values in sync across all readers.
public enum AyuBottomBarDefaultsKeys {
    public static let foldersAtBottom = "shadow.foldersAtBottom"
    public static let hideBottomSearch = "shadow.hideBottomSearch"
    public static let compactBottomBar = "shadow.compactBottomBar"
}

// Synchronous read inside a Postbox transaction — used by the low-level
// interception points (presence, typing, delete handling). Also refreshes the
// global snapshot as a side effect.
public func currentAyuGramSettings(transaction: Transaction) -> AyuGramSettings {
    let settings: AyuGramSettings
    if let entry = transaction.getPreferencesEntry(key: PreferencesKeys.ayuGramSettings)?.get(AyuGramSettings.self) {
        settings = entry
    } else {
        settings = AyuGramSettings.defaultSettings
    }
    setAyuGramSettingsCurrent(settings)
    return settings
}

public func updateAyuGramSettings(transaction: Transaction, _ f: (AyuGramSettings) -> AyuGramSettings) {
    let current = currentAyuGramSettings(transaction: transaction)
    let updated = f(current)
    if updated != current {
        transaction.setPreferencesEntry(key: PreferencesKeys.ayuGramSettings, value: PreferencesEntry(updated))
        setAyuGramSettingsCurrent(updated)
    }
}

public func updateAyuGramSettings(postbox: Postbox, _ f: @escaping (AyuGramSettings) -> AyuGramSettings) -> Signal<Never, NoError> {
    return postbox.transaction { transaction -> Void in
        updateAyuGramSettings(transaction: transaction, f)
    }
    |> ignoreValues
}

// Reactive stream — used by the UI (settings screen) and the presence wiring.
public func ayuGramSettings(postbox: Postbox) -> Signal<AyuGramSettings, NoError> {
    return postbox.preferencesView(keys: [PreferencesKeys.ayuGramSettings])
    |> map { view -> AyuGramSettings in
        return view.values[PreferencesKeys.ayuGramSettings]?.get(AyuGramSettings.self) ?? AyuGramSettings.defaultSettings
    }
}

// Started once per account (from Account managed operations) so the global
// snapshot always reflects the persisted settings, even before any low-level
// interception point has run.
public func keepAyuGramSettingsUpdated(postbox: Postbox) -> Signal<Never, NoError> {
    return ayuGramSettings(postbox: postbox)
    |> map { settings -> AyuGramSettings in
        setAyuGramSettingsCurrent(settings)
        return settings
    }
    |> ignoreValues
}

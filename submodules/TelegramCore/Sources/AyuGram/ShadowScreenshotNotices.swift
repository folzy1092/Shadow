import Foundation

// Shadow: screenshots of secret chats and view-once media are never reported
// to the other side. Kept as one switch so every report site (secret chat
// screen, gallery, self-destruct viewer) stays consistent.
public let shadowSuppressScreenshotNotices: Bool = true

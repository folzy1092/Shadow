import Foundation
import SwiftSignalKit

// AyuGram: remote badge configuration ("git config").
//
// A small JSON document hosted on GitHub drives two kinds of client-only
// decorations:
//   * `badges`         — custom-emoji badges for chats, matched by chat_id.
//   * `profile_badges` — custom-emoji badges for profiles, matched by user_id.
//
// Nothing here touches backend/account data — the emoji is only rendered
// client-side. The document is fetched over HTTPS, cached on disk, and read
// through a lock-guarded process-wide snapshot so the profile render path can
// look badges up synchronously.

public struct GitConfigBadge: Equatable {
    public let id: String
    public let chatId: Int64
    public let emojiId: Int64
    public let textTemplate: String?

    public init(id: String, chatId: Int64, emojiId: Int64, textTemplate: String?) {
        self.id = id
        self.chatId = chatId
        self.emojiId = emojiId
        self.textTemplate = textTemplate
    }
}

public struct GitConfigProfileBadge: Equatable {
    public let id: String
    public let userId: Int64
    public let emojiId: Int64
    public let textTemplate: String?

    public init(id: String, userId: Int64, emojiId: Int64, textTemplate: String?) {
        self.id = id
        self.userId = userId
        self.emojiId = emojiId
        self.textTemplate = textTemplate
    }
}

public struct GitConfig: Equatable {
    public let badges: [GitConfigBadge]
    public let profileBadges: [GitConfigProfileBadge]

    public static let empty = GitConfig(badges: [], profileBadges: [])

    public init(badges: [GitConfigBadge], profileBadges: [GitConfigProfileBadge]) {
        self.badges = badges
        self.profileBadges = profileBadges
    }
}

// MARK: - Process-wide snapshot

private let gitConfigLock = NSLock()
private var gitConfigValue: GitConfig = .empty
private let gitConfigPromise = ValuePromise<GitConfig>(.empty, ignoreRepeated: false)

public var gitConfigCurrent: GitConfig {
    gitConfigLock.lock()
    defer { gitConfigLock.unlock() }
    return gitConfigValue
}

// Reactive stream — used by the profile screen to rebuild once the config
// arrives from the network (the initial value is the current snapshot).
public func gitConfigUpdates() -> Signal<GitConfig, NoError> {
    return gitConfigPromise.get()
}

private func setGitConfig(_ config: GitConfig) {
    gitConfigLock.lock()
    gitConfigValue = config
    gitConfigLock.unlock()
    gitConfigPromise.set(config)
}

// Look up a profile badge by user id (used by the profile render path). Only the
// user ids present in `profile_badges` match — everyone else gets nil.
public func gitConfigProfileBadge(forUserId userId: Int64) -> GitConfigProfileBadge? {
    return gitConfigCurrent.profileBadges.first(where: { $0.userId == userId })
}

// Shadow: all profile badges for a user (the remote config may list more than
// one for the same user_id). `gitConfigProfileBadge` returns only the first;
// this returns every match so the UI can render each one.
public func gitConfigProfileBadges(forUserId userId: Int64) -> [GitConfigProfileBadge] {
    return gitConfigCurrent.profileBadges.filter({ $0.userId == userId })
}

// Look up a chat badge by chat id.
public func gitConfigChatBadge(forChatId chatId: Int64) -> GitConfigBadge? {
    return gitConfigCurrent.badges.first(where: { $0.chatId == chatId })
}

// MARK: - Parsing

// Decoded with JSONDecoder so the large emoji_id values keep full Int64 precision
// (JSONSerialization can coerce big integers to Double and lose bits).
private struct GitConfigDTO: Codable {
    struct Badge: Codable {
        let id: String?
        let chat_id: Int64?
        let emoji_id: Int64?
        let text_template: String?
    }
    struct ProfileBadge: Codable {
        let id: String?
        let user_id: Int64?
        let emoji_id: Int64?
        let text_template: String?
    }
    let badges: [Badge]?
    let profile_badges: [ProfileBadge]?
}

private func parseGitConfig(_ data: Data) -> GitConfig? {
    guard let dto = try? JSONDecoder().decode(GitConfigDTO.self, from: data) else {
        return nil
    }
    let badges: [GitConfigBadge] = (dto.badges ?? []).compactMap { badge in
        guard let chatId = badge.chat_id, let emojiId = badge.emoji_id else {
            return nil
        }
        return GitConfigBadge(id: badge.id ?? "", chatId: chatId, emojiId: emojiId, textTemplate: badge.text_template)
    }
    let profileBadges: [GitConfigProfileBadge] = (dto.profile_badges ?? []).compactMap { badge in
        guard let userId = badge.user_id, let emojiId = badge.emoji_id else {
            return nil
        }
        return GitConfigProfileBadge(id: badge.id ?? "", userId: userId, emojiId: emojiId, textTemplate: badge.text_template)
    }
    return GitConfig(badges: badges, profileBadges: profileBadges)
}

// MARK: - Fetch + cache lifecycle

private let gitConfigURLString = "https://raw.githubusercontent.com/folzy1092/tgfork/main/config.json"

private func gitConfigCacheURL() -> URL? {
    guard let directory = try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
        return nil
    }
    return directory.appendingPathComponent("GitConfig.json")
}

// Downloads the config from GitHub, updates the snapshot + disk cache, and
// reports success on the main queue. Failures (offline, malformed JSON) are
// swallowed so the UI is never affected — badges just don't change.
private func fetchGitConfig(completion: ((Bool) -> Void)? = nil) {
    guard let remoteURL = URL(string: gitConfigURLString) else {
        completion?(false)
        return
    }
    var request = URLRequest(url: remoteURL)
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.timeoutInterval = 20.0
    let task = URLSession.shared.dataTask(with: request) { data, _, error in
        guard error == nil, let data = data, let config = parseGitConfig(data) else {
            if let completion = completion {
                Queue.mainQueue().async { completion(false) }
            }
            return
        }
        setGitConfig(config)
        if let cacheURL = gitConfigCacheURL() {
            try? data.write(to: cacheURL, options: .atomic)
        }
        if let completion = completion {
            Queue.mainQueue().async { completion(true) }
        }
    }
    task.resume()
}

private let gitConfigStartLock = NSLock()
private var gitConfigStarted = false

// Called once per process (from Account setup). Loads the on-disk cache first so
// badges are available immediately, then refreshes from GitHub in the background.
public func startGitConfigIfNeeded() {
    gitConfigStartLock.lock()
    if gitConfigStarted {
        gitConfigStartLock.unlock()
        return
    }
    gitConfigStarted = true
    gitConfigStartLock.unlock()

    // 1. Seed from cache synchronously.
    if let cacheURL = gitConfigCacheURL(), let data = try? Data(contentsOf: cacheURL), let config = parseGitConfig(data) {
        setGitConfig(config)
    }

    // 2. Refresh from GitHub.
    fetchGitConfig()
}

// Forces a fresh download (used by the "Sync with GitHub" settings button).
// `completion` is called on the main queue with whether the sync succeeded.
public func refreshGitConfig(completion: ((Bool) -> Void)? = nil) {
    fetchGitConfig(completion: completion)
}

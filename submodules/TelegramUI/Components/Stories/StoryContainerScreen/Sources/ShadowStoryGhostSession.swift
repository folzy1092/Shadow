import Foundation
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext

// Shadow: «Включить призрака» in the offer before someone's stories turns Ghost
// Mode on only while the stories are open. The values it changed are written
// to UserDefaults first, so they come back:
// - when the story screen closes (StoryContainerScreen.dismiss / deinit);
// - when the stories never opened (loading cancelled or nothing to show);
// - on the next launch, if the app was killed while the stories were open
//   (swiped away from the app switcher, or killed by iOS in the background).
// Backgrounding alone changes nothing: the stories are still open.
//
// Only the fields this session turned on are restored, and only if they still
// hold the session's value — a change made by hand meanwhile is kept.
public final class ShadowStoryGhostSession {
    static let defaultsKey = "shadow.storyGhostSession.v1"

    private struct Snapshot: Codable {
        var accountPeerId: Int64
        var ghostMode: Bool
        var hideStoryViews: Bool
        var ghostAccountMode: Int32
    }

    private let context: AccountContext
    private var snapshot: Snapshot?
    private var isEnded = false

    private init(context: AccountContext) {
        self.context = context
    }

    /// Turns Ghost Mode on for this viewing. `completion` runs on the main queue
    /// once the settings are written.
    static func begin(context: AccountContext, completion: @escaping (ShadowStoryGhostSession) -> Void) {
        let accountPeerId = context.account.peerId.toInt64()
        let session = ShadowStoryGhostSession(context: context)
        let _ = (context.account.postbox.transaction { transaction -> Snapshot in
            // Stored values, not the disguise mask.
            var snapshot: Snapshot?
            updateAyuGramSettings(transaction: transaction, { settings in
                snapshot = Snapshot(
                    accountPeerId: accountPeerId,
                    ghostMode: settings.ghostMode,
                    hideStoryViews: settings.hideStoryViews,
                    ghostAccountMode: settings.ghostAccountMode.rawValue
                )
                // Saved before the change is committed: a kill right after it
                // still finds the snapshot.
                ShadowStoryGhostSession.save(snapshot!)
                var settings = settings
                settings.ghostMode = true
                settings.hideStoryViews = true
                settings.ghostAccountMode = .manual
                return settings
            })
            return snapshot!
        }
        |> deliverOnMainQueue).start(next: { snapshot in
            session.snapshot = snapshot
            completion(session)
        })
    }

    /// Restores the previous values. Safe to call more than once.
    func end() {
        if self.isEnded {
            return
        }
        self.isEnded = true
        guard let snapshot = self.snapshot else {
            return
        }
        let _ = (ShadowStoryGhostSession.restore(postbox: self.context.account.postbox, snapshot: snapshot)
        |> deliverOnMainQueue).start(completed: {
            ShadowStoryGhostSession.clearIfMatches(snapshot)
        })
    }

    deinit {
        // Last resort: a session dropped without end() (screen never retained it).
        if !self.isEnded, let snapshot = self.snapshot {
            let _ = (ShadowStoryGhostSession.restore(postbox: self.context.account.postbox, snapshot: snapshot)
            |> deliverOnMainQueue).start(completed: {
                ShadowStoryGhostSession.clearIfMatches(snapshot)
            })
        }
    }

    private static func restore(postbox: Postbox, snapshot: Snapshot) -> Signal<Never, NoError> {
        return updateAyuGramSettings(postbox: postbox, { settings in
            var settings = settings
            if settings.ghostMode && !snapshot.ghostMode {
                settings.ghostMode = false
            }
            if settings.hideStoryViews && !snapshot.hideStoryViews {
                settings.hideStoryViews = false
            }
            if settings.ghostAccountMode == .manual, let mode = ShadowGhostAccountMode(rawValue: snapshot.ghostAccountMode) {
                settings.ghostAccountMode = mode
            }
            return settings
        })
    }

    /// Called once at launch: undoes a session that was cut short by the app
    /// being killed while the stories were open.
    public static func recoverAfterLaunch(sharedContext: SharedAccountContext) {
        guard let snapshot = ShadowStoryGhostSession.load() else {
            return
        }
        let _ = (sharedContext.activeAccountContexts
        |> map { _, accounts, _ -> [AccountContext] in
            return accounts.map { $0.1 }
        }
        |> filter { !$0.isEmpty }
        |> take(1)
        |> timeout(30.0, queue: .mainQueue(), alternate: .single([]))
        |> mapToSignal { accounts -> Signal<Never, NoError> in
            guard let context = accounts.first(where: { $0.account.peerId.toInt64() == snapshot.accountPeerId }) else {
                // The account is gone (logged out) — nothing to restore.
                return .complete()
            }
            return ShadowStoryGhostSession.restore(postbox: context.account.postbox, snapshot: snapshot)
        }
        |> deliverOnMainQueue).start(completed: {
            ShadowStoryGhostSession.clearIfMatches(snapshot)
        })
    }

    private static func save(_ snapshot: Snapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: ShadowStoryGhostSession.defaultsKey)
        }
    }

    private static func load() -> Snapshot? {
        guard let data = UserDefaults.standard.data(forKey: ShadowStoryGhostSession.defaultsKey) else {
            return nil
        }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    // A newer session may already have written its own snapshot; keep it.
    private static func clearIfMatches(_ snapshot: Snapshot) {
        guard let stored = ShadowStoryGhostSession.load() else {
            return
        }
        if stored.accountPeerId == snapshot.accountPeerId && stored.ghostMode == snapshot.ghostMode && stored.hideStoryViews == snapshot.hideStoryViews && stored.ghostAccountMode == snapshot.ghostAccountMode {
            UserDefaults.standard.removeObject(forKey: ShadowStoryGhostSession.defaultsKey)
        }
    }
}

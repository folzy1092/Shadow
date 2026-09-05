"""Source contracts for the own-profile Ghost Mode last-seen timestamp."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
SETTINGS = (ROOT / "submodules/TelegramCore/Sources/AyuGram/AyuGramSettings.swift").read_text()
PRESENCE = (ROOT / "submodules/TelegramCore/Sources/State/ManagedAccountPresence.swift").read_text()
ACCOUNT = (ROOT / "submodules/TelegramCore/Sources/Account/Account.swift").read_text()
STRINGS = (ROOT / "submodules/TelegramStringFormatting/Sources/PresenceStrings.swift").read_text()
HEADER = (ROOT / "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoHeaderNode.swift").read_text()


class GhostLastSeenContracts(unittest.TestCase):
    def test_timestamp_is_account_scoped_and_persisted(self):
        self.assertIn("public var ghostLastSeenTimestamp: Int32", SETTINGS)
        self.assertIn('decodeIfPresent(Int32.self, forKey: "ghostLastSeenTimestamp")', SETTINGS)
        self.assertIn('encode(self.ghostLastSeenTimestamp, forKey: "ghostLastSeenTimestamp")', SETTINGS)
        self.assertNotIn('"ghostLastSeenTimestamp":', (ROOT / "submodules/TelegramCore/Sources/AyuGram/ShadowSettingsTransfer.swift").read_text())

    def test_profile_reads_the_owning_account_from_telegram(self):
        self.assertIn("shadowOwnServerPresence(account: self.context.account)", HEADER)
        self.assertIn("account.network.request(Api.functions.users.getUsers(id: [.inputUserSelf]))", PRESENCE)
        self.assertIn("case let .userStatusOffline(data): return .offline(wasOnline: data.wasOnline)", PRESENCE)

    def test_status_commands_never_generate_last_seen(self):
        self.assertNotIn("pendingOfflineTransitionTimestamp", PRESENCE)
        self.assertNotIn("ghostLastSeenTimestamp =", PRESENCE)
        self.assertNotIn("Date().timeIntervalSince1970", PRESENCE)

    def test_reasserts_do_not_advance_the_timestamp(self):
        reassert = PRESENCE.split("self.offlineReassertDisposable", 1)[1].split("deinit", 1)[0]
        self.assertIn("self.updatePresence(false)", reassert)
        self.assertNotIn("ghostLastSeenTimestamp", reassert)

    def test_fetch_failure_is_unknown_and_read_does_not_publish_online(self):
        query = PRESENCE.split("public func shadowOwnServerPresence", 1)[1].split("private final class", 1)[0]
        self.assertIn("return .single(.unavailable)", query)
        self.assertIn("timeout(10.0", query)
        self.assertNotIn("account.updateStatus", query)

    def test_own_profile_replaces_online_only_while_presence_is_hidden(self):
        own_profile = HEADER.split("} else if self.isMyProfile {", 1)[1].split("} else if let _ = threadData", 1)[0]
        self.assertIn("self.ayuSettings.effectiveHideOnline", own_profile)
        self.assertIn("ayuExactLastSeenString", own_profile)
        self.assertIn("presentationData.strings.LastSeen_Lately", own_profile)
        self.assertIn("presentationData.strings.Presence_online", own_profile)
        self.assertIn("self.ownServerPresence.exactLastSeenTimestamp", own_profile)
        self.assertIn("Статус Telegram недоступен", own_profile)
        self.assertNotIn("ghostLastSeenTimestamp", own_profile)

    def test_polling_stops_offscreen_and_in_background(self):
        self.assertIn("self.ownPresenceApplicationActive && self.ownHeaderVisible", HEADER)
        self.assertIn("override func didExitHierarchy()", HEADER)
        self.assertIn("self.ownServerPresenceDisposable.set(nil)", HEADER)
        self.assertIn("self.ownServerPresenceTimer?.invalidate()", HEADER)
        self.assertIn("self.ownServerPresence = .unavailable", HEADER)

    def test_exact_formatter_never_uses_just_now(self):
        formatter = STRINGS.split("public func ayuExactLastSeenString", 1)[1].split("// AyuGram (Этап 4b)", 1)[0]
        self.assertIn("stringForUserPresence", formatter)
        self.assertIn("includeSeconds", formatter)
        self.assertNotIn("LastSeen_JustNow", formatter)


if __name__ == "__main__":
    unittest.main()

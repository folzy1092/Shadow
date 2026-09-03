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

    def test_presence_manager_receives_the_owning_postbox(self):
        self.assertIn("network: network, postbox: postbox", ACCOUNT)
        self.assertIn("private let postbox: Postbox", PRESENCE)
        self.assertIn("updateAyuGramSettings(postbox: self.postbox)", PRESENCE)

    def test_only_a_real_online_to_offline_transition_starts_capture(self):
        transition = PRESENCE.split("let previousValue = self.wasOnline", 1)[1].split("self.updatePresence(value)", 1)[0]
        self.assertIn("previousValue == true", transition)
        self.assertIn("pendingOfflineTransitionTimestamp", transition)
        self.assertNotIn("previousValue == nil", transition)

    def test_reasserts_do_not_advance_the_timestamp(self):
        reassert = PRESENCE.split("self.offlineReassertDisposable", 1)[1].split("deinit", 1)[0]
        self.assertIn("self.updatePresence(false)", reassert)
        self.assertNotIn("pendingOfflineTransitionTimestamp =", reassert)
        self.assertEqual(PRESENCE.count("pendingOfflineTransitionTimestamp = Int32(Date().timeIntervalSince1970)"), 1)

    def test_only_a_confirmed_offline_rpc_is_saved(self):
        response = PRESENCE.split("start(next:", 1)[1].split("completed:", 1)[0]
        self.assertIn("!isOnline", response)
        self.assertIn("case .boolTrue = result", response)
        self.assertIn("timestamp > settings.ghostLastSeenTimestamp", response)

    def test_own_profile_replaces_online_only_while_presence_is_hidden(self):
        own_profile = HEADER.split("} else if self.isMyProfile {", 1)[1].split("} else if let _ = threadData", 1)[0]
        self.assertIn("self.ayuSettings.effectiveHideOnline", own_profile)
        self.assertIn("ayuExactLastSeenString", own_profile)
        self.assertIn("presentationData.strings.LastSeen_Lately", own_profile)
        self.assertIn("presentationData.strings.Presence_online", own_profile)

    def test_exact_formatter_never_uses_just_now(self):
        formatter = STRINGS.split("public func ayuExactLastSeenString", 1)[1].split("// AyuGram (Этап 4b)", 1)[0]
        self.assertIn("stringForUserPresence", formatter)
        self.assertIn("includeSeconds", formatter)
        self.assertNotIn("LastSeen_JustNow", formatter)


if __name__ == "__main__":
    unittest.main()

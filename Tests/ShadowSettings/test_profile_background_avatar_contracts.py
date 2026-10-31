"""Source contracts for «Фон из аватарки» (2.2.0): each profile's background is that peer's own avatar."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SUB = ROOT / "submodules"


def read(path: str) -> str:
    return (SUB / path).read_text(encoding="utf-8")


class ProfileBackgroundAvatarContracts(unittest.TestCase):
    def setUp(self) -> None:
        self.header = read("TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoHeaderNode.swift")

    def test_setting_is_stored_transferred_and_linked(self) -> None:
        self.assertIn("customProfileBackgroundFromAvatar", read("TelegramCore/Sources/AyuGram/AyuGramSettings.swift"))
        self.assertIn("customProfileBackgroundFromAvatar", read("TelegramCore/Sources/AyuGram/ShadowSettingsTransfer.swift"))
        self.assertIn("customProfileBackgroundFromAvatar", read("TelegramCore/Sources/AyuGram/ShadowSettingLinksApply.swift"))
        links = read("TelegramCore/Sources/AyuGram/ShadowSettingLinks.swift")
        self.assertIn('"profile-background-avatar"', links)
        controller = read("SettingsUI/Sources/AyuGramSettingsController.swift")
        self.assertIn('"Фон из аватарки"', controller)

    def test_avatar_mode_draws_the_shown_peers_own_avatar(self) -> None:
        update = self.header[self.header.index("private func updateProfileBackground("):]
        self.assertIn("self.ayuSettings.customProfileBackgroundFromAvatar, let peer = self.peer", update)
        self.assertIn("peer.profileImageRepresentations.last", update)
        avatar = self.header[self.header.index("private func updateProfileBackgroundFromAvatar("):]
        self.assertIn("peerAvatarImage(account: self.context.account", avatar)
        # The signature carries the peer and the photo, so another profile or a new avatar reloads.
        self.assertIn('"avatar_\\(peer.id.toInt64())_\\(representation.resource.id.stringRepresentation)"', avatar)
        # A late result for a previous peer must not land on this one.
        self.assertIn("self.profileBackgroundLoadedSignature == signature", avatar)

    def test_one_condition_decides_where_the_background_applies(self) -> None:
        self.assertIn("var customProfileBackgroundApplies: Bool", self.header)
        self.assertIn("let customBackgroundActive = self.customProfileBackgroundApplies", self.header)
        self.assertIn("self.profileBackgroundAvatarDisposable.dispose()", self.header)


if __name__ == "__main__":
    unittest.main()

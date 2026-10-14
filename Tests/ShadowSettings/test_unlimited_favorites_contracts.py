"""Source contracts: «Безлимитное избранное» — stickers and GIFs over the limit (1.13.0)."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SUB = ROOT / "submodules"


def read(path):
    return (SUB / path).read_text(encoding="utf-8")


class UnlimitedFavoritesContracts(unittest.TestCase):
    def test_settings(self):
        settings = read("TelegramCore/Sources/AyuGram/AyuGramSettings.swift")
        self.assertIn("public var unlimitedFavorites: Bool = true", settings)
        self.assertIn('forKey: "unlimitedFavorites")) ?? 1) != 0', settings)
        self.assertIn("settings.unlimitedFavorites = false", settings)
        self.assertIn('"unlimitedFavorites": \\.unlimitedFavorites', read("TelegramCore/Sources/AyuGram/ShadowSettingsTransfer.swift"))
        self.assertIn('slug: "unlimited-favorites", entryId: 131, key: "unlimitedFavorites"', read("TelegramCore/Sources/AyuGram/ShadowSettingLinks.swift"))
        self.assertIn("case .unlimitedFavorites: return 131", read("SettingsUI/Sources/AyuGramSettingsController.swift"))

    def test_nothing_is_cut(self):
        stickers = read("TelegramCore/Sources/TelegramEngine/Stickers/SavedStickers.swift")
        self.assertIn("limit: shadowUnlimited ? ShadowUnlimitedFavorites.localLimit :", stickers)
        gifs = read("TelegramCore/Sources/State/SynchronizeSavedGifsOperation.swift")
        self.assertIn("limit: shadowUnlimited ? ShadowUnlimitedFavorites.localLimit :", gifs)
        self.assertIn("max(limit, ShadowUnlimitedFavorites.localLimit)", gifs)
        self.assertIn("max(limit, ShadowUnlimitedFavorites.localLimit)", read("TelegramCore/Sources/State/SynchronizeSavedStickersOperation.swift"))
        sync = read("TelegramCore/Sources/State/ManagedRecentStickers.swift")
        self.assertEqual(sync.count("shadowKeepsLocalExtras: true"), 2)
        self.assertIn("if shadowKeepsLocalExtras && currentAyuGramSettings(transaction: transaction).unlimitedFavorites {", sync)


if __name__ == "__main__":
    unittest.main()

import Foundation

// Shadow: «Безлимитное избранное» (AyuGramSettings.unlimitedFavorites, on by
// default, next to «Безлимитные закрепы»). Telegram keeps 5 favourite stickers
// (10 with Premium) and 200 saved GIFs; adding one more drops the oldest. With
// the toggle on nothing is dropped: the server keeps its share, the rest stays
// in this device's list after it.
//
//   _internal_toggleStickerSaved / toggleGifSaved  no limit toast, no tail cut
//   addSavedSticker / addSavedGif                  limit raised to localLimit
//   managedSavedStickers / managedRecentGifs       a server sync keeps local
//                                                  extras after its own items
//
// Removing a favourite elsewhere does not remove a local extra here.
public enum ShadowUnlimitedFavorites {
    public static let localLimit = 1000
}

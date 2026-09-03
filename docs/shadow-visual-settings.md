# Shadow: account-owned visual settings

## Regression and fix

Every loaded account runs `keepAyuGramSettingsUpdated` and a 300-second media
cleanup check. Previously even a read of `currentAyuGramSettings(transaction:)`
replaced the process-wide snapshot, full settings mirror and bottom-bar defaults.
An inactive account's defaults could therefore hide the active profile's image
and change the bar. The image file itself was not removed by that cleanup.

Ghost Mode wrote the active account's complete settings back into that shared
snapshot. The root subscription only watched three bar flags, while both the
geometry cache and component equality omitted the externally-read visual flags.
Switching to Contacts/Settings caused the unrelated layout that made the bar
look correct again.

Ownership after the fix:

- Postbox is still the authoritative per-account store. Transaction reads have
  no UI/UserDefaults side effects; transaction writes only update preferences.
- Each account maintains its own synchronous cache and
  `shadow.settingsMirror.account.<AccountRecordId>` cold-start mirror. The old
  unscoped mirror is deliberately ignored: its owning account cannot be trusted.
- The root controller selects the UI account before constructing views and
  publishes only its own full settings stream on main. Old roots for other
  accounts cannot overwrite the active projection or reapply their bar defaults.
  Processes without a root UI retain the legacy synchronous fallback; it cannot
  write bar defaults or replace a snapshot once an account's root is selected.
- The tab-bar geometry cache, parent component and all three item components
  explicitly include label visibility; the geometry/parent component also include
  search visibility. Layout no longer requires a tab switch or tab reconstruction.
- Profile headers subscribe to their own account and foreground events, and ask
  their parent for layout. The background flags and image path use the same account.
- Media-save/edit-history hooks use the snapshot for their MediaBox, not the UI
  account. Unknown MediaBoxes use default settings rather than another account's.

No settings schema, profile/banner image paths, saved images or server-side
account settings are changed. On the first launch after upgrading, an account
without a scoped mirror uses defaults until its first Postbox emission; that
emission must update the visible layout immediately. Later launches can restore
that account's mirror synchronously.

## Verification

Fast source-contract checks (no Xcode needed):

```sh
python3 -m unittest discover -s Tests/ShadowVisualSettings -v
```

These are regression guards for the source wiring, not Swift compilation or
UIKit tests. Build the app with the repository's documented Bazel/Xcode workflow
and verify on a simulator/device before shipping:

1. Sign into accounts A and B. Give them different compact/search/folder settings;
   enable a profile background only for A. Keep A on Chats for at least 10 minutes
   (two media cleanup intervals), with no Ghost toggle or tab switch. Its bar and
   background must remain A's.
2. Switch A → B → A several times, including while background updates arrive.
   Each account must retain its own bar, background and media-save preferences.
3. Force-quit and relaunch on each account. Test an upgrade with only the old
   `shadow.settingsMirror` present as well as a subsequent cold launch with scoped
   mirrors. The first Postbox result must correct the bar without opening another tab.
4. Toggle compact bar, hidden bottom search and folders-at-bottom individually
   and in combination. Check both selected and unselected labels, search open/close,
   keyboard transitions and portrait/landscape layout. Compact rows are 40pt and
   regular rows 56pt, plus the existing padding; icons must not be scaled.
5. Background/foreground while Chats, Settings and My Profile are open. Check
   profile-for-settings/profile-for-others options as well as the active account's
   own profile. The selected tab must not change to repair the UI.
6. Toggle Ghost Mode with the bar already correct: privacy behavior may change,
   but it must not restore another account's appearance or move the bar.

Do not disable the profile-background toggle as a recovery step: the existing
settings action intentionally deletes that image. This fix neither invokes nor
changes that action, and does not address unrelated image-save failures.

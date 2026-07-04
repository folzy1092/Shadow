# AyuGram-style fork of Telegram-iOS

Fork goal: two AyuGram-like behaviors on top of the official Telegram-iOS
source — **anti-deletion** of messages/media and **hiding the "online" /
"typing…" status** — with a Settings toggle, structured so upstream updates
stay easy to merge.

All work lives on branch **`ayugram`**. This document is the map: what is done,
where every integration point is (verified against the current checkout), the
storage design for saved messages, the Settings screen wiring, and the
upstream-merge strategy.

> **Build status:** the code below is written against this checkout but **not
> yet compiled** — a full build needs your own Apple credentials (`api_id`/
> `api_hash`) and a codesigning setup replacing the project's private
> `fastlanematch` repo (see §1). Treat every patch as "ready to build & verify",
> not "verified".

---

## 0. What is implemented on the `ayugram` branch

| Piece | File | Status |
|---|---|---|
| Settings model + Postbox persistence | `submodules/TelegramCore/Sources/AyuGram/AyuGramSettings.swift` (new) | ✅ written |
| Hide "typing…" (outgoing) | `submodules/TelegramCore/Sources/State/ManagedLocalInputActivities.swift` | ✅ written |
| Hide "online" | `submodules/TelegramUI/Sources/SharedWakeupManager.swift` | ✅ written |
| Anti-delete core hook + graveyard store | `AccountStateManagementUtils.swift` + new `DeletedMessageStore.swift` | 📋 designed (§4) |
| Settings UI toggle screen | `submodules/SettingsUI/...` (new) | 📋 designed (§5) |
| "Deleted messages" in-chat UI | `submodules/TelegramUI/...` | 📋 designed (§4.4) |

The settings model uses one **self-contained new file** with a preferences key
raw value of `1000` (far above upstream's range, currently ~49) — so adding the
feature flags touches **zero** existing files and never conflicts on merge.

---

## 1. Build (task #1)

The repo builds via Bazel through a Python wrapper. Target Xcode/Bazel/macOS are
pinned in `versions.json` (app `12.8`, Xcode `26.2`, Bazel `8.4.2`, macOS `26`).
A matching Bazel binary is vendored at `build-input/bazel-8.4.2`, so you don't
strictly need `bazelisk`.

Canonical simulator build (from `CLAUDE.md`):

```sh
python3 build-system/Make/Make.py --overrideXcodeVersion \
  --cacheDir ~/telegram-bazel-cache \
  build \
  --configurationPath build-system/appstore-configuration.json \
  --gitCodesigningRepository <YOUR_CODESIGNING_REPO> \
  --gitCodesigningType development --gitCodesigningUseCurrent --buildNumber=1 \
  --configuration=debug_sim_arm64
```

Add `--continueOnError` while iterating so all compile errors surface in one
pass instead of stopping at the first.

### What you must supply (blocks a clean build today)
1. **`api_id` / `api_hash`** — create at <https://my.telegram.org> → API
   development tools. They go into the configuration JSON you pass to
   `--configurationPath`. Copy `build-system/appstore-configuration.json` to your
   own file, set your own `bundle_id` (e.g. `com.<you>.telegram`, **not**
   `org.telegram.*`), team id, and the api values.
2. **Codesigning** — the default config references a **private** repo
   (`git@gitlab.com:peter-iakovlev/fastlanematch.git`) you can't access. Replace
   it with either your own fastlane-match repo or, simplest for a personal
   device, point the build at your personal Apple Developer signing identity /
   provisioning profile. For a **simulator** build (`debug_sim_arm64`) signing is
   effectively a no-op — start there to validate the code before dealing with a
   device build (which hits the 7-day free-provisioning limit → weekly
   re-install, as the brief notes).

Start with `debug_sim_arm64` (no device, no paid account needed) to compile and
smoke-test the two presence features; move to `debug_arm64` (device) once the
code is green.

---

## 2. Integration point map (task #2) — verified

### 2.1 Incoming message deletion (anti-delete target)
`submodules/TelegramCore/Sources/State/AccountStateManagementUtils.swift`

Server "deleted" updates flow: `Api.Update.updateDeleteMessages` /
`updateDeleteChannelMessages` → collected into `AccountMutableState` operations
(`deleteMessagesWithGlobalIds` / `deleteMessages`) → **applied to Postbox** in
the big operation switch. The apply site is the interception point:

- `case .DeleteMessagesWithGlobalIds(ids)` — **~line 4464** (1:1 & group cloud
  chats; `ids` are global Int32, resolve with `transaction.messageIdsForGlobalIds(ids)`).
- `case .DeleteMessages(ids)` — **~line 4473** (channels/threads; `ids` are `MessageId`).
- `case .UpdateMinAvailableMessage` — **~line 4478** (range trim; lower priority).

Media resources are dropped right after via
`mediaBox.removeCachedResources(resourceIds, force: true)` — so anti-delete must
copy/pin media **before** the delete runs (§4.2).

### 2.2 Outgoing "online" presence (hide-online target)
`submodules/TelegramCore/Sources/State/ManagedAccountPresence.swift` —
`AccountPresenceManagerImpl.updatePresence(_:)` issues
`account.updateStatus(offline:)`. It is driven by the boolean signal
`Account.shouldKeepOnlinePresence` (`Account.swift:1199`), which the UI sets in
`SharedWakeupManager.swift:1150`. **Gating at that setter is the cleanest, least
invasive lever** — when hidden we feed `false`, and the presence manager then
actively reports `offline: .boolTrue` once and never schedules the online timer.

### 2.3 Outgoing "typing…" (hide-typing target)
`submodules/TelegramCore/Sources/State/ManagedLocalInputActivities.swift` —
`requestActivity(...)` sends `messages.setTyping`. Guarding the top of its
`postbox.transaction` block suppresses all outgoing activity while leaving
incoming activity of others untouched.

### 2.4 Settings storage pattern
Preferences structs are `Codable, Equatable`, persisted in Postbox preferences
under a `PreferencesKeys` `ValueBoxKey`, read in core via
`transaction.getPreferencesEntry(key:)?.get(T.self)` and reactively via
`postbox.preferencesView(keys:)`. `AppConfiguration.swift` /
`SyncCore_AppConfiguration.swift` are the reference pattern we mirror.

---

## 3. Saved-messages storage schema (task #3)

**Reuse Postbox** rather than a side SQLite file — it gives us the media box,
transactions, and the existing item-cache infrastructure for free.

### 3.1 Text/message snapshot — item-cache collection
Store each deleted message as a `Codable` snapshot in a dedicated item-cache
collection (same API `Wallpapers.swift`/`Themes.swift` use):

- Collection id: a new `ApplicationSpecificItemCacheCollectionId.ayuGramDeletedMessages`
  (next free Int8 in `submodules/TelegramUIPreferences/Sources/PostboxKeys.swift`).
- Entry key: `peerId (8 bytes) + messageNamespace (4) + messageId (4)` so entries
  are range-scannable per peer for the chat UI.
- Entry payload `StoredDeletedMessage` (Codable): `peerId`, `authorId`,
  `timestamp`, `deletionTimestamp`, `text`, encoded `[MessageAttribute]` markers
  we care about, and `mediaReferences: [PersistedMediaRef]` (see below). Encode
  media via Postbox's message coder rather than re-inventing a media codec.

### 3.2 Media — copy out of the GC'd namespace
The delete pipeline force-removes the original resource ids. Before that, for
each media resource copy the bytes into a **fork-private resource id namespace**
that upstream's GC never enumerates:

```
mediaBox.copyResourceData(from: originalId, to: ayuPersistentId, synchronous: false)
```

Derive `ayuPersistentId` deterministically (e.g. hash of original id prefixed
`ayu_del_`). Store `ayuPersistentId` in `PersistedMediaRef` so the "deleted
media" gallery can resolve files even after the originals are gone. For
self-destruct / TTL media the same copy-before-wipe applies.

### 3.3 Edit history (task, feature 1b)
On `updateEditMessage`, before overwriting, append the prior
`(timestamp, text, entities)` to a parallel item-cache collection
`ayuGramEditHistory` keyed by messageId → `[StoredEdit]`. Hook point:
`AccountStateManagementUtils.swift` where `.UpdateMessage`/edit is applied
(search `updateMessage` in the same operation switch).

---

## 4. Anti-delete implementation (the large piece)

### 4.1 New store module
`submodules/TelegramCore/Sources/AyuGram/DeletedMessageStore.swift`:

```swift
import Foundation
import Postbox

public struct PersistedMediaRef: Codable, Equatable {
    public var persistentResourceId: String
    public var originalResourceId: String
}

public struct StoredDeletedMessage: Codable, Equatable {
    public var peerId: Int64
    public var authorId: Int64?
    public var timestamp: Int32
    public var deletionTimestamp: Int32
    public var text: String
    public var media: [PersistedMediaRef]
}

private func deletedMessageKey(_ id: MessageId) -> ValueBoxKey {
    let key = ValueBoxKey(length: 8 + 4 + 4)
    key.setInt64(0, value: id.peerId.toInt64())
    key.setInt32(8, value: id.namespace)
    key.setInt32(12, value: id.id)
    return key
}

// Called from the delete apply-site BEFORE the messages are removed.
func ayuGramSaveDeletedMessages(transaction: Transaction, mediaBox: MediaBox, messageIds: [MessageId]) {
    for id in messageIds {
        guard let message = transaction.getMessage(id) else { continue }
        var media: [PersistedMediaRef] = []
        for m in message.media {
            for resource in mediaResources(m) {                 // small helper: enumerate resources of a Media
                let persistentId = MediaResourceId("ayu_del_\(resource.id.stringRepresentation)")
                mediaBox.copyResourceData(from: resource.id, to: persistentId, synchronous: false)
                media.append(PersistedMediaRef(
                    persistentResourceId: persistentId.stringRepresentation,
                    originalResourceId: resource.id.stringRepresentation
                ))
            }
        }
        let stored = StoredDeletedMessage(
            peerId: id.peerId.toInt64(),
            authorId: message.author?.id.toInt64(),
            timestamp: message.timestamp,
            deletionTimestamp: Int32(Date().timeIntervalSince1970),
            text: message.text,
            media: media
        )
        if let entry = CodableEntry(stored) {
            transaction.putItemCacheEntry(
                id: ItemCacheEntryId(collectionId: ApplicationSpecificItemCacheCollectionId.ayuGramDeletedMessages, key: deletedMessageKey(id)),
                entry: entry
            )
        }
    }
}
```

`mediaResources(_:)` is a small switch over the concrete `TelegramMedia*` types
returning their `.resource`s (image reps, file, etc.). `ApplicationSpecificItemCacheCollectionId`
lives in TelegramUIPreferences, which TelegramCore can't import — so either put
the collection-id constant directly in the store (an `Int8` literal namespaced to
the fork) or add it to Postbox's `Namespaces.CachedItemCollection`. Prefer a
fork-local literal to keep the change in one file.

### 4.2 Hook the delete apply-site
In `AccountStateManagementUtils.swift`, guard both cases on the toggle and save
first:

```swift
case let .DeleteMessagesWithGlobalIds(ids):
    if currentAyuGramSettings(transaction: transaction).keepDeletedMessages {
        ayuGramSaveDeletedMessages(transaction: transaction, mediaBox: mediaBox, messageIds: transaction.messageIdsForGlobalIds(ids))
    }
    var resourceIds: [MediaResourceId] = []
    transaction.deleteMessagesWithGlobalIds(ids, forEachMedia: { media in
        addMessageMediaResourceIdsToRemove(media: media, resourceIds: &resourceIds)
    })
    // ... unchanged ...

case let .DeleteMessages(ids):
    if currentAyuGramSettings(transaction: transaction).keepDeletedMessages {
        ayuGramSaveDeletedMessages(transaction: transaction, mediaBox: mediaBox, messageIds: ids)
    }
    _internal_deleteMessages(...)   // unchanged
```

This preserves upstream behavior exactly (DB stays consistent with the server)
while snapshotting into the graveyard — the low-risk design the brief prefers
("separate local storage"). Media survive because we copied them to `ayu_del_*`
ids before `removeCachedResources` runs.

### 4.3 Read API for the UI
Add to `DeletedMessageStore.swift`:

```swift
public func ayuGramDeletedMessages(postbox: Postbox, peerId: PeerId) -> Signal<[StoredDeletedMessage], NoError> {
    return postbox.transaction { transaction -> [StoredDeletedMessage] in
        var result: [StoredDeletedMessage] = []
        // range-scan the collection for keys prefixed by peerId
        // (transaction.scanItemCacheEntries / retrieveItemCacheEntry)
        return result
    }
}
```

### 4.4 In-chat UI (feature 1, UI part)
Two surfaces, both additive:
1. **In-place marker** — when rendering, tint the bubble background and add a
   "deleted" badge for messages present in the graveyard. Lightest touch: a chat
   controller overlay driven by `ayuGramDeletedMessages(...)`, avoiding edits to
   the message-node layout system.
2. **"Deleted media" section** — a new gallery controller in `submodules/GalleryUI`
   fed by the persisted `ayu_del_*` resources, opened from a chat-info row.

Keep both read-only over the store so they never touch the sync pipeline.

---

## 5. Settings toggle (task #4)

**Model — done** (`AyuGramSettings.swift`): `keepDeletedMessages`,
`saveEditHistory`, `hideOnlineStatus`, `hideTyping`, persisted in Postbox
preferences, with sync (`currentAyuGramSettings(transaction:)`) and reactive
(`ayuGramSettings(postbox:)`) accessors plus an `updateAyuGramSettings` writer.

**Presence/typing wiring — done** (see §2.2/§2.3 patches on the branch).

**UI screen — to add:** a new `AyuGramSettingsController.swift` in
`submodules/SettingsUI/Sources/`, modeled on any existing toggle controller
(e.g. `DataAndStorageSettingsController.swift`). Pattern:

```swift
// switches read ayuGramSettings(postbox:) and write via:
let _ = updateAyuGramSettings(postbox: context.account.postbox) { current in
    var settings = current
    settings.hideOnlineStatus = value
    return settings
}.start()
```

Add one entry row in the root settings list
(`submodules/SettingsUI/Sources/SettingsController.swift`) that pushes this
controller. This is the only place that reaches into an existing large UI file;
everything else is additive.

---

## 6. Upstream update strategy (task #5)

Design goal already reflected in the code: **isolate the fork so weekly
`git rebase` onto upstream is near-conflict-free.**

### Layout
- **New files only** where possible: everything under
  `submodules/TelegramCore/Sources/AyuGram/` and the new SettingsUI/GalleryUI
  controllers never conflict.
- **Feature flag key = 1000** avoids the one file (`PreferencesKeys`) that
  upstream edits most.
- **Existing-file edits are minimal and guarded** — currently exactly three
  hunks (typing gate, online gate, and the delete hook), each 3–10 lines and
  clearly commented `// AyuGram:` so they're greppable and re-appliable.

### Workflow
```sh
git remote add upstream https://github.com/TelegramMessenger/Telegram-iOS.git
git fetch upstream
git checkout ayugram
git rebase upstream/master          # or the tag matching versions.json app number
# resolve only the 3 guarded hunks if their surrounding code moved
git tag ayugram-$(date +%F)         # snapshot each weekly rebuild
```

Keep the three existing-file edits as a **thin patch series** you can re-apply if
a rebase gets messy:
```sh
git format-patch upstream/master --output-directory .ayugram-patches -- \
  submodules/TelegramCore/Sources/State/ManagedLocalInputActivities.swift \
  submodules/TelegramUI/Sources/SharedWakeupManager.swift \
  submodules/TelegramCore/Sources/State/AccountStateManagementUtils.swift
```
The additive files need no patch management — they just travel with the branch.

### When a rebase conflicts
Conflicts will only ever be in those three files. The `// AyuGram:` comments mark
exactly what to re-insert; the logic doesn't depend on surrounding upstream code
beyond the anchor lines named in §2, so re-anchoring is mechanical.

---

## 7. Open follow-ups
- Compile the branch on `debug_sim_arm64` and fix any `-warnings-as-errors`
  issues (TelegramCore treats warnings as errors).
- Implement §4 (graveyard store + hook + read API) and §5 (settings screen).
- Edit-history capture (§3.3) and the in-chat deleted-media UI (§4.4).
- Decide retention policy for the graveyard (cap size / age) so it doesn't grow
  unbounded — add a periodic prune in a managed operation.

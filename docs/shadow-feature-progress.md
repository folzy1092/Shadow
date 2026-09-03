# Shadow feature implementation

## Settings export/import

Implemented in `ShadowSettingsDocument`, `ShadowSettingsTransfer` and
`ShadowSettingsBackupController`. Entry: Shadow > Резервная копия настроек.

- Versioned JSON, strict types, maximum 1 MiB; unknown fields ignored.
- Explicit portable allowlist. No sessions, spoof values, background files or paths.
- Missing fields preserve their current values. No reset of settings introduced
  after an older export. Local-only fields are not imported.
- Preview includes changed sections/count and resulting Ghost master state.
- If settings change after preview, import refuses and asks for a fresh preview.
- Backup and application use one transaction in the captured account's Postbox.
- One local undo snapshot. Undo explicitly warns about subsequent settings edits.
- Coordinated, bounded file-provider reads; iPad popover anchor; temporary export
  cleanup on completion/cancellation.

Filter-rule transfer will be added with the filtering feature, not exposed as a
nonfunctional control in this commit.

Validation performed on Linux: 8 structural transfer tests, Swift syntax parsing,
existing CI/visual contracts and workflow shell/YAML checks. The committed
Foundation executable tests are wired into Actions but require `swiftc` and were
not executed on this Linux host. UIKit/Postbox type-checking and on-device testing
remain pending an iOS build. Structural checks do not establish UI correctness.

Device checklist: export/share/cancel on iPhone and iPad; invalid/oversized/newer
JSON; import and undo; cancel import; change Ghost while preview is open; switch
accounts; kill/relaunch; background during document selection/export.

## Pending features

- Search in Shadow settings.
- Scroll-driven tab bar visibility.
- Message filtering and rule transfer.
- Message screenshots.
- Replies to locally preserved deleted messages.

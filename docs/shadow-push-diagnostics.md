# Shadow push diagnostics

Settings → Shadow → Диагностика push (also searchable).

This patch diagnoses delivery; it does not create APNs provider credentials,
change the bundle identity, or replace the fake-sign → ESign workflow.

The current `.bazelrc` explicitly sets `build --//Telegram:disableExtensions`.
Consequently the absence of NSE in a re-signed IPA does not demonstrate that
the re-signer removed it. The app also falls back to local Documents storage
when the expected App Group is unavailable; NSE has no equivalent shared-data
fallback. Re-enabling extensions requires a separate signing/data-sharing plan.

## Evidence exposed

- iOS authorization and alert/sound/badge settings, live while the page is open.
- Calls to APNs registration and its success/failure callbacks in this process.
- The APNs token is kept only in memory, hidden until explicitly revealed, and
  removed from the existing general-purpose registration log.
- Bundle ID and the main executable's embedded XML signing entitlements.
  This is not the profile's entitlement allowlist, not a kernel query and not
  cryptographic validation; unsupported/DER-only signatures are unknown.
- DEBUG/release and the actual Telegram appSandbox switch (still DEBUG-derived).
- The selected account's APNs and VoIP registerDevice status, separately.
  Server Bool=false and all RPC errors are preserved. Only
  TOKEN_WAS_INVALIDATED initiates the existing one-token invalidation policy;
  ordinary RPC failures no longer masquerade as success or cause a token loop.
- Expected App Group accessibility, NSE bundle detection, and a last lifecycle
  event written by the NSE to the expected shared group (no payload or key).

Registration diagnostics are session-local. NSE timestamps can be older and
refer to the shared installation, not necessarily the currently selected account.
NSE presence is not evidence of invocation, decryption, or display. A server
acknowledgement is not evidence of an accepted/delivered APNs request.

## Reproduce

1. Build this branch and export the final IPA after ESign signing.
2. Install, sign in and enable notification presentation in iOS.
3. Open the diagnostics screen and record signing and registration fields.
4. If needed, use “Повторить регистрацию push”; it retries both registration
   paths without clearing app data or requesting new display authorization.
5. Lock the phone / leave the app normally (do not swipe-force-quit for the
   baseline test). Send a new unmuted message from a different account.
6. Reopen diagnostics and compare NSE timestamps with that test.
7. A failure before the APNs callback is client-side. A registerDevice RPC
   failure is Telegram registration. If both succeed, the missing evidence is
   the provider's APNs response/topic/environment and delivery record.

Do not upload device tokens, signing files, profiles, account encryption data,
API hashes or provider credentials to public issues or the repository.

## Verification

`python3 -B -m unittest discover -s Tests/ShadowSettings -p 'test_*.py'`
checks source wiring; `python3 build-system/ci/test_shadow_foundation.py`
compiles and executes the state and binary-reader fixtures with Swift.
The dedicated diagnostics workflow needs no secrets. It parses changed Swift
files and runs these checks; it is not a full Telegram iOS/Bazel build.
The existing full build workflow and its signing steps remain unchanged.

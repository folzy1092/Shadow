# Wide channel posts

The existing customization switch already persists and supports export/import.
It now invalidates the current account's history presentation when toggled.

Root cause: broadcast posts already set `allowFullWidth` in native layout. Merely
setting it again, or increasing the maximum constraint, did not stop final bubble
width from shrinking to a short text/document. The old extra padding override also
bypassed special content limits.

Fix: use the history's account-local setting and expand the **final** content
width to the content nodes' supported maximum before their finalize closures.
Text/document/status/reactions/buttons and the bubble then use the same width.
Keep both content insets and the native forward-button reservation. No self-frame
mutation, fixed device width, stretching image aspect ratios or private-chat changes.

Applies in broadcast-channel peer histories. Native caps for individual media and
special nodes remain; albums, round videos, transparent/centered service nodes,
ads, recent actions and screenshot previews keep native geometry.

Checks: Python regression contracts and Swift syntax parsing. Device checklist:
short text, long text, document/caption, poll, image, album, round video, reactions,
comments, keyboard buttons, forwarding; portrait/landscape/iPad; toggle while a
channel is open; two accounts; forwarded post in PM; off state vs upstream.
Full macOS app compilation and visual validation are still required.

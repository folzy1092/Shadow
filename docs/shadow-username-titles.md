# Username titles

Shadow → Кастомизация → «@username вместо имени незнакомых» (off by default).

An account-local presentation option. A non-contact user with an active username
is displayed as `@username` in the main chat list, both chat title implementations,
the profile header, and normal message-author headers. Saved contacts, self,
service dialogs, groups/channels and users without a username keep native titles.
Unknown contact state also keeps the native title; no contact/peer records are
rewritten. RTL isolation keeps badges and the @ prefix outside nickname bidi text.

The option updates open views through account preference subscriptions and is
included in settings export/import and search. Special search results, forwarded
attribution, typing indicators and sticker-specific headers retain native naming.
Screenshot previews intentionally use original names, independent of this option.

Validation: Foundation formatter tests (run in CI with Swift), Python integration
contracts, Swift syntax parsing. On iPhone, test two accounts with opposite toggle
values, add/remove a contact, remove/change username, RTL names, switch themes and
reopen the app. Full app compilation and runtime checks still required.

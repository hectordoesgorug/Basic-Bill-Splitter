# Development Progress

This file records the verifiable implementation state of Basic Bill Splitter. Automated checks, hardware acceptance, Git publication, and releases are tracked separately.

| Area | Status | Notes |
| --- | --- | --- |
| Offline bill calculation and five-step workflow | Implemented | Pure-Dart allocation engine; integer-cent reconciliation and validation remain the calculation authority. |
| Saved bills and billing periods | Implemented | Android app-private SQLite, category/majority-month uniqueness, continuity suggestions, and overlap warnings. |
| History and PNG sharing | Implemented | Annual category graphs, saved snapshots, reusable card, and Android image sharing. |
| Settings and data management | Implemented | ZIP Backup/Restore, Clear All for drafts, Wipe Data for saved bills, and persisted Dark Mode. |
| Current refinements | Implemented | Currency display, safe single-record History deletion, saved computation explanations, corrected card text, and accessible date confirmation. |
| Automated verification for current refinements | Tested | Dart formatting check, Flutter analysis, 195 Flutter tests, Kotlin compilation, debug APK build, and `git diff --check` passed. |
| Physical-device acceptance | Pending | No device verification is claimed for the current refinements. |
| Git publication | Not performed | Source changes remain local until separately reviewed and authorized. |
| Release | Not performed | No release or APK distribution is part of this work. |

## Current Limitations

- Drafts remain in memory and are not restored after process termination.
- Currency selection changes denomination labels only. No exchange-rate conversion is performed; mixed-currency graph values are not financially equivalent comparisons.
- ZIP backups are not encrypted and should be stored securely.
- Physical-device checks for date-picker layout, deletion interaction, currency persistence, and accessibility remain pending; automated tests and compilation do not verify those runtime behaviors.

## Deferred

- Currency conversion and exchange-rate services.
- Saved-bill editing, Undo, and revision history.
- Cloud synchronization, scheduled backups, and encrypted backups.
- History export galleries and bulk deletion.
- Itemized billing and saved household profiles.

## Next Priorities

1. Review the implemented refinements and verification results.
2. Perform isolated physical-device acceptance checks when installation is separately authorized.
3. Keep source changes local until Git operations are separately authorized.

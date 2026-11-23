# Development Progress

Basic Bill Splitter v1.0.0 is the first published stable release. This page
records the committed MVP, historical and release verification, owner-reported
device acceptance, current limitations, and deferred work.

## Implementation and Source Baseline

| Area | Status | Notes |
| --- | --- | --- |
| Offline bill calculation and five-step workflow | Implemented | Pure-Dart allocation engine; integer-cent reconciliation and validation remain the calculation authority. |
| Saved bills and billing periods | Implemented | Android app-private SQLite, category/majority-month uniqueness, continuity suggestions, and overlap warnings. |
| History and PNG sharing | Implemented | Annual category graphs, saved snapshots, reusable card, and Android image sharing. |
| Settings and data management | Implemented | ZIP Backup/Restore, Clear All for drafts, Wipe Data for saved bills, and persisted Dark Mode. |
| Currency and History refinements | Implemented | Currency display, safe single-record History deletion, saved computation explanations, corrected card text, and accessible date confirmation. |
| MVP implementation baseline | Committed and pushed | `a94a96b8c521fc1e7363180679f8ae6e08e47d53` contains the completed MVP implementation. Repository review on 2026-11-23 confirmed that it matched local `main`, `origin/main`, and live remote `main` at that time. |
| Documentation and metadata | Committed and pushed | `86e2a9605b0e92d2732c0fa9ebe5337cb0c9f63d` is the subsequent documentation-and-metadata commit. The editorial review confirmed local `main`, `origin/main`, and live remote `main` at this commit. |
| Project license | Committed and pushed | MIT License; Copyright (c) 2026 hectordoesgorug. Added in commit `e6e3ee6f6ccb7f7246ad48229b1a0260fdd75f60`. |
| Production release | Published stable | v1.0.0 (`1.0.0+1`), published 2026-11-23. See [Published Release](#published-release) for the tag target, APK, and checksum. |

The implementation and subsequent documentation, metadata, license, and signing
commits remain recorded above. The release tag points to the completed source
baseline; release publication did not add or change a source commit.

## Verification and Device Acceptance

The earlier MVP verification report recorded Dart formatting, Flutter analysis,
Kotlin compilation, a debug APK build, and `git diff --check` passing, with 195
Flutter tests passing. These are historical results from the MVP implementation
baseline.

Release verification on 2026-11-23 recorded:

- `dart format --set-exit-if-changed lib test` passed; 32 files were checked and none changed.
- `flutter analyze` passed with no issues.
- `flutter test` passed all 198 tests.
- A separate clean checkout of commit `0f432caf60cdb7535df552340c5cdf219ef1ef9e` restored dependencies and built a debug APK. Flutter supplied the ignored Gradle wrapper components and `local.properties` from the local SDK setup.
- `flutter build apk --release` produced the production-signed universal APK. `apksigner verify --print-certs` passed, and the certificate matched the established production fingerprint.
- APK identity, SDK metadata, and permissions were inspected: application ID `com.hectordoesgorug.basic_bill_splitter`, version `1.0.0` (code `1`), minimum SDK 24, target SDK 36, and no network or broad storage permission.
- The APK SHA-256 was verified as `C44D709686C46C9C9583C372C976CBF44C703B0FA065E599C11034645E23A6C1`.
- The release APK contains Flutter's generated `NOTICES.Z` asset, including the listed native Android dependency notice markers and license text. Bundled image assets and compiled launcher icon resources were also inspected.
- `git diff --check` passed before release publication.

Owner-reported device acceptance: the signed APK was manually installed and
tested on a Poco X6 running Android 16, with no issues reported. No individual
device test-case results are recorded here. A same-signature upgrade from an
earlier production-signed build was not verified; a debug-signed installation
is not a valid upgrade baseline.

## Current Limitations

- Drafts remain in memory and are not restored after process termination.
- Currency selection changes denomination labels only. No exchange-rate conversion is performed; mixed-currency graph values are not financially equivalent comparisons.
- ZIP backups are not encrypted and should be stored securely.
- History snapshots are read-only apart from deletion. The active Results workflow can update its saved record after recalculation; reopening a historical record for editing is not implemented.

## Published Release

The first stable release, [v1.0.0](https://github.com/hectordoesgorug/Basic-Bill-Splitter/releases/tag/v1.0.0),
was published on 2026-11-23 from annotated tag `v1.0.0`, which targets
`0f432caf60cdb7535df552340c5cdf219ef1ef9e`. The release contains the universal
production-signed APK `Basic-Bill-Splitter-v1.0.0.apk` and its `.sha256` file.
The APK checksum is recorded above and in the published release assets.

The v1.0.0 artifact, signer, package identity, SDK metadata, and bundled notices
were inspected before publication. The signed release APK was built from the
primary checkout. Fresh-checkout verification covered dependency restoration and
a debug build, not a signed release build. See [Architecture](ARCHITECTURE.md#build-configuration-and-fresh-checkouts)
for the ignored Gradle wrapper behavior.

The owner-reported Poco X6 acceptance and the unverified same-signature upgrade
are recorded in [Verification and Device Acceptance](#verification-and-device-acceptance).
The published APK and checksum remain available from the GitHub Release.

## Deferred

- Currency conversion and exchange-rate services.
- Reopening saved History bills for editing, Undo, and revision history.
- Cloud synchronization, scheduled backups, and encrypted backups.
- History export galleries and bulk deletion.
- Itemized billing and saved household profiles.

# Development Progress

The MVP feature set is implemented. This page records committed source,
historical automated results, reported manual testing, and pending release
preparation.

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
| Production release preparation | Pending | Package version remains `1.0.0+1`. Release-version approval, signed-candidate verification, and publication remain pending. The signing identity and local signing setup are prepared. |

The earlier progress page described the refinements as local and physical-device
checks as pending. Source publication and reported manual testing subsequently
superseded that status. The commits above distinguish the implementation baseline
from the later documentation and metadata updates.

## Historical Verification and Device Acceptance

The MVP's prior verification report recorded:

- Dart formatting passed.
- Flutter analysis passed.
- 195 Flutter tests passed.
- Kotlin compilation passed.
- Debug APK build passed.
- `git diff --check` passed.

Manual acceptance testing on a Poco X6 running Android 16 was subsequently
confirmed. These checks have not been independently repeated as part of
release-candidate validation. No individual case log is recorded here for
date-picker layout, deletion, currency persistence, or accessibility; those
scenarios still require release-candidate verification.

These results are historical. They are not fresh verification of a signed release
candidate. The repository documentation and package-description review did not
rerun Flutter tests, compile Kotlin, build an APK, or install on a device.

## Current Limitations

- Drafts remain in memory and are not restored after process termination.
- Currency selection changes denomination labels only. No exchange-rate conversion is performed; mixed-currency graph values are not financially equivalent comparisons.
- ZIP backups are not encrypted and should be stored securely.
- History snapshots are read-only apart from deletion. The active Results workflow can update its saved record after recalculation; reopening a historical record for editing is not implemented.

## Release Preparation

The dependency notices and asset provenance are now documented, and the app
provides offline access to its bundled Flutter and native notices. The following
release steps remain:

1. Approve the release version/build number.
2. Review the current documentation and establish an approved source baseline.
3. Inspect the signed release APK to confirm generated notices are packaged and
   readable through About → Third-Party Licenses. Debug packaging was checked;
   release packaging remains pending.
4. Verify build setup from a fresh checkout with a recorded Flutter SDK revision.
   See [Architecture](ARCHITECTURE.md#build-configuration-and-fresh-checkouts) for
   ignored wrapper components and Flutter's bootstrap behavior.
5. Run applicable automated checks, then validate the signed candidate on an
   authorized test device with isolated data: clean install and upgrade, restart
   persistence, calculation/save/replace/delete, currency and Dark Mode, PNG
   recipient access, valid and invalid ZIP restores, and Clear All versus Wipe Data.
6. Inspect APK identity, version, permissions and signer; record SHA-256, prepare
   release notes, and obtain final approval before tagging or publishing.

## Deferred

- Currency conversion and exchange-rate services.
- Reopening saved History bills for editing, Undo, and revision history.
- Cloud synchronization, scheduled backups, and encrypted backups.
- History export galleries and bulk deletion.
- Itemized billing and saved household profiles.

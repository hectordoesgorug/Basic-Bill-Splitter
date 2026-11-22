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
| Production release preparation | Pending | Package version remains `1.0.0+1`. Release-version approval, signing-key creation, signed-candidate verification, and publication remain pending. |

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

The following work remains before a first production release:

1. Approve the release version/build number. The MIT license is committed in the root `LICENSE`.
2. Review the documentation changes and establish an approved source baseline.
3. Complete dependency and asset attribution review. Local resolved packages
   `material_ui` 1.11.1 and `cupertino_ui` 1.1.7 contain BSD three-clause terms;
   `cupertino_icons` 1.0.9 contains MIT terms. Their notices must be preserved as
   required for distribution. This focused review is not a complete inventory of
   transitive Dart, Flutter engine, Android, or bundled font notices.
4. Verify the final artifact's bundled notices and how users or recipients can
   access required terms. The current About dialog has no license-viewing entry
   point. Existing debug outputs contain `NOTICES.Z`; their presence alone does
   not establish complete release attribution. Keep the README's GitHub logo
   attribution. The repository has no separate provenance/license record for
   `assets/app_icon.png` or `assets/banner.png`; confirm their distribution rights.
5. Create and securely back up the production keystore, configure local signing
   properties, then verify the signed candidate. The release signing configuration
   is prepared, but no production key exists in this repository and no signed
   candidate has been built.
6. Verify build setup from a fresh checkout with a recorded Flutter SDK revision.
   See [Architecture](ARCHITECTURE.md#build-configuration-and-fresh-checkouts) for
   ignored wrapper components and Flutter's bootstrap behavior.
7. Run applicable automated checks, then validate the signed candidate on an
   authorized test device with isolated data: clean install and upgrade, restart
   persistence, calculation/save/replace/delete, currency and Dark Mode, PNG
   recipient access, valid and invalid ZIP restores, and Clear All versus Wipe Data.
8. Inspect APK identity, version, permissions and signer; record SHA-256, prepare
   release notes, and obtain final approval before tagging or publishing.

## Deferred

- Currency conversion and exchange-rate services.
- Reopening saved History bills for editing, Undo, and revision history.
- Cloud synchronization, scheduled backups, and encrypted backups.
- History export galleries and bulk deletion.
- Itemized billing and saved household profiles.

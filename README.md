# Basic Bill Splitter

![Basic Bill Splitter — Simple, exact shared-bill calculation](assets/banner.png)

Basic Bill Splitter is an offline Flutter Android app for sharing residential
expenses among households. Calculate each expense independently, one bill at a
time, using measured consumption, occupancy days, or equal household shares.
The Android launcher name is **Splitter**. No account is required.

The MVP is implemented and accepted. Production release preparation is still
pending; this README does not offer a production APK download.

## Features and expense categories

- Exact integer-cent totals with deterministic rounding.
- Occupancy by Full Period, manual day count, or multiple date ranges.
- Local saved bills, annual History, and stored computation explanations.
- PNG result sharing, manual ZIP Backup/Restore, Dark Mode, and Currency settings.

| Expense category | Default allocation method |
| --- | --- |
| Electricity | Hybrid |
| Water | Hybrid |
| Internet | Person-days |
| Rent | Person-days |
| LPG | Person-days |
| Miscellaneous (Misc on Home) | Equal per household |

You can choose another supported method for the current bill:

- **Hybrid:** charge measured usage, then share remaining usage by person-days
  across **all occupants, including those with measured usage**.
- **Person-days:** weight each occupant by occupancy duration and aggregate
  their shares by household.
- **Equal per household:** divide the bill among households. This method does
  not assign individual monetary shares.

## Requirements and running from source

Android is the primary platform. Development requires a Flutter SDK with Dart
compatible with the constraints in [pubspec.yaml](pubspec.yaml), Android SDK
tooling, and a configured Java toolchain. See the
[build configuration notes](docs/ARCHITECTURE.md#build-configuration-and-fresh-checkouts)
for the current toolchain and Gradle wrapper behavior.

From the repository root:

```text
flutter pub get
flutter run
```

Select a connected Android device or emulator when running. Dependency resolution
and initial toolchain setup may require internet access; core app operations work
offline. These commands run a development build.

## Getting started

Choose one of the six expense categories on Home, then follow
**Details → Households → Usage → Review → Results**.

1. **Details:** enter the amount and inclusive billing period, choose a method,
   and provide total consumption for Hybrid.
2. **Households:** name households and set 1–10 occupants each. The stepper
   allows zero while editing, but validation requires at least one occupant.
3. **Usage:** optionally enter measured consumption and select occupancy
   durations. Manual days must fit the period; date ranges must be within it
   and cannot overlap for the same occupant, including shared endpoints.
4. **Review:** check the inputs and calculate.
5. **Results:** inspect household totals and applicable occupant amounts,
   then Save, Share, or Exit.

Amounts accept plain decimal digits with up to two decimal places, such as
`1234.56`. Zero bills are valid. Hybrid requires positive total consumption,
and measured usage cannot exceed it. Earlier available tabs preserve draft
inputs; changing inputs requires calculation again. Section Clear actions reset
their respective inputs after confirmation when needed.

## Saving, History, sharing, and settings

**Save** stores the completed calculation on this Android device. A record is
assigned to the month containing the most billing-period days; ties go to the
later month. Only one bill per category and assigned month is saved.
Replacement requires confirmation. New drafts suggest a period after the latest
saved bill in that category; overlapping periods show a warning.

Open **History** from the menu to choose a category and year, view monthly
amounts, and open a saved bill's Card, Details, or Computation. Saved results are
historical snapshots and are never recalculated. Long-press a bill entry to
reveal Delete, then confirm removal.

**Share** opens Android's share chooser with a PNG card from Results or History.
Sharing does not save a bill. Results **Exit** returns Home and offers Save &
Exit, Exit Without Saving, or Cancel for unsaved or changed calculations.
The menu's Exit command closes the Android activity.

**Settings** provides Backup, Restore, Clear All, Wipe Data, Dark Mode, and
Currency. Appearance and currency preferences persist separately from saved bills.

## Backup, Restore, and local-data privacy

Saved bills use app-private SQLite storage. Core calculation, storage, History,
and sharing need no account or network service. Visit GitHub opens an external
browser only when selected.

- **Backup:** export saved bills to a ZIP at a destination chosen in Android's
  document picker. Drafts, preferences, and share-cache files are excluded.
- **Restore:** validate a compatible ZIP, then confirm replacement of **all**
  saved bills. This is not a merge; bills absent from the backup are removed.
  A successful restore also clears the active draft.
- **Clear All:** discard only the current calculation; saved bills remain.
- **Wipe Data:** permanently delete saved bills after confirmation and clear
  the active calculation. Preferences remain.

**Exported ZIP backups are unencrypted and may contain household and billing
details. Store them securely.** Keep a separate backup before replacing or
deleting saved bills. Android automatic backup is disabled and database files
are excluded from device transfer; manual ZIP backup is the supported recovery
workflow. Shared PNGs also contain bill details and are passed to the recipient
you choose. See [Data storage](docs/DATA_STORAGE.md) for format and privacy details.

## Limitations and important behavior

- Drafts stay in memory and are lost after process termination.
- Currency selection changes labels and formatting; **it does not convert
  amounts**. PHP is the default. Saved bills keep their stored currency.
- All currencies display two decimal places. Mixed-currency graphs plot
  unconverted values and are not financially equivalent comparisons.
- The app does not provide itemized bills, saved household profiles, payment
  tracking, cloud synchronization, or encrypted backups.
- History is read-only apart from deletion; reopening historical bills for
  editing, Undo, and revision history are not implemented.

## Development and technical documentation

Read [AGENTS.md](AGENTS.md) before changing the project.

- [Architecture](docs/ARCHITECTURE.md): components, workflow, calculator contract,
  rounding example, tests, optional private fixture, and build setup.
- [Data storage](docs/DATA_STORAGE.md): saved snapshots, billing-date rules,
  currency compatibility, backup/restore, and privacy.
- [Progress](docs/PROGRESS.md): accepted MVP, historical verification, and pending
  release-candidate checks.

Standard checks from the repository root:

```text
dart format lib test
flutter analyze
flutter test
git diff --check
```

An Android debug build uses `flutter build apk --debug`. Platform-channel mocks
and widget tests do not establish physical-device behavior. Historical test and
owner-reported device results are recorded separately in Progress.

## Third-party attribution and licensing status

The locally bundled black and white GitHub Invertocat PNGs come unchanged from
[GitHub's official logo download](https://brand.github.com/GitHub_Logos.zip).
They appear only beside the repository link, with clear space and theme-appropriate
contrast, following the [GitHub logo guidelines](https://brand.github.com/foundations/logo).
GitHub and the Invertocat mark are trademarks of GitHub, Inc.; the link does not
imply sponsorship or endorsement.

The project has no root LICENSE file; selection of a project license remains an
owner decision. Third-party packages and assets retain their own terms.
Dependency notices and their distribution requirements still need a release
review; see [Progress](docs/PROGRESS.md#release-preparation).

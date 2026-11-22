# Application Architecture

## Overview

Basic Bill Splitter is an offline-first Flutter application for calculating one residential expense at a time. Flutter owns the workflow and presentation. A pure-Dart calculation layer owns allocation and cent reconciliation. On Android, a small native storage component persists completed calculation snapshots in app-private SQLite.

The current UI has five steps: Details, Households, Usage, Review, and Results. The working draft is transient; saved completed calculations are durable. Saved household profiles and persistent drafts are not part of the design.

## Layers and Data Flow

```mermaid
flowchart LR
  UI[Home and workflow UI] --> Draft[BillDraft parsing and validation]
  Draft --> Models[Typed Bill inputs]
  Models --> Engine[BillCalculator]
  Engine --> Results[BillAllocation and Results UI]
  Results --> Snapshot[SavedBillRecord snapshot]
  Snapshot --> Repository[BillRepository]
  Repository --> Channel[Flutter MethodChannel]
  Channel --> SQLite[Android SavedBillDatabase]
```

Data moves from **User Input → Draft Validation → Calculation Engine → Results → Persistent Storage**. The storage layer records the validated inputs and calculated output as a snapshot; it does not perform or revise allocations.

## Flutter Components

| Path | Responsibility |
| --- | --- |
| `lib/main.dart` | App entry point, root-owned Material 3 light/dark themes, persisted appearance loading, and Home route |
| `lib/app/home_screen.dart` | Home category selection, fresh draft creation, saved-period continuity suggestion, and app shell |
| `lib/app/app_menu.dart` | About, How to, History category selection, Settings navigation, and activity Exit |
| `lib/app/app_platform.dart` | Android method-channel wrapper for repository access, SAF backup/restore, appearance preferences, PNG sharing, version lookup, repository link, and activity exit |
| `lib/workflow/bill_draft.dart` | Transient fields, category/method defaults, parsing, date and form validation, and typed Bill construction |
| `lib/workflow/bill_workflow.dart` | Five-step UI, validation-gated navigation, result invalidation, calculation, save/replace/exit flows, and result display |
| `lib/workflow/date_range_fields.dart` | Billing and occupancy date selection and input |
| `lib/workflow/household_section.dart` | Shared household grouping and presentation |
| `lib/calculation/bill_models.dart` | Typed Bill, Household, Occupant, and immutable allocation models |
| `lib/calculation/bill_calculator.dart` | Pure-Dart input validation, allocation, and deterministic cent reconciliation |
| `lib/storage/bill_repository.dart` | Repository contract, platform implementation, save and replace-all result types, and in-memory test implementation |
| `lib/storage/saved_bill_record.dart` | Versioned record metadata, backward-compatible currency decoding, snapshot JSON encoding/decoding, and consistency validation |
| `lib/currency/currency.dart` | Fixed supported-currency list, code validation, and integer-cent formatting |
| `android/app/src/main/kotlin/com/hectordoesgorug/basic_bill_splitter/SavedBillBackup.kt` | Native version 1 ZIP creation, checksum, entry limits, and archive validation |
| `lib/storage/billing_period.dart` | Pure-Dart assigned-month, inclusive overlap, and next-period rules |
| `lib/history/bill_history_screen.dart` | Category/year History, monthly graph/list, stale-safe single-record deletion, and read-only Card/Details/Computation views |
| `lib/history/bill_computation_view.dart` | Plain-language explanation using stored inputs and saved allocations; never recalculates historical bills |
| `lib/app/settings_screen.dart` | Backup, validated full-replacement restore, current-draft clearing, saved-record wiping, Dark Mode, and Currency preferences |
| `lib/sharing/bill_share_card.dart` | Reusable current/saved snapshot card data and visual card |
| `lib/sharing/bill_share_export.dart` | Full-card PNG rendering and Android share-channel orchestration |

## Workflow and Validation

Home creates a new `BillDraft` when a category is selected. The draft supplies the category's default allocation method and a default calendar period; Home may asynchronously replace that period with a continuity suggestion from the repository. It applies the suggestion only while the same draft still has its original default dates.

The workflow validates Details, Households, and Usage before enabling later tabs. Review validates the full draft again before Calculate. `BillDraft` parses currency to integer cents and consumption separately from widgets; `toBill()` is used only after field validation. The calculator repeats boundary validation independently.

The 0–10 headcount control is a presentation limit. Zero can be selected, but household validation requires 1–10 participants. Inactive occupant draft entries can remain when the count is reduced so restoring a count restores prior inputs; Clear explicitly resets those entries.

## Calculation and Results

`BillCalculator` is stateless and has no Flutter or storage dependencies. It returns household allocations in input order and occupant allocations for Hybrid and Person-days. Equal-per-household returns no occupant monetary allocation. Integer cents are reconciled using deterministic largest remainders, with input order breaking ties.

Input edits clear the in-memory bill and allocation. Results navigation is available only while a valid allocation exists. Reopening earlier inputs without editing retains the calculation; editing requires validation and calculation again. Review's Calculate action creates a fresh allocation from the current draft rather than using a prior result.

The workflow creates the saved snapshot only from the current calculated bill and allocation. A saved snapshot is a historical result and is not silently recomputed when the calculator changes. History loads records through `BillRepository`, filters by category and assigned year/month, and displays stored allocations without invoking `BillCalculator`. Annual graphs represent one saved bill per populated month; a saved zero-cent value is distinct from a missing month.

Both current Results and saved History records map to `ShareBillCardData`. `ShareBillCard` renders the concise monetary card, and `bill_share_export.dart` captures the entire variable-height card as a PNG. The Android method channel passes PNG bytes to a native `FileProvider` share intent. The provider exposes only temporary files under its dedicated cache subdirectory; sharing does not save or change a bill.

`SettingsScreen` is opened from the shared app menu on Home or during a workflow. It reuses `BillRepository` for backup snapshots, validated full replacement, and saved-record wipe. Clear All calls the Home draft-reset callback and leaves the repository untouched. Successful restore or wipe also clears the active draft so a Results screen cannot retain stale saved-state references. The root `MyApp` owns Light/Dark theme and current-currency state; Settings persists both through Android preferences. Currency changes affect new/current unsaved calculations, while saved records render with their stored currency.

## Android Storage Boundary, Settings, and Errors

Dart code talks to the `BillRepository` abstraction. `PlatformBillRepository` encodes records and invokes the `basic_bill_splitter/app` method channel. The Kotlin `MainActivity` dispatches SQLite work on a single-thread executor and posts results back to the Flutter main thread. `SavedBillDatabase` owns SQLite operations. The repository contract also has an in-memory implementation for deterministic Dart tests.

`SettingsScreen` uses this same repository for listing, full replacement, and wipe; it does not access SQLite directly. History deletion targets a stable record ID and expected update timestamp through the same repository boundary. Backup and restore use Android's Storage Access Framework document picker. Native `SavedBillBackup` writes and validates the versioned ZIP payload, while Dart decodes each restored `SavedBillRecord` before it can request replacement. Replacement and wipe use database transactions. Dark Mode state belongs to `MyApp`; Android private preferences persist it separately from saved bills and ZIP archives.

Android storage failures return a platform-channel error; Dart does not interpret read failures as an empty database. Settings reports operation failures without claiming success, and a failed native replacement rolls back its transaction. Record decoding rejects unsupported schemas and inconsistent snapshots rather than accepting malformed data.

## Source and Test Map

| Path | Coverage |
| --- | --- |
| `test/calculation/` | Pure-Dart allocation, rounding, reconciliation, and optional private regression fixture |
| `test/workflow/` | Draft parsing/validation, billing-period helpers, and date-range controls |
| `test/storage/bill_repository_test.dart` | Repository save, conflict, movement, replacement, wipe, and integrity behavior |
| `test/widget_test.dart` | Home, workflow navigation, validation, calculation/result UI, storage-channel flows, and layout |
| `test/history/` | Category/year selection, graph/list state, and read-only saved details |
| `test/sharing/` | Reusable card content, full-card PNG output, and share-channel orchestration |
| `test/app/settings_screen_test.dart` | Settings backup/restore document-channel flows, confirmations, draft reset, wipe, and preference failures |

Automated repository and platform-channel tests do not establish physical-device behavior. Report Android hardware checks separately.

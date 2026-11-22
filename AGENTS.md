# Basic Bill Splitter — Development Instructions

## Project Scope

Basic Bill Splitter is an offline-first Flutter and Dart Android app for calculating one shared residential bill at a time. Completed calculations can be saved locally on Android. Draft inputs remain in memory and are not restored after process termination.

Android is the primary platform. Do not add platform targets, network access, permissions, or dependencies without a justified requirement and any approval required by this file. Keep the app's identity, branding, and existing behavior unless the approved task calls for a change.

Read `README.md`, `pubspec.yaml`, relevant source and tests, and the technical references before changing behavior. Inspect the current repository and working tree; do not assume prior reports describe current state.

## Core Engineering Rules

- Prioritize correctness, reliability, maintainability, simplicity, performance, and usability.
- Make the smallest coherent change that satisfies the approved requirement.
- Preserve offline calculation behavior and existing user work. Treat uncommitted changes and branding assets as protected.
- Keep business rules separate from Flutter presentation and Android infrastructure.
- Reuse the existing code and dependencies. Do not add speculative abstractions, unrelated refactors, or unapproved dependencies.
- Do not broaden the task or introduce proposed functionality as if it already exists.

## Architecture and Calculation Authority

- Use the pure-Dart `BillCalculator` as the single authority for allocation. Never duplicate allocation formulas in widgets or presentation code.
- Keep typed calculation inputs and immutable result collections; validate at calculation boundaries as well as in forms.
- Keep parsing and draft validation separate from rendering.
- Preserve saved calculation snapshots as historical results; do not recalculate old records when calculation code changes.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the current component map, data flow, and Flutter/Android boundary. See [docs/DATA_STORAGE.md](docs/DATA_STORAGE.md) for the implemented record format, persistence behavior, and billing-date rules.

## Product and Calculation Invariants

The six bill categories and defaults are Electricity and Water (Hybrid), Internet, Rent and LPG (Person-days), and Miscellaneous (Equal per household). Users can choose another supported method for the current bill.

- Hybrid charges measured usage and distributes residual usage by person-days among **all participating occupants, including metered occupants**.
- Person-days weights occupants by occupancy duration and aggregates contributions by household.
- Equal per household defines household totals only; never invent individual monetary allocations.
- Preserve integer-cent money, exact intermediate arithmetic, deterministic largest-remainder rounding, and input-order tie breaks. Household totals must reconcile to the bill; occupant totals must reconcile to household totals where individual allocations exist.
- Preserve validation of nonnegative bill amounts (including zero), consumption, positive occupancy days, participating households and occupants, denominators, and excess measured usage.
- Preserve inclusive billing and occupancy date semantics. Manual durations must fit the period; occupancy ranges must be within it and non-overlapping for the same occupant, including shared endpoints.
- The headcount UI is a 0–10 stepper with default 1; validation requires 1–10 occupants per participating household. This is a UI limit, not a calculation-engine limit.
- Preserve draft inputs while navigating and while a headcount is reduced then increased, unless an explicit Clear action resets them.
- Preserve two-decimal display formatting for money and continuous quantities without feeding rounded display text back into calculations.

## Validation, Security, and Data Integrity

- Parse PHP amounts directly into integer cents; do not pass money through floating-point conversion.
- Reject malformed, negative, nonfinite, or out-of-range inputs explicitly. Never silently substitute, drop participants, clamp excessive usage, lose cents, overflow, or allow nondeterministic results.
- Keep credentials and personal data out of source control. Do not request unnecessary permissions or network access.
- Dispose controllers and other resources reliably, including on error paths. Handle platform and storage errors explicitly.
- Keep persistence app-private. Preserve schema versioning, explicit migration paths, transactional writes, uniqueness enforcement, and recovery safeguards. Never silently delete or rebuild an unreadable database.
- Do not delete protected files, private fixtures, or user data. Destructive operations and changes to real data require explicit authorization. Keep test data isolated.

## Testing and Verification

Use the existing Flutter/Dart test framework and configured analysis rules. Add focused regression tests for behavior changes and failure paths; do not remove or weaken valid assertions to make checks pass. Test calculation boundaries, exact reconciliation, navigation, validation, storage behavior, and relevant layouts as applicable.

Standard project checks are:

```text
dart format lib test
flutter analyze
flutter test
```

Run proportionate focused checks during development and the full applicable suite before reporting completion. Run an Android build or native verification when the change affects those layers. Documentation-only edits need document review and `git diff --check`, not Flutter tests solely because Markdown changed. Report exact commands and results, including failures, skips, unavailable checks, and physical-device verification separately from automated tests. Historical results are not proof of current behavior.

## Repository Workflow and Authorization

Before editing, inspect the branch, HEAD, status, relevant source, tests, and documentation. Preserve unrelated work. After editing, review the complete diff and report changed files, verification, limitations, and final Git status.

Do not stage or commit, push, merge, rebase, reset, discard changes, create tags/releases, publish artifacts, deploy, install on a device, or alter real user data without explicit authorization. Source inspection and editing authorization do not grant those permissions. Do not invent features or widen scope; clarify material uncertainty before making a consequential assumption.

## Documentation

Keep documentation synchronized with actual behavior. Use `README.md` as the user guide, this file for binding development instructions, [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for component responsibilities and data flow, and [docs/DATA_STORAGE.md](docs/DATA_STORAGE.md) for persistence and billing-date behavior.

Distinguish implemented, proposed, partially implemented, and unverified functionality. Preserve historical dates, versions, identifiers, test counts, technical decisions, and verification provenance. Update existing documentation with targeted edits; do not create redundant status documents.

## GitHub Writing Standards

Apply these standards to repository documentation, issues, comments, pull requests, commit messages, release text, and progress reports:

- Write directly in an authentic developer voice. Describe changes and evidence without third-person coordination phrases.
- Keep agent names, internal coordination details, handover numbers, and session identifiers out of repository-facing prose.
- Distinguish executed tests, reported manual tests, independent verification, historical results, and pending checks. Never invent results, approvals, or implementation history.
- Do not silently alter versions, dates, commit IDs, checksums, counts, limitations, or historical decisions.
- Prefer targeted, technically accurate edits over unrelated stylistic rewrites.

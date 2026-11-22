# AGENTS.md — Basic Bill Splitter Development Guidelines

## 1. Project Overview

Basic Bill Splitter is an Android application built with Flutter and Dart,
developed using Android Studio. It calculates residential shared expenses one
bill at a time without requiring saved property or occupant profiles.

- Android is the primary target; do not add platform targets without justification
  and approval.
- Core calculations work offline without accounts or a network connection.
- A pure-Dart engine provides typed inputs, validation, and allocation results.
- The Material 3 interface keeps one in-memory calculation draft across Bill
  Details, Households, Usage & Duration, Review, and Results.

Read `README.md`, `pubspec.yaml`, and relevant source and tests before changing
behavior. Inspect the current repository rather than assuming an earlier
description still reflects its state.

## 2. Core Development Principles

- Favor correctness, reliability, maintainability, and simplicity.
- Preserve the straightforward calculation workflow and offline operation.
- Keep business rules independent of Flutter widgets.
- Reuse existing code and dependencies; avoid speculative abstractions.
- Make the smallest coherent change that satisfies the approved requirement.
- Preserve existing calculation behavior unless a requirement explicitly changes it.
- Do not silently add features, expand scope, refactor unrelated code, or modify
  unrelated files.
- Treat existing modifications and branding assets as protected work.

## 3. Architecture

Current responsibilities:

| Location | Responsibility |
| --- | --- |
| `lib/main.dart` | App startup, Material 3 theme, and workflow entry point |
| `lib/calculation/bill_models.dart` | Typed bill, household, occupant, and allocation models |
| `lib/calculation/bill_calculator.dart` | Pure-Dart validation, allocation, and cent reconciliation |
| `lib/workflow/bill_draft.dart` | Transient inputs, category defaults, parsing, and form/date validation |
| `lib/workflow/bill_workflow.dart` | Step-based interface, navigation, field errors, save flow, and result presentation |
| `lib/storage/` | Versioned saved-bill records, assigned-month rules, and repository interface |
| `android/.../SavedBillDatabase.kt` | App-private SQLite schema, transactional writes, and category/month uniqueness |
| `test/calculation/` | Calculation unit and regression tests |
| `test/workflow/` | Draft parsing and validation tests |
| `test/widget_test.dart` | Form, navigation, layout, and calculation integration tests |
| `android/` | Native Android project and configuration |

- Use `BillCalculator` as the computation foundation. Never duplicate allocation
  formulas in widgets or presentation helpers.
- Keep typed input and result models, including immutable result collections.
- Validate at calculation boundaries as well as in forms; UI validation alone is
  insufficient.
- Keep parsing and draft rules separate from rendering. Avoid growing startup or
  workflow code into a monolithic application module.
- Follow existing conventions and the dependencies configured in `pubspec.yaml`,
  including `material_ui`. New dependencies require separate approval.

## 4. Product and Calculation Rules

Each calculation concerns one expense. The six fixed categories and defaults are:

| Category | Default allocation |
| --- | --- |
| Electricity | Hybrid measured consumption + person-days |
| Water | Hybrid measured consumption + person-days |
| Internet | Person-days |
| Rent | Person-days |
| LPG | Person-days |
| Miscellaneous | Equal per household |

Users may override the allocation method for the current bill.

- Measurements belong to individual occupants and use the bill's consumption unit.
- Hybrid determines the unit rate from the bill amount and total consumption,
  subtracts specified measured usage, and distributes residual consumption among
  **all participating occupants** by person-days, including metered occupants.
  Never restore the legacy rule that excluded metered occupants.
- Person-days weights each occupant by occupancy duration. For hybrid and
  person-days, aggregate occupant contributions into household shares.
- Preserve integer-cent amounts and deterministic largest-remainder rounding.
  Household totals must equal the original bill. For hybrid and person-days,
  reconcile household cents first, then occupant cents within each household;
  occupant totals must equal household totals. Break rounding ties by input order.
- Equal-per-household defines household totals only. Show occupant inputs without
  inventing individual monetary allocations.
- Accept nonnegative bill amounts, including zero. Hybrid requires positive total
  consumption; measurements cannot exceed a supplied total.
- Require participating households and occupants, positive integer occupancy days,
  and valid allocation denominators.
- Preserve inclusive billing-period and occupancy-range counts. Manual days must
  fit the period length; ranges must lie within the period and cannot overlap
  for the same occupant, including shared endpoints.
- Preserve draft inputs when navigating backward. The current form allows 1–100
  occupants per household; this is a UI guard, not an engine limit.

The engine and five-step calculation interface are implemented. Drafts are not
restored after process termination. Completed calculations can be saved in the
versioned app-private SQLite database and are unique by category and majority-
covered assigned month. Saved household or occupant profiles, membership
management, payment tracking, revision histories, History UI, backups, exports,
and itemized billing are not implemented; do not treat proposals as existing
functionality or introduce them without separately approved scope.

## 5. Reliability and Security

- Validate monetary and numerical inputs. Parse PHP amounts directly into integer
  cents rather than through floating-point money.
- Reject NaN, infinity, negative consumption, malformed inputs, and invalid
  durations. Handle errors explicitly without silently substituting values,
  dropping participants, or clamping excessive measured usage.
- Prevent over-allocation, lost cents, overflow, and nondeterministic results.
  Preserve the engine's exact intermediate arithmetic and supported input bounds.
- Keep credentials and personal data out of source control; never hardcode secrets.
- Request no unnecessary Android permissions or network access.
- Dispose controllers and other resources reliably, including on error paths.
- Do not perform destructive operations or alter real user data without explicit
  authorization. Keep test data isolated from real data.
- Preserve saved-bill validation, schema versioning, explicit migrations,
  transactional replacement, and recovery safeguards when changing persistence.
  Never silently delete or rebuild an unreadable saved-bill database.

## 6. Testing

Use the existing `flutter_test` framework and configured analysis rules. Standard
verification from the repository root is:

```text
dart format lib test
flutter analyze
flutter test
```

- Add unit tests for calculation rules and regression tests for calculation changes.
- Add widget tests for relevant forms, navigation, validation, and result behavior.
- Cover boundaries, invalid inputs, failure paths, decimal consumption, rounding
  ties, zero usage, and exact occupant-to-household-to-bill reconciliation.
- Run focused tests during development and the full suite after meaningful code
  changes. Do not skip or weaken tests or assertions to obtain passing results.
- Test on physical Android hardware when relevant, especially keyboard/system-bar
  insets, Back behavior, date pickers, rotation, and accessibility.
- Report exact commands and actual passed, failed, skipped, or unavailable checks.
  Distinguish automated and mocked results from physical-device verification.
- Documentation-only edits need document review and `git diff --check`; Flutter
  tests are not required solely for documentation changes.

## 7. Change Workflow

Before editing:

1. Inspect the branch, Git status, relevant source, tests, and documentation.
2. Identify existing uncommitted work and preserve it.
3. Understand current behavior, the requirement, intended scope, and risks.
   Clarify uncertainty that materially affects correctness.

During editing:

1. Make focused changes using existing naming, formatting, and architecture.
2. Keep implementation, tests, and relevant documentation consistent.
3. Avoid unrelated modifications and preserve ongoing work.

After editing:

1. Review the complete diff, including new files.
2. Run appropriate verification and report actual results and limitations.
3. List changed files, their purpose, findings, unresolved issues, final Git status,
   and the recommended next action when applicable.
4. Do not claim completion while required verification remains outstanding.
5. Do not commit or push without explicit permission.

## 8. Documentation and Project Status

- Keep `README.md`, setup instructions, and relevant documentation synchronized
  with actual behavior and architecture.
- Update existing documentation rather than creating redundant status files.
  Do not assume progress reports, changelogs, or other documents exist.
- Record significant architectural decisions, configuration changes, compatibility
  requirements, and known limitations where relevant.
- Distinguish implemented, partially implemented, proposed, and unverified work.
- If requirements, documentation, and implementation disagree, report the
  discrepancy rather than silently changing requirements or guessing intent.
- Treat historical test results as historical evidence, not proof of current
  behavior. Follow the writing standards below for all status reporting.

## 9. Scope and Approval

Separate explicit authorization is required for:

- Significant changes to implementation scope, product behavior, or architecture.
- Adding dependencies that have not already been approved.
- Destructive cleanup, deletion, or changes to real user data.
- Git staging, commits, pushes, merging, rebasing, resets, or discarding changes.
- Creating tags or releases and publishing build artifacts or deploying.

Inspection or editing authorization does not authorize Git mutations, deployment,
publication, or deletion. Read-only Git inspection remains part of normal work.
Do not invent features or expand product scope; explain material tradeoffs and
request clarification or approval when required.

## 10. GitHub Writing Standards

Apply these standards to README files, documentation, CHANGELOG entries, issues
and comments, pull requests and reviews, commit messages, release notes and
descriptions, and testing and progress reports.

- Write in an authentic developer voice. Describe technical changes, decisions,
  implementation, and verification directly. Avoid third-person coordination
  phrases such as "The owner requested...", "The user confirmed...", "The
  maintainer approved...", or "Codex implemented...".
- Keep internal agent names, coordination mechanics, handover numbers, and
  session identifiers out of public repository-facing prose.
- Preserve factual accuracy and verification provenance. Distinguish successfully
  executed tests, reported manual tests, independently verified results,
  historical findings, and pending or unavailable verification. Never invent
  test execution, approvals, implementation history, or firsthand development work.
- Do not silently alter version numbers, dates, commit identifiers, checksums,
  test counts, known limitations, or historical technical decisions.
- Prefer targeted edits. Do not rewrite unrelated documentation for stylistic
  uniformity or change technical requirements merely to improve prose.

These standards apply to future repository contributions.

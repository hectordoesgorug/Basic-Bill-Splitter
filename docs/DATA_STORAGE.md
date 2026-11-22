# Saved Bill Storage

## Scope and Location

Completed bill calculations are stored on Android in the app-private SQLite database `saved_bills.db`. The database uses Android's built-in SQLite APIs; Dart accesses it through the `BillRepository` abstraction and the `basic_bill_splitter/app` method channel. Reads and writes run on a native single-thread executor so SQLite work does not block Flutter's UI thread.

Working drafts are held in memory only and are not restored after process termination. There is no History interface, PNG sharing, or ZIP Backup/Restore feature.

## Schema and Record Format

The Android database schema is version 1. Its `saved_bills` table stores these record fields alongside a JSON payload:

- `id` — stable record identifier and primary key.
- `schema_version` — record payload schema.
- `category`, `assigned_year`, `assigned_month` — unique category/month key.
- `created_at`, `updated_at` — UTC ISO-8601 timestamps.
- `start_date`, `end_date` — billing dates as date-only `YYYY-MM-DD` values.
- `payload` — complete JSON encoding of the `SavedBillRecord`.

The table has a database-level unique constraint on `(category, assigned_year, assigned_month)`. Record IDs are generated independently of category, month, or household names. Updating or moving a saved record retains its ID and creation timestamp.

The record payload has schema version 1 and includes the metadata above plus a snapshot. The snapshot stores category, integer `totalAmountCents`, original billing dates, allocation method, consumption inputs, and participating households and occupants in input order. It preserves each household name, active occupant count, household cents, each occupant's measured input and occupancy mode/days/ranges, and occupant cents when defined. Equal-per-household occupant cents are `null`; no individual allocation is invented. Only active occupants included in the calculated Bill are saved; inactive entries retained in the in-memory draft are excluded.

Money and calculated allocations are serialized as integer cents. Consumption values are preserved as numeric inputs, with the original draft text retained in the snapshot as well; presentation formatting is not used to rewrite calculation inputs. Date-only values are separate from timestamps. The decoder validates schema support, category/month and date consistency, snapshot shape, and household/occupant reconciliation before returning a record. Collections exposed by the record model are immutable.

## Assigned Billing Month

A bill is assigned to the calendar month containing the greatest number of inclusive billing-period days. The helper uses UTC calendar dates, so device timezone and daylight-saving transitions do not affect classification. If two or more months tie for the greatest count, the later month wins. The assigned year and month determine the unique storage key; the amount is not prorated.

The pure-Dart helper rejects reversed periods and counts every covered calendar day inclusively, including periods crossing years, leap days, or more than two months.

## Continuity and Overlap

When Home starts a new draft, it asks the repository for the saved record in that category with the latest billing-period end date. If found, it proposes a period starting the following calendar day and ending one day before the corresponding date in the next calendar month. Each category has independent continuity. The suggestion applies only to a fresh draft whose default period has not changed while the asynchronous lookup was pending; it does not update a saved record or replace a reopened draft.

A manually confirmed billing-period range is checked against saved records in the same category. Periods overlap if they share any date, including endpoints. The warning offers Change Dates or Continue Anyway; continuing does not block calculation. The current record is excluded when editing it. Repeated checks are guarded against stale asynchronous responses and an already acknowledged unchanged range. Overlap is distinct from category/month uniqueness at Save.

## Save, Replace, and Move

The repository supports listing records, looking up a category/month record, finding the latest period for a category, finding overlaps, and saving a record. It has a platform implementation and an in-memory implementation used by tests.

Save is accepted only for a current calculated result. An unchanged saved calculation is reported as unchanged without inserting a duplicate. When another record occupies the target category/month, the UI requires confirmation before replacing it. Recalculated changes to the current saved record also require confirmation. Moving a saved record to another assigned month keeps the source ID; if the destination is occupied, replacement is confirmed before the move.

The Android save operation is synchronized and runs in one SQLite transaction. It rechecks the moving source and destination conflict inside the transaction, then inserts or updates the record and removes an authorized destination conflict as one operation. The database unique constraint remains the final uniqueness guard. A declined or failed replacement/move leaves the existing saved data intact. Results remains available after a save error so the user can retry.

Exit from Results returns to Home. An unchanged saved result exits without a prompt; an unsaved or changed result offers Save & Exit, Exit Without Saving, or Cancel. Save & Exit returns Home only after Save succeeds. Exit Without Saving discards the in-memory work but does not delete or revert saved records.

## Failure Handling, Migration, and Privacy

A database read/write failure is surfaced as a platform-channel storage error. The app does not treat a failed read as an empty database. Record decoding reports malformed or unsupported payloads rather than silently accepting them. SQLite corruption is configured to fail explicitly; there is no automatic database deletion or rebuild.

The Android database version is 1. The current upgrade handler has no migration path and fails explicitly if a different database version is encountered. Any future schema change must add and verify an explicit migration before it is released; it must not silently drop or recreate saved data.

The database resides in app-private storage. Android backup is disabled for the app, and backup and device-transfer rules exclude the database and its journal/WAL files. No storage or network permission is requested for saving bills. This protection does not provide user-facing backup or restore; those features remain out of scope.

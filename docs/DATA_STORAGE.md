# Saved Bill Storage

## Scope and Location

Completed bill calculations are stored on Android in the app-private SQLite database `saved_bills.db`. The database uses Android's built-in SQLite APIs; Dart accesses it through the `BillRepository` abstraction and the `basic_bill_splitter/app` method channel. Reads and writes run on a native single-thread executor so SQLite work does not block Flutter's UI thread.

Working drafts are held in memory only and are not restored after process termination. History reads saved snapshots through the repository. PNG sharing creates temporary cache files outside the database. Manual ZIP Backup and full-replacement Restore use Android's Storage Access Framework; backups contain saved bills only and are not encrypted.

## Schema and Record Format

The Android database schema is version 1. Its `saved_bills` table stores these record fields alongside a JSON payload:

- `id` — stable record identifier and primary key.
- `schema_version` — record payload schema.
- `category`, `assigned_year`, `assigned_month` — unique category/month key.
- `created_at`, `updated_at` — UTC ISO-8601 timestamps.
- `start_date`, `end_date` — billing dates as date-only `YYYY-MM-DD` values.
- `payload` — complete JSON encoding of the `SavedBillRecord`.

The table has a database-level unique constraint on `(category, assigned_year, assigned_month)`. Record IDs are generated independently of category, month, or household names. Updating or moving a saved record retains its ID and creation timestamp.

The record payload has schema version 1 and includes the metadata above plus a snapshot and an optional top-level `currencyCode`. Missing currency metadata in older v1 records means PHP; new records write one of the 20 supported codes. Unsupported codes are rejected. The optional field keeps schema-v1 backups readable without a SQLite migration. The snapshot stores category, integer `totalAmountCents`, original billing dates, allocation method, consumption inputs, and participating households and occupants in input order. It preserves each household name, active occupant count, household cents, each occupant's measured input and occupancy mode/days/ranges, and occupant cents when defined. Equal-per-household occupant cents are `null`; no individual allocation is invented. Only active occupants included in the calculated Bill are saved; inactive entries retained in the in-memory draft are excluded.

Money and calculated allocations are serialized as integer cents. Currency is a display denomination, not an exchange-rate conversion; saved records retain their own code when the Settings preference changes. Backups preserve this optional field, and records without it remain PHP. Consumption values are preserved as numeric inputs, with the original draft text retained in the snapshot as well; presentation formatting is not used to rewrite calculation inputs. Date-only values are separate from timestamps. The decoder validates schema support, category/month and date consistency, snapshot shape, and household/occupant reconciliation before returning a record. Collections exposed by the record model are immutable.

## Assigned Billing Month

A bill is assigned to the calendar month containing the greatest number of inclusive billing-period days. The helper uses UTC calendar dates, so device timezone and daylight-saving transitions do not affect classification. If two or more months tie for the greatest count, the later month wins. The assigned year and month determine the unique storage key; the amount is not prorated.

The pure-Dart helper rejects reversed periods and counts every covered calendar day inclusively, including periods crossing years, leap days, or more than two months.

## Continuity and Overlap

When Home starts a new draft, it asks the repository for the saved record in that category with the latest billing-period end date. If found, it proposes a period starting the following calendar day and ending one day before the corresponding date in the next calendar month. Each category has independent continuity. The suggestion applies only to a fresh draft whose default period has not changed while the asynchronous lookup was pending; it does not update a saved record or replace a reopened draft.

A manually confirmed billing-period range is checked against saved records in the same category. Periods overlap if they share any date, including endpoints. The warning offers Change Dates or Continue Anyway; continuing does not block calculation. The current record is excluded when editing it. Repeated checks are guarded against stale asynchronous responses and an already acknowledged unchanged range. Overlap is distinct from category/month uniqueness at Save.

## Save, Replace, and Move

The repository supports listing records, looking up a category/month record, finding the latest period for a category, finding overlaps, saving a record, and deleting a single record by stable ID with an expected update timestamp. It has a platform implementation and an in-memory implementation used by tests.

Save is accepted only for a current calculated result. An unchanged saved calculation is reported as unchanged without inserting a duplicate. When another record occupies the target category/month, the UI requires confirmation before replacing it. Recalculated changes to the current saved record also require confirmation. Moving a saved record to another assigned month keeps the source ID; if the destination is occupied, replacement is confirmed before the move.

The Android save operation is synchronized and runs in one SQLite transaction. It rechecks the moving source and destination conflict inside the transaction, then inserts or updates the record and removes an authorized destination conflict as one operation. The database unique constraint remains the final uniqueness guard. A declined or failed replacement/move leaves the existing saved data intact. Results remains available after a save error so the user can retry.

Exit from Results returns to Home. An unchanged saved result exits without a prompt; an unsaved or changed result offers Save & Exit, Exit Without Saving, or Cancel. Save & Exit returns Home only after Save succeeds. Exit Without Saving discards the in-memory work but does not delete or revert saved records.

## ZIP Backup and Restore

Settings exports the saved-record collection through Android's Storage Access Framework. The user chooses the destination with `ACTION_CREATE_DOCUMENT`; the app does not select an external path or request broad storage access. Restore uses `ACTION_OPEN_DOCUMENT`. Both operations run offline and keep the database inside app-private storage.

Format version 1 is a ZIP with exactly two UTF-8 entries: `manifest.json` and `bills.json`. The manifest records the format version, application ID, UTC creation timestamp, saved-record schema version, record count, and SHA-256 checksum of the exact `bills.json` bytes. The payload is the complete encoded `SavedBillRecord` list. Records are sorted by category, assigned year/month, then ID for deterministic output; IDs, timestamps, input snapshots, ordering, and integer-cent results are retained. Empty collections are supported. Drafts, preferences, database journals, PNG cache files, and unrelated app files are excluded.

Restore first checks the ZIP entry names and count, compressed-stream limits, manifest versions and fields, checksum, and record count in the Android layer. It then decodes every record through `SavedBillRecord` in Dart and rejects unsupported schemas, malformed snapshots, duplicate IDs, or duplicate category/month keys before showing destructive confirmation. The confirmation explains full replacement and includes the saved-record counts; if a draft is active, it explains that success will discard it too. No merge is performed.

The native replacement validates the incoming rows, then deletes and inserts all records inside one SQLite transaction. It checks the resulting record count and unique IDs/category/month keys before committing; exceptions roll the transaction back. After readback is compared with the validated input, Settings clears the active draft and returns Home. A failed replacement leaves existing saved rows intact. Single-record History deletion verifies the selected ID and expected update timestamp inside a SQLite transaction, then deletes only that row; a missing or changed record is retained and triggers a refresh. Wipe Data is a separate transactional row deletion and does not remove the database, preferences, or share cache. Clear All affects only the current in-memory draft and never deletes saved bills.

Archive processing is bounded to 40 MiB total input, 64 KiB for the manifest, 32 MiB for bill payload data, and 5,000 records. Only the two expected file entries are accepted; duplicate, directory, and unexpected entries are rejected. Backups are not encrypted and may contain household and billing information. Store exported ZIPs securely. The app does not upload backups or make hidden extra copies.

## Currency Display

The root application stores the selected currency code in Android app-private preferences, with PHP as the default. The formatter always uses integer cents and two fractional digits; changing the preference changes the displayed denomination for current/new unsaved calculations only. No amount is converted. Historical records keep their saved currency, including in History lists, graphs, Details, Computation, and PNG cards. Legacy v1 records with no currency field are interpreted as PHP.

Annual graphs plot stored numeric amounts without conversion. A single-currency year labels its axis with that currency; a mixed-currency year uses a neutral numeric axis, includes each bill's currency, and states that values are not converted. Such cross-currency comparisons are not financially equivalent.

## Appearance Preferences

Dark Mode is owned by the root Flutter app theme and stored separately in Android app-private `SharedPreferences`. The default is the established light theme. Turning Dark Mode on or off applies immediately; the selection is restored at startup. Preference-write failure is reported in Settings and the prior appearance is restored. Theme settings are not included in a bill backup and survive Wipe Data.

## Failure Handling, Migration, and Privacy

A database read/write failure is surfaced as a platform-channel storage error. The app does not treat a failed read as an empty database. Record decoding reports malformed or unsupported payloads rather than silently accepting them. SQLite corruption is configured to fail explicitly; there is no automatic database deletion or rebuild.

The Android database version is 1. The current upgrade handler has no migration path and fails explicitly if a different database version is encountered. Any future schema change must add and verify an explicit migration before it is released; it must not silently drop or recreate saved data.

The database and appearance preferences reside in app-private storage. Android automatic backup and device-transfer are disabled for app data, including the database and journal/WAL files. The Storage Access Framework grants access only to the user-selected ZIP document; no broad storage or network permission is requested. This does not encrypt an exported backup.

## PNG Sharing

Sharing renders a PNG in Flutter from the current calculated result or the stored historical snapshot; it does not save, update, or recalculate a bill. Android validates the PNG signature and enforces a 32 MiB payload limit, writes a uniquely named temporary file under the app cache directory `bill-share/`, and shares it with an `image/png` `ACTION_SEND` chooser. The AndroidX `FileProvider` is non-exported and grants temporary read access only to that cache subdirectory through a `content://` URI. It does not expose the SQLite database or general app files. The app deletes a file if it cannot open a recipient chooser and prunes only its own `bill-*.png` files older than 24 hours before the next share. Share files are temporary and are not part of the saved-bill schema or History records.

# Basic Bill Splitter

![Basic Bill Splitter — Simple, exact shared-bill calculation](assets/banner.png)

A Material 3 Flutter app for splitting one residential bill at a time. The
interface uses the pure-Dart calculation engine and keeps a single in-memory
draft while navigating between steps.

## Calculation workflow

1. **Bill Details** — select a category and allocation method, enter the PHP
   amount and inclusive billing period, and supply total consumption for hybrid.
2. **Households** — enter household names and participating occupant headcounts.
   The form accepts 1–100 occupants per household to guard against accidental
   generation of thousands of fields. This is a UI limit, not an engine limit.
3. **Usage & Duration** — optionally enter each occupant's measured usage.
   Select manual days, Full Period, or one or more occupancy date ranges.
   Manual days must be within the bill period's length. Date ranges must lie
   within the bill period and must not overlap for the same occupant; both
   endpoints count, so sharing an endpoint is an overlap.
4. **Review** — inspect the bill, household and occupant inputs.
5. **Results** — view PHP household totals and, for hybrid/person-days,
   reconciled occupant amounts. Equal-per-household shows occupant inputs
   without assigning individual monetary shares.

Category defaults are Electricity and Water → hybrid; Internet, Rent and LPG →
person-days; Miscellaneous → equal per household. Selecting a category applies
its default. The method can then be overridden for this bill. Measured inputs
do not affect the two non-hybrid methods.

Amounts accept plain decimal digits with up to two decimal places (for example
`1234.56`) and convert directly to integer cents. Results use PHP formatting,
such as `₱1,234.56`. Dates accept `YYYY-MM-DD` or the calendar picker.
Field errors prevent advancing until corrected; aggregate measured usage is
validated by the engine before Review.

Back buttons and Android system Back return to the previous step and preserve
inputs. Reducing and then increasing a headcount retains the inactive occupant
entries within this draft. Household removal and starting a new calculation
require confirmation. The draft is not restored after process termination.

The entry point is `lib/main.dart`. `lib/workflow/bill_workflow.dart` renders
the steps; `lib/workflow/bill_draft.dart` owns transient inputs, parsing and
form validation. Widgets do not implement allocation formulas.

## Calculation engine

Use `lib/calculation/bill_models.dart` for immutable bill, household, occupant,
and result models, and `lib/calculation/bill_calculator.dart` for
`BillCalculator.calculate`. The engine has no Flutter or third-party imports.

Each bill supplies a nonnegative integer `totalAmountCents` and a list of
participating households. Each household contains its participating occupants;
list lengths define headcounts rather than maintaining separate counts. Every
occupant supplies positive integer `occupancyDays` and may supply a
`measuredConsumption`. These are inputs for this bill only.

Supported methods:

- `AllocationMethod.hybrid`: requires positive `totalConsumption`. The unit rate
  is the bill amount divided by total consumption. Subtract all measured usage,
  then distribute residual consumption by occupancy days across **all**
  occupants, including those with measurements. An occupant's unrounded charge
  is `rate * (measuredUsage + residualUsage * days / totalPersonDays)`, with
  missing measured usage treated as zero. Sum these charges by household.
- `AllocationMethod.personDays`: split the bill by each household's total
  occupancy days divided by all participating occupancy days.
- `AllocationMethod.equalPerHousehold`: split the bill equally among households,
  irrespective of their occupant counts or days.

The hybrid rule deliberately supersedes the owner-provided legacy
`BillSplitter.py`, which excluded metered occupants from residual allocation.

### Validation and rounding

Calculation throws `ArgumentError` for empty household/occupant lists,
nonpositive occupancy days, negative bill amounts, negative/nonfinite
consumption, or measurements whose sum exceeds a supplied total consumption.
Total consumption is optional for the two non-hybrid methods; measurements do
not affect their weights, but supplied consumption values are still validated.
Zero bills are valid. Hybrid still requires positive consumption for a valid
unit-rate denominator.

Amounts are integer cents, bounded at `2^53 - 1` for Dart web portability.
Consumption uses one consistent unit per bill (for example kWh or cubic meters)
and accepts finite nonnegative doubles. The engine interprets each supplied
double's shortest decimal string exactly, using `BigInt` intermediate weights.
Pass source decimal values directly: a precomputed `0.1 + 0.2` remains
`0.30000000000000004`, rather than being silently adjusted with a tolerance.
Days are explicit counts; date ranges, billing-period limits, and currency
formatting belong to the calling workflow.

No individual charge is rounded before household aggregation. Household shares
are floored to cents, then leftover cents go to the largest fractional
remainders; ties favor household input order. Returned allocations preserve
that order and the original household objects, so duplicate display labels
remain distinct. Household amounts always sum to the original bill.

For hybrid and person-days, each `HouseholdAllocation.occupants` contains
immutable `OccupantAllocation` results in occupant input order. Once household
cents are reconciled, the engine distributes those cents within each household
using the same exact occupant weights and largest-remainder rule, with ties
favoring occupant input order. Occupant cents sum to household cents, including
zero-usage households and bills smaller than the number of occupants.
For equal-per-household, `occupants` is null because that method defines no
individual monetary allocation.

### Example

```dart
import 'package:basic_bill_splitter/calculation/bill_calculator.dart';
import 'package:basic_bill_splitter/calculation/bill_models.dart';

final bill = Bill(
  totalAmountCents: 10000,
  totalConsumption: 100,
  households: [
    Household(
      name: 'A',
      occupants: [
        Occupant(occupancyDays: 30, measuredConsumption: 20),
      ],
    ),
    Household(name: 'B', occupants: [Occupant(occupancyDays: 10)]),
  ],
);
final result = const BillCalculator().calculate(
  bill,
  method: AllocationMethod.hybrid,
);
// A: 8000 cents; B: 2000 cents; total: 10000 cents.
```

There are no saved profiles, membership records, payments, storage, backups, or
exports. Future itemized billing and expense categories can supply separate
bill inputs without coupling calculation to the UI or persistence.

## Verification

```text
dart format lib test
flutter analyze
flutter test
```

Calculation and occupant reconciliation tests are in
`test/calculation/bill_calculator_test.dart`. Draft parsing, duration and
validation tests are in `test/workflow/bill_draft_test.dart`.
`test/widget_test.dart` covers form validation, category defaults, navigation,
engine integration, date ranges, reset confirmation and a narrow layout with
larger text.

Automated widget tests do not establish physical-device keyboard, system-bar,
rotation, or accessibility behavior. Device checks should be reported
separately from the automated suite.

## Getting Started

Install the Flutter SDK, resolve dependencies with `flutter pub get`, then run
`flutter run` on a connected Android device.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

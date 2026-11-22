import 'package:basic_bill_splitter/workflow/bill_draft.dart';
import 'package:basic_bill_splitter/storage/billing_period.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DateTime d(String value) => parseDate(value)!;

  test('assigns periods to the month with most covered days', () {
    expect(
      assignBillingMonth(d('2026-10-23'), d('2026-11-22')),
      const AssignedMonth(2026, 11),
    );
    expect(
      assignBillingMonth(d('2026-10-01'), d('2026-10-31')),
      const AssignedMonth(2026, 10),
    );
    expect(
      assignBillingMonth(d('2026-10-08'), d('2026-11-07')),
      const AssignedMonth(2026, 10),
    );
    expect(
      assignBillingMonth(d('2026-04-16'), d('2026-05-15')),
      const AssignedMonth(2026, 5),
    );
  });

  test('ties go to the later calendar month across year boundaries', () {
    expect(
      assignBillingMonth(d('2026-12-16'), d('2027-01-16')),
      const AssignedMonth(2027, 1),
    );
  });

  test('handles leap February and periods spanning multiple months', () {
    expect(
      assignBillingMonth(d('2024-02-01'), d('2024-02-29')),
      const AssignedMonth(2024, 2),
    );
    expect(
      assignBillingMonth(d('2026-01-20'), d('2026-03-10')),
      const AssignedMonth(2026, 2),
    );
    expect(
      () => assignBillingMonth(d('2026-03-01'), d('2026-02-28')),
      throwsArgumentError,
    );
  });

  test('overlap includes a shared endpoint and rejects separate ranges', () {
    expect(
      billingPeriodsOverlap(
        d('2026-10-23'),
        d('2026-11-22'),
        d('2026-11-22'),
        d('2026-12-19'),
      ),
      isTrue,
    );
    expect(
      billingPeriodsOverlap(
        d('2026-10-23'),
        d('2026-11-22'),
        d('2026-11-23'),
        d('2026-12-19'),
      ),
      isFalse,
    );
  });

  test('continues using calendar months and inclusive endpoints', () {
    expect(nextBillingPeriod(d('2026-10-23'), d('2026-11-22')), (
      d('2026-11-23'),
      d('2026-12-22'),
    ));
    expect(nextBillingPeriod(d('2026-10-01'), d('2026-10-31')), (
      d('2026-11-01'),
      d('2026-11-30'),
    ));
    expect(nextBillingPeriod(d('2026-10-08'), d('2026-11-07')), (
      d('2026-11-08'),
      d('2026-12-07'),
    ));
    expect(nextBillingPeriod(d('2026-01-01'), d('2026-01-31')), (
      d('2026-02-01'),
      d('2026-02-28'),
    ));
    expect(nextBillingPeriod(d('2024-01-01'), d('2024-01-31')), (
      d('2024-02-01'),
      d('2024-02-29'),
    ));
    expect(nextBillingPeriod(d('2026-11-30'), d('2026-12-31')), (
      d('2027-01-01'),
      d('2027-01-31'),
    ));
  });
}

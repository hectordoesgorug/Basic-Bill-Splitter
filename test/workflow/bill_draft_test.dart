import 'package:basic_bill_splitter/calculation/bill_models.dart';
import 'package:basic_bill_splitter/workflow/bill_draft.dart';
import 'package:flutter_test/flutter_test.dart';

BillDraft draft() => BillDraft(today: DateTime(2026, 11, 1))..amount = '100.00';

void main() {
  test('only entered work requires discard confirmation', () {
    final input = BillDraft(today: DateTime(2026, 11, 1));
    expect(input.hasMeaningfulInputs, isFalse);
    input.selectCategory(BillCategory.rent);
    expect(input.hasMeaningfulInputs, isFalse);
    input.amount = '0';
    expect(input.hasMeaningfulInputs, isTrue);
    input.amount = '';
    input.method = AllocationMethod.hybrid;
    expect(input.hasMeaningfulInputs, isTrue);
    input.method = input.category.defaultMethod;
    input.periodEnd = '2026-11-29';
    expect(input.hasMeaningfulInputs, isTrue);
    input.periodEnd = '2026-11-30';
    final household = input.households.single;
    household.headcount = '2';
    household.prepareOccupants();
    household.occupants[1].measured = '0';
    household.headcount = '1';
    expect(input.hasMeaningfulInputs, isTrue);
  });

  test('PHP display includes whole amounts, trailing zeros and zero cents', () {
    expect(formatPhp(700), '₱7.00');
    expect(formatPhp(750), '₱7.50');
    expect(formatPhp(0), '₱0.00');
  });

  for (final entry in <num, String>{
    0: '0.00',
    7: '7.00',
    7.5: '7.50',
    0.007: '0.01',
    0.0049: '0.00',
    0.9999: '1.00',
    12.34567: '12.35',
    1.005: '1.01',
    1e-300: '0.00',
    1e21: '1000000000000000000000.00',
  }.entries) {
    test('quantity ${entry.key} displays exactly two decimal places', () {
      expect(formatQuantity(entry.key), entry.value);
    });
  }

  test(
    'quantity formatting handles extreme finite values and negative zero',
    () {
      expect(formatQuantity(1e300), '1${''.padLeft(300, '0')}.00');
      expect(formatQuantity(-0.0), '0.00');
    },
  );

  for (final invalid in [double.nan, double.infinity, -double.infinity]) {
    test('quantity formatting rejects nonfinite value $invalid', () {
      expect(() => formatQuantity(invalid), throwsArgumentError);
    });
  }

  test('display rounding does not alter source quantity precision', () {
    final input = draft()..consumption = '3.00007';
    final occupant = input.households.single.occupants.single
      ..measured = '1.23456';
    final bill = input.toBill();
    expect(formatQuantity(bill.totalConsumption!), '3.00');
    expect(
      formatQuantity(
        bill.households.single.occupants.single.measuredConsumption!,
      ),
      '1.23',
    );
    expect(input.consumption, '3.00007');
    expect(occupant.measured, '1.23456');
    expect(bill.totalConsumption, 3.00007);
    expect(
      bill.households.single.occupants.single.measuredConsumption,
      1.23456,
    );
  });

  test('six categories select specified default methods', () {
    final input = draft();
    expect(BillCategory.values, hasLength(6));
    for (final category in BillCategory.values) {
      input.selectCategory(category);
      expect(input.method, category.defaultMethod);
    }
    expect(BillCategory.electricity.defaultMethod, AllocationMethod.hybrid);
    expect(BillCategory.water.defaultMethod, AllocationMethod.hybrid);
    for (final category in [
      BillCategory.internet,
      BillCategory.rent,
      BillCategory.lpg,
    ]) {
      expect(category.defaultMethod, AllocationMethod.personDays);
    }
    expect(
      BillCategory.miscellaneous.defaultMethod,
      AllocationMethod.equalPerHousehold,
    );
    input.method = AllocationMethod.hybrid;
    expect(draft().method, AllocationMethod.hybrid);
  });

  test('PHP parsing and formatting are exact to the cent', () {
    expect(parsePhpCents('0.29'), 29);
    expect(parsePhpCents(' 0001.1 '), 110);
    expect(parsePhpCents('90071992547409.91'), 9007199254740991);
    expect(parsePhpCents('0'), 0);
    expect(formatPhp(123456789), '₱1,234,567.89');
    expect(formatPhp(1), '₱0.01');
    expect(formatPhp(9007199254740991), '₱90,071,992,547,409.91');
    for (final invalid in [
      '',
      '-1',
      '1.001',
      '1e2',
      'NaN',
      'Infinity',
      '1,000',
      '1.',
      '.50',
      '90071992547409.92',
    ]) {
      expect(parsePhpCents(invalid), isNull, reason: invalid);
    }
  });

  test(
    'dates are strict and inclusive across leap days and year boundaries',
    () {
      expect(parseDate('2026-02-29'), isNull);
      expect(parseDate('2024-02-29'), isNotNull);
      expect(parseDate('2026-13-01'), isNull);
      expect(parseDate('0000-01-01'), isNull);
      expect(parseDate('2026-1-01'), isNull);
      expect(inclusiveDays(DateTime(2024, 2, 28), DateTime(2024, 3, 1)), 3);
      expect(inclusiveDays(DateTime(2026, 12, 31), DateTime(2027, 1, 1)), 2);
      expect(inclusiveDays(DateTime(2026, 1, 1), DateTime(2026, 1, 1)), 1);
    },
  );

  test('validates amount, ordered period and hybrid total consumption', () {
    final input = draft();
    expect(input.validateDetails(), contains('consumption'));
    input.consumption = '100';
    expect(input.validateDetails(), isEmpty);
    input.periodEnd = '2026-10-31';
    expect(input.validateDetails(), contains('periodEnd'));
    input.periodStart = 'bad';
    expect(input.validateDetails(), contains('periodStart'));
    input.amount = '1.999';
    expect(input.validateDetails(), contains('amount'));
    input.method = AllocationMethod.personDays;
    expect(input.validateDetails(), isNot(contains('consumption')));
  });

  test('consumption rejects negative, nonfinite and nondecimal inputs', () {
    for (final invalid in ['-1', 'NaN', 'Infinity', '1e3', 'abc', '']) {
      expect(parseConsumption(invalid), isNull);
    }
    expect(parseConsumption('.25'), .25);
    expect(parseConsumption('0'), 0);
  });

  test('headcounts validate and inactive occupant entries are retained', () {
    final input = draft();
    final household = input.households.single;
    for (final invalid in ['0', '-1', '1.5', '101', 'abc']) {
      household.headcount = invalid;
      expect(input.validateHouseholds(), contains('h0.headcount'));
    }
    household.name = ' ';
    expect(input.validateHouseholds(), contains('h0.name'));
    household.name = 'A';
    household.headcount = '2';
    household.prepareOccupants();
    household.occupants[1].measured = '20';
    household.headcount = '1';
    household.prepareOccupants();
    household.headcount = '2';
    household.prepareOccupants();
    expect(household.occupants[1].measured, '20');
  });

  test('manual and full-period counts respect the bill period', () {
    final input = draft();
    final occupant = input.households.single.occupants.single;
    expect(input.occupancyDays(occupant), 30);
    occupant.mode = OccupancyMode.manualDays;
    for (final invalid in ['0', '-1', '31', '1.5', '']) {
      occupant.days = invalid;
      expect(input.validateUsage(), contains('h0.o0.days'));
    }
    occupant.days = '30';
    expect(input.validateUsage(), isEmpty);
    expect(input.occupancyDays(occupant), 30);
    input.periodEnd = '2026-11-20';
    expect(input.validateUsage(), contains('h0.o0.days'));
    occupant.mode = OccupancyMode.fullPeriod;
    expect(input.occupancyDays(occupant), 20);
  });

  test(
    'unsorted non-overlapping ranges are inclusive and allow adjacent dates',
    () {
      final input = draft();
      final occupant = input.households.single.occupants.single;
      occupant.mode = OccupancyMode.dateRanges;
      occupant.ranges
        ..clear()
        ..addAll([
          OccupancyRangeDraft(start: '2026-11-03', end: '2026-11-05'),
          OccupancyRangeDraft(start: '2026-11-01', end: '2026-11-02'),
          OccupancyRangeDraft(start: '2026-11-10', end: '2026-11-10'),
        ]);
      expect(input.validateUsage(), isEmpty);
      expect(input.occupancyDays(occupant), 6);
    },
  );

  test(
    'ranges reject overlap, shared endpoints, reversed and outside dates',
    () {
      final input = draft();
      final occupant = input.households.single.occupants.single;
      occupant.mode = OccupancyMode.dateRanges;
      occupant.ranges
        ..clear()
        ..addAll([
          OccupancyRangeDraft(start: '2026-11-01', end: '2026-11-05'),
          OccupancyRangeDraft(start: '2026-11-05', end: '2026-11-06'),
        ]);
      expect(input.validateUsage(), contains('h0.o0.r1.start'));
      occupant.ranges[1].start = '2026-11-03';
      expect(input.validateUsage(), contains('h0.o0.r1.start'));
      occupant.ranges[1].start = '2026-11-07';
      expect(input.validateUsage(), contains('h0.o0.r1.end'));
      occupant.ranges[1]
        ..start = '2026-10-31'
        ..end = '2026-12-01';
      expect(
        input.validateUsage().keys,
        containsAll(['h0.o0.r1.start', 'h0.o0.r1.end']),
      );
    },
  );

  test(
    'draft converts only active occupants and preserves measured inputs',
    () {
      final input = draft()..consumption = '0.3';
      final household = input.households.single;
      household.headcount = '2';
      household.prepareOccupants();
      household.occupants[0].measured = '0.1';
      household.occupants[1].measured = '0.2';
      final bill = input.toBill();
      expect(bill.totalAmountCents, 10000);
      expect(bill.totalConsumption, .3);
      expect(
        bill.households.single.occupants.map((o) => o.measuredConsumption),
        [.1, .2],
      );
      input.method = AllocationMethod.equalPerHousehold;
      household.headcount = '1';
      expect(input.toBill().totalConsumption, isNull);
      expect(input.toBill().households.single.occupants, hasLength(1));
      expect(household.occupants, hasLength(2));
    },
  );
}

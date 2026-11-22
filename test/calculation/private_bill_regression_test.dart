import 'dart:convert';
import 'dart:io';

import 'package:basic_bill_splitter/calculation/bill_calculator.dart';
import 'package:basic_bill_splitter/calculation/bill_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fixture = File(
    Platform.environment['BILL_SPLITTER_PRIVATE_FIXTURE'] ??
        'test/fixtures/private/bill_regression.json',
  );

  test(
    'optional local bill fixture reconciles exactly',
    () {
      late final Bill bill;
      late final BillAllocation result;
      late final int periodDays;
      late final int expectedPersonDays;
      late final int expectedBillCents;
      late final List<int> expectedHouseholdCents;
      late final List<int> expectedOccupantCents;
      try {
        final data =
            jsonDecode(fixture.readAsStringSync()) as Map<String, dynamic>;
        periodDays = data['periodDays'] as int;
        final expected = data['expected'] as Map<String, dynamic>;
        expectedPersonDays = expected['personDays'] as int;
        expectedBillCents = expected['totalAmountCents'] as int;
        expectedHouseholdCents = (expected['householdCents'] as List)
            .cast<int>()
            .toList();
        expectedOccupantCents = (expected['occupantCents'] as List)
            .cast<int>()
            .toList();
        bill = Bill(
          totalAmountCents: data['totalAmountCents'] as int,
          totalConsumption: (data['totalConsumption'] as num?)?.toDouble(),
          households: [
            for (final household in data['households'] as List)
              Household(
                name: household['name'] as String,
                occupants: [
                  for (final occupant in household['occupants'] as List)
                    Occupant(
                      occupancyDays: occupant['occupancyDays'] as int,
                      measuredConsumption:
                          (occupant['measuredConsumption'] as num?)?.toDouble(),
                    ),
                ],
              ),
          ],
        );
        result = const BillCalculator().calculate(
          bill,
          method: AllocationMethod.values.byName(data['method'] as String),
        );
      } catch (_) {
        // Never include fixture contents or engine input values in test output.
        fail(
          'Could not load or calculate the private fixture. Check its local JSON schema and input validity.',
        );
      }

      final occupants = bill.households.expand(
        (household) => household.occupants,
      );
      expect(
        periodDays > 0 &&
            occupants.every(
              (occupant) =>
                  occupant.occupancyDays > 0 &&
                  occupant.occupancyDays <= periodDays,
            ),
        isTrue,
        reason: 'Occupancy durations must fit the fixture billing period.',
      );
      expect(
        occupants.fold(0, (sum, occupant) => sum + occupant.occupancyDays) ==
            expectedPersonDays,
        isTrue,
        reason: 'Person-days must match the private expectation.',
      );
      expect(
        _sameCents(
          result.households.map((household) => household.amountCents),
          expectedHouseholdCents,
        ),
        isTrue,
        reason: 'Household cents must match the private expectations.',
      );
      expect(
        _sameCents(
          result.households
              .expand(
                (household) => household.occupants ?? <OccupantAllocation>[],
              )
              .map((occupant) => occupant.amountCents),
          expectedOccupantCents,
        ),
        isTrue,
        reason: 'Occupant cents must match the private expectations.',
      );
      for (final household in result.households) {
        if (household.occupants != null) {
          expect(
            household.occupants!.fold(
                  0,
                  (sum, occupant) => sum + occupant.amountCents,
                ) ==
                household.amountCents,
            isTrue,
            reason: 'Occupant cents must reconcile to their household.',
          );
        }
      }
      expect(
        result.totalAmountCents == bill.totalAmountCents &&
            result.totalAmountCents == expectedBillCents,
        isTrue,
        reason: 'Household cents must reconcile to the original bill and private expectation.',
      );
    },
    skip: fixture.existsSync() ? false : 'Private fixture unavailable. Supply test/fixtures/private/bill_regression.json or set BILL_SPLITTER_PRIVATE_FIXTURE to a local JSON file.',
  );
}

bool _sameCents(Iterable<int> actual, List<int> expected) {
  final values = actual.toList();
  return values.length == expected.length &&
      values.indexed.every((entry) => entry.$2 == expected[entry.$1]);
}

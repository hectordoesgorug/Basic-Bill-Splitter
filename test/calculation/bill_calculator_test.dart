import 'package:basic_bill_splitter/calculation/bill_calculator.dart';
import 'package:basic_bill_splitter/calculation/bill_models.dart';
import 'package:flutter_test/flutter_test.dart';

const calculator = BillCalculator();

Household home(List<Occupant> occupants, {String name = 'Home'}) =>
    Household(name: name, occupants: occupants);

Occupant person(int days, [double? measured]) =>
    Occupant(occupancyDays: days, measuredConsumption: measured);

Bill bill(
  List<Household> households, {
  int cents = 10000,
  double? consumption,
}) => Bill(
  totalAmountCents: cents,
  totalConsumption: consumption,
  households: households,
);

List<int> amounts(Bill input, AllocationMethod method) => calculator
    .calculate(input, method: method)
    .households
    .map((allocation) => allocation.amountCents)
    .toList();

void main() {
  group('hybrid', () {
    test('metered occupants also receive residual person-days usage', () {
      final input = bill([
        home([person(30, 20)]),
        home([person(10)]),
      ], consumption: 100);
      // Rate = 100 / 100 = 1; residual = 80; shares = 20+60 and 20.
      expect(amounts(input, AllocationMethod.hybrid), [8000, 2000]);
    });

    test('aggregates mixed occupants within each household', () {
      final input = bill(
        [
          home([person(30, 20), person(10)]),
          home([person(20)]),
        ],
        consumption: 100,
        cents: 100000,
      );
      expect(amounts(input, AllocationMethod.hybrid), [73333, 26667]);
    });

    test('all metered occupants still share remaining consumption', () {
      final input = bill([
        home([person(30, 20)]),
        home([person(10, 30)]),
      ], consumption: 100);
      expect(amounts(input, AllocationMethod.hybrid), [5750, 4250]);
    });

    test('fully measured consumption leaves no residual', () {
      final input = bill([
        home([person(1, 20)]),
        home([person(100, 80)]),
      ], consumption: 100);
      expect(amounts(input, AllocationMethod.hybrid), [2000, 8000]);
    });

    test('without measurements it matches person-days', () {
      final input = bill(
        [
          home([person(3), person(1)]),
          home([person(2)]),
        ],
        consumption: 70,
        cents: 101,
      );
      expect(
        amounts(input, AllocationMethod.hybrid),
        amounts(input, AllocationMethod.personDays),
      );
      expect(amounts(input, AllocationMethod.hybrid), [67, 34]);
    });

    test('explicit zero measurements behave like unmeasured usage', () {
      final input = bill([
        home([person(1, 0)]),
        home([person(1)]),
      ], consumption: 1);
      expect(amounts(input, AllocationMethod.hybrid), [5000, 5000]);
    });

    test('decimal measurements sum exactly without binary floating drift', () {
      final input = bill(
        [
          home([person(1, 0.1)]),
          home([person(1, 0.2)]),
        ],
        consumption: 0.3,
        cents: 100,
      );
      expect(amounts(input, AllocationMethod.hybrid), [33, 67]);
    });

    test('supports scientific notation and extreme finite consumption', () {
      for (final total in [1e-300, 1e300]) {
        final input = bill([
          home([person(1, total / 2)]),
          home([person(1)]),
        ], consumption: total);
        expect(amounts(input, AllocationMethod.hybrid), [7500, 2500]);
      }
    });

    test('combines tiny and large values without intermediate overflow', () {
      final input = bill([
        home([person(1, 1e-300)]),
        home([person(1)]),
      ], consumption: 1e300);
      expect(amounts(input, AllocationMethod.hybrid), [5000, 5000]);
    });
  });

  group('person-days', () {
    test('weights all occupants by their individual occupancy days', () {
      final input = bill([
        home([person(30), person(15)]),
        home([person(15)]),
      ]);
      expect(amounts(input, AllocationMethod.personDays), [7500, 2500]);
    });

    test('does not use measured consumption as an allocation weight', () {
      final input = bill([
        home([person(1, 90)]),
        home([person(3, 10)]),
      ], consumption: 100);
      expect(amounts(input, AllocationMethod.personDays), [2500, 7500]);
    });

    test('does not require total consumption', () {
      expect(
        amounts(
          bill([
            home([person(1)]),
          ]),
          AllocationMethod.personDays,
        ),
        [10000],
      );
    });
  });

  group('equal per household', () {
    test('ignores differences in headcount, days and measured usage', () {
      final input = bill([
        home([person(1, 90)]),
        home([person(30), person(30), person(30)]),
      ], consumption: 100);
      expect(amounts(input, AllocationMethod.equalPerHousehold), [5000, 5000]);
    });

    test('does not require consumption', () {
      expect(
        amounts(
          bill([
            home([person(1)]),
          ]),
          AllocationMethod.equalPerHousehold,
        ),
        [10000],
      );
    });
  });

  group('cent reconciliation', () {
    test('equal remainders favor household input order', () {
      final input = bill(
        [
          home([person(1)]),
          home([person(1)]),
          home([person(1)]),
        ],
        consumption: 10,
        cents: 100,
      );
      for (final method in AllocationMethod.values) {
        expect(amounts(input, method), [34, 33, 33]);
        expect(amounts(input, method), [34, 33, 33]);
      }
    });

    test('largest fractional remainders receive leftover cents first', () {
      final input = bill([
        home([person(1)]),
        home([person(2)]),
        home([person(3)]),
      ], cents: 5);
      expect(amounts(input, AllocationMethod.personDays), [1, 2, 2]);
    });

    test('aggregates individual shares before rounding households', () {
      final input = bill(
        [
          home([person(1), person(1)]),
          home([person(1)]),
        ],
        cents: 2,
        consumption: 3,
      );
      expect(amounts(input, AllocationMethod.personDays), [1, 1]);
      expect(amounts(input, AllocationMethod.hybrid), [1, 1]);
    });

    test('bill smaller than household count and zero bills reconcile', () {
      for (final cents in [0, 1]) {
        final input = bill(
          [
            home([person(1)]),
            home([person(1)]),
            home([person(1)]),
          ],
          consumption: 3,
          cents: cents,
        );
        for (final method in AllocationMethod.values) {
          expect(amounts(input, method), [cents, 0, 0]);
        }
      }
    });

    test('largest portable bill remains exact through multiplication', () {
      final input = bill(
        [
          home([person(1)]),
          home([person(1)]),
        ],
        consumption: 0.1,
        cents: 9007199254740991,
      );
      for (final method in AllocationMethod.values) {
        final result = calculator.calculate(input, method: method);
        expect(result.households.map((h) => h.amountCents), [
          4503599627370496,
          4503599627370495,
        ]);
        expect(result.totalAmountCents, input.totalAmountCents);
      }
    });

    test('single household receives the whole bill for each method', () {
      final input = bill(
        [
          home([person(17, 2), person(4)]),
        ],
        consumption: 11,
        cents: 12345,
      );
      for (final method in AllocationMethod.values) {
        expect(amounts(input, method), [12345]);
      }
    });

    test('many varied allocations reconcile without negative charges', () {
      for (var count = 1; count <= 10; count++) {
        for (final cents in [0, 1, 2, 19, 100, 10001]) {
          final input = bill(
            [
              for (var i = 1; i <= count; i++)
                home([person(i, i / 10), person(count + 1 - i)]),
            ],
            consumption: 100,
            cents: cents,
          );
          for (final method in AllocationMethod.values) {
            final result = calculator.calculate(input, method: method);
            expect(result.totalAmountCents, cents);
            expect(result.households.length, count);
            expect(result.households.every((h) => h.amountCents >= 0), isTrue);
          }
        }
      }
    });
  });

  group('validation', () {
    for (final method in AllocationMethod.values) {
      group(method.name, () {
        void rejects(Bill input) => expect(
          () => calculator.calculate(input, method: method),
          throwsArgumentError,
        );

        test('rejects no households', () {
          rejects(bill([], consumption: 1));
        });

        test('rejects an empty household even with other participants', () {
          rejects(
            bill([
              home([]),
              home([person(1)]),
            ], consumption: 1),
          );
        });

        for (final days in [0, -1]) {
          test('rejects occupancy days $days', () {
            rejects(
              bill([
                home([person(days)]),
              ], consumption: 1),
            );
          });
        }

        for (final cents in [-1, 9007199254740992]) {
          test('rejects bill cents $cents', () {
            rejects(
              bill(
                [
                  home([person(1)]),
                ],
                consumption: 1,
                cents: cents,
              ),
            );
          });
        }

        for (final invalid in [
          -1.0,
          double.nan,
          double.infinity,
          -double.infinity,
        ]) {
          test('rejects total consumption $invalid', () {
            rejects(
              bill([
                home([person(1)]),
              ], consumption: invalid),
            );
          });
          test('rejects measured consumption $invalid', () {
            rejects(
              bill([
                home([person(1, invalid)]),
              ], consumption: 1),
            );
          });
        }

        test('rejects sum of measurements exceeding total', () {
          rejects(
            bill([
              home([person(1, 0.2)]),
              home([person(1, 0.2)]),
            ], consumption: 0.3),
          );
        });
      });
    }

    for (final consumption in <double?>[null, 0]) {
      test('hybrid rejects a zero or missing denominator: $consumption', () {
        expect(
          () => calculator.calculate(
            bill([
              home([person(1)]),
            ], consumption: consumption),
            method: AllocationMethod.hybrid,
          ),
          throwsArgumentError,
        );
      });
    }

    test('other methods allow zero total consumption', () {
      final input = bill([
        home([person(1, 0)]),
      ], consumption: 0);
      for (final method in [
        AllocationMethod.personDays,
        AllocationMethod.equalPerHousehold,
      ]) {
        expect(amounts(input, method), [10000]);
      }
    });
  });

  group('models and results', () {
    test('snapshots input collections and exposes immutable lists', () {
      final occupants = [person(1)];
      final household = home(occupants);
      final households = [household];
      final input = bill(households);
      occupants.clear();
      households.clear();
      expect(household.occupants, hasLength(1));
      expect(input.households, hasLength(1));
      expect(() => household.occupants.clear(), throwsUnsupportedError);
      expect(() => input.households.clear(), throwsUnsupportedError);

      final result = calculator.calculate(
        input,
        method: AllocationMethod.personDays,
      );
      expect(() => result.households.clear(), throwsUnsupportedError);
      expect(result.method, AllocationMethod.personDays);
      expect(result.households.single.household, same(household));
    });

    test('duplicate display names do not overwrite household charges', () {
      final input = bill([
        home([person(1)], name: 'Same'),
        home([person(3)], name: 'Same'),
      ]);
      expect(amounts(input, AllocationMethod.personDays), [2500, 7500]);
    });
  });
}

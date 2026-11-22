import 'bill_models.dart';

/// Stateless calculation, independent of Flutter, storage, and presentation.
class BillCalculator {
  const BillCalculator();

  /// Allocates the original cents using largest remainders at household level.
  /// Equal remainders favor earlier households in the input list.
  ///
  /// Throws [ArgumentError] for invalid bill inputs. Consumption is interpreted
  /// as the exact decimal value of each double's shortest string representation.
  BillAllocation calculate(Bill bill, {required AllocationMethod method}) {
    if (bill.totalAmountCents < 0 || bill.totalAmountCents > 9007199254740991) {
      throw ArgumentError.value(
        bill.totalAmountCents,
        'totalAmountCents',
        'Must be between 0 and 2^53 - 1',
      );
    }
    if (bill.households.isEmpty) {
      throw ArgumentError('At least one household must participate');
    }

    final consumption = bill.totalConsumption;
    if (consumption != null) {
      _validateConsumption(consumption, 'totalConsumption');
    }
    if (method == AllocationMethod.hybrid &&
        (consumption == null || consumption <= 0)) {
      throw ArgumentError('Hybrid allocation needs positive total consumption');
    }

    final days = <BigInt>[];
    final measured = <double>[];

    for (final household in bill.households) {
      if (household.occupants.isEmpty) {
        throw ArgumentError('Each household needs at least one occupant');
      }
      var householdDays = BigInt.zero;

      for (final occupant in household.occupants) {
        if (occupant.occupancyDays <= 0) {
          throw ArgumentError.value(
            occupant.occupancyDays,
            'occupancyDays',
            'Must be positive',
          );
        }
        householdDays += BigInt.from(occupant.occupancyDays);
        final usage = occupant.measuredConsumption;
        if (usage != null) {
          _validateConsumption(usage, 'measuredConsumption');
          measured.add(usage);
        }
      }
      days.add(householdDays);
    }

    final units = _decimalUnits([consumption ?? 0, ...measured]);
    final totalUnits = units.first;
    final measuredUnits = units.skip(1).fold(BigInt.zero, (a, b) => a + b);
    if (consumption != null && measuredUnits > totalUnits) {
      throw ArgumentError('Measured consumption exceeds total consumption');
    }

    final occupantWeights = <List<BigInt>>[];
    final List<BigInt> weights;
    switch (method) {
      case AllocationMethod.hybrid:
        final totalDays = days.fold(BigInt.zero, (a, b) => a + b);
        final remaining = totalUnits - measuredUnits;
        var offset = 1;
        weights = [];
        for (var h = 0; h < bill.households.length; h++) {
          final individualWeights = <BigInt>[];
          for (final occupant in bill.households[h].occupants) {
            final usage = occupant.measuredConsumption == null
                ? BigInt.zero
                : units[offset++];
            // Every occupant, including metered occupants, shares the residual.
            individualWeights.add(
              usage * totalDays +
                  remaining * BigInt.from(occupant.occupancyDays),
            );
          }
          occupantWeights.add(individualWeights);
          weights.add(individualWeights.fold(BigInt.zero, (a, b) => a + b));
        }
      case AllocationMethod.personDays:
        weights = days;
        occupantWeights.addAll([
          for (final household in bill.households)
            [
              for (final occupant in household.occupants)
                BigInt.from(occupant.occupancyDays),
            ],
        ]);
      case AllocationMethod.equalPerHousehold:
        weights = List.filled(bill.households.length, BigInt.one);
    }

    final cents = _allocateCents(bill.totalAmountCents, weights);
    return BillAllocation(
      method: method,
      households: [
        for (var h = 0; h < bill.households.length; h++)
          HouseholdAllocation(
            household: bill.households[h],
            amountCents: cents[h],
            occupants: method == AllocationMethod.equalPerHousehold
                ? null
                : _occupantAllocations(
                    bill.households[h],
                    cents[h],
                    occupantWeights[h],
                  ),
          ),
      ],
    );
  }
}

List<OccupantAllocation> _occupantAllocations(
  Household household,
  int cents,
  List<BigInt> weights,
) {
  // A fully measured bill can leave a household with zero usage and zero cents.
  final shares = weights.every((weight) => weight == BigInt.zero)
      ? List.filled(weights.length, 0)
      : _allocateCents(cents, weights);
  return [
    for (var i = 0; i < household.occupants.length; i++)
      OccupantAllocation(
        occupant: household.occupants[i],
        amountCents: shares[i],
      ),
  ];
}

void _validateConsumption(double value, String name) {
  if (!value.isFinite || value < 0) {
    throw ArgumentError.value(value, name, 'Must be finite and nonnegative');
  }
}

/// Converts finite nonnegative decimal doubles to a shared integer scale.
/// BigInt prevents intermediate overflow and floating-point cent drift.
List<BigInt> _decimalUnits(List<double> values) {
  final coefficients = <BigInt>[];
  final exponents = <int>[];
  var minimumExponent = 0;
  for (final value in values) {
    final parts = value.toString().toLowerCase().split('e');
    final mantissa = parts.first.split('.');
    final fraction = mantissa.length == 2 ? mantissa[1] : '';
    final exponent =
        (parts.length == 2 ? int.parse(parts[1]) : 0) - fraction.length;
    coefficients.add(BigInt.parse(mantissa.first + fraction));
    exponents.add(exponent);
    if (exponent < minimumExponent) minimumExponent = exponent;
  }
  return [
    for (var i = 0; i < values.length; i++)
      coefficients[i] * BigInt.from(10).pow(exponents[i] - minimumExponent),
  ];
}

List<int> _allocateCents(int totalCents, List<BigInt> weights) {
  final denominator = weights.fold(BigInt.zero, (a, b) => a + b);
  if (denominator <= BigInt.zero) {
    throw ArgumentError('Allocation denominator must be positive');
  }
  final total = BigInt.from(totalCents);
  final cents = <int>[];
  final remainders = <BigInt>[];
  var allocated = BigInt.zero;
  for (final weight in weights) {
    final numerator = total * weight;
    final share = numerator ~/ denominator;
    cents.add(share.toInt());
    remainders.add(numerator.remainder(denominator));
    allocated += share;
  }
  final order = List.generate(weights.length, (i) => i)
    ..sort((a, b) {
      final comparison = remainders[b].compareTo(remainders[a]);
      return comparison == 0 ? a.compareTo(b) : comparison;
    });
  final leftover = (total - allocated).toInt();
  for (var i = 0; i < leftover; i++) {
    cents[order[i]]++;
  }
  return cents;
}

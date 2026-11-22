/// Initial bill allocation policies.
enum AllocationMethod { hybrid, personDays, equalPerHousehold }

/// One participant in this bill, rather than a saved household membership.
class Occupant {
  const Occupant({required this.occupancyDays, this.measuredConsumption});

  final int occupancyDays;

  /// In the same unit as [Bill.totalConsumption]; null means unmeasured.
  final double? measuredConsumption;
}

class Household {
  Household({required this.name, required List<Occupant> occupants})
    : occupants = List.unmodifiable(occupants);

  /// A display label, not a unique key.
  final String name;
  final List<Occupant> occupants;
}

/// Inputs for a single expense. Validation occurs when calculating.
class Bill {
  Bill({
    required this.totalAmountCents,
    required List<Household> households,
    this.totalConsumption,
  }) : households = List.unmodifiable(households);

  /// Nonnegative integer cents, at most 2^53 - 1 for Dart web portability.
  final int totalAmountCents;

  /// Required and strictly positive for hybrid allocation.
  final double? totalConsumption;
  final List<Household> households;
}

class HouseholdAllocation {
  const HouseholdAllocation({
    required this.household,
    required this.amountCents,
  });

  final Household household;
  final int amountCents;
}

class BillAllocation {
  BillAllocation({
    required this.method,
    required List<HouseholdAllocation> households,
  }) : households = List.unmodifiable(households);

  final AllocationMethod method;

  /// Same order as the input households, including duplicate display labels.
  final List<HouseholdAllocation> households;

  int get totalAmountCents =>
      households.fold(0, (total, household) => total + household.amountCents);
}

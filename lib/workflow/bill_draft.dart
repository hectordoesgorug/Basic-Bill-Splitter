import '../calculation/bill_models.dart';

enum BillCategory {
  electricity('Electricity', AllocationMethod.hybrid),
  water('Water', AllocationMethod.hybrid),
  internet('Internet', AllocationMethod.personDays),
  rent('Rent', AllocationMethod.personDays),
  lpg('LPG', AllocationMethod.personDays),
  miscellaneous('Miscellaneous', AllocationMethod.equalPerHousehold);

  const BillCategory(this.label, this.defaultMethod);
  final String label;
  final AllocationMethod defaultMethod;

  String get unit => switch (this) {
    electricity => 'kWh',
    water => 'm³',
    _ => 'units',
  };
}

String methodLabel(AllocationMethod method) => switch (method) {
  AllocationMethod.hybrid => 'Hybrid: measured + person-days',
  AllocationMethod.personDays => 'Person-days',
  AllocationMethod.equalPerHousehold => 'Equal per household',
};

enum OccupancyMode { manualDays, fullPeriod, dateRanges }

String modeLabel(OccupancyMode mode) => switch (mode) {
  OccupancyMode.manualDays => 'Manual days',
  OccupancyMode.fullPeriod => 'Full Period',
  OccupancyMode.dateRanges => 'Date ranges',
};

/// Money is parsed as decimal digits, never via a floating-point amount.
int? parsePhpCents(String input) {
  final text = input.trim();
  if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(text)) return null;
  final parts = text.split('.');
  final cents =
      BigInt.parse(parts[0]) * BigInt.from(100) +
      BigInt.parse(parts.length == 1 ? '0' : parts[1].padRight(2, '0'));
  if (cents > BigInt.from(9007199254740991)) return null;
  return cents.toInt();
}

String formatPhp(int cents) {
  final whole = (cents ~/ 100).toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (match) => '${match[1]},',
  );
  return '₱$whole.${(cents % 100).toString().padLeft(2, '0')}';
}

/// Two decimal places for presentation only; never feed this back into a bill.
/// Decimal expansion also keeps very large finite values out of exponent form.
String formatQuantity(num value) {
  if (!value.isFinite) {
    throw ArgumentError.value(value, 'value', 'Must be finite');
  }
  final parts = value.abs().toString().toLowerCase().split('e');
  final mantissa = parts.first.split('.');
  final fraction = mantissa.length == 2 ? mantissa[1] : '';
  final exponent =
      (parts.length == 2 ? int.parse(parts[1]) : 0) - fraction.length + 2;
  var hundredths = BigInt.parse(mantissa.first + fraction);
  if (exponent >= 0) {
    hundredths *= BigInt.from(10).pow(exponent);
  } else {
    final divisor = BigInt.from(10).pow(-exponent);
    hundredths = (hundredths + divisor ~/ BigInt.two) ~/ divisor;
  }
  final sign = value.isNegative && hundredths != BigInt.zero ? '-' : '';
  final whole = hundredths ~/ BigInt.from(100);
  final decimal = (hundredths % BigInt.from(100)).toString().padLeft(2, '0');
  return '$sign$whole.$decimal';
}

String dateText(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

DateTime? parseDate(String input) {
  final text = input.trim();
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) return null;
  final parts = text.split('-').map(int.parse).toList();
  if (parts[0] < 1) return null;
  final date = DateTime.utc(parts[0], parts[1], parts[2]);
  return dateText(date) == text ? date : null;
}

int inclusiveDays(DateTime start, DateTime end) =>
    DateTime.utc(
      end.year,
      end.month,
      end.day,
    ).difference(DateTime.utc(start.year, start.month, start.day)).inDays +
    1;

double? parseConsumption(String text) {
  final trimmed = text.trim();
  if (!RegExp(r'^(?:\d+(?:\.\d*)?|\.\d+)$').hasMatch(trimmed)) return null;
  final value = double.tryParse(trimmed);
  return value != null && value.isFinite && value >= 0 ? value : null;
}

class OccupancyRangeDraft {
  OccupancyRangeDraft({this.start = '', this.end = ''});
  String start;
  String end;
}

class OccupantDraft {
  String measured = '';
  String days = '';
  OccupancyMode mode = OccupancyMode.fullPeriod;
  final ranges = [OccupancyRangeDraft()];
}

class HouseholdDraft {
  HouseholdDraft({this.name = ''});
  String name;
  String headcount = '1';
  final occupants = [OccupantDraft()];

  /// UI guard; the calculation engine has no corresponding limit.
  static const maxOccupants = 10;

  int? get count {
    if (!RegExp(r'^\d+$').hasMatch(headcount.trim())) return null;
    final value = int.tryParse(headcount.trim());
    return value != null && value >= 0 && value <= maxOccupants ? value : null;
  }

  void prepareOccupants() {
    final activeCount = count;
    if (activeCount == null || activeCount == 0) return;
    while (occupants.length < activeCount) {
      occupants.add(OccupantDraft());
    }
    // Retain inactive entries if the headcount is reduced and later restored.
  }

  void clearUsage() {
    for (final occupant in occupants) {
      occupant
        ..measured = ''
        ..days = ''
        ..mode = OccupancyMode.fullPeriod;
      occupant.ranges
        ..clear()
        ..add(OccupancyRangeDraft());
    }
  }
}

/// One transient calculation draft. No persistence or membership identities.
class BillDraft {
  BillDraft({DateTime? today}) {
    final now = today ?? DateTime.now();
    periodStart = dateText(DateTime(now.year, now.month));
    periodEnd = dateText(DateTime(now.year, now.month + 1, 0));
    _initialStart = periodStart;
    _initialEnd = periodEnd;
  }

  BillCategory category = BillCategory.electricity;
  AllocationMethod method = AllocationMethod.hybrid;
  String amount = '';
  late String periodStart;
  late String periodEnd;
  String consumption = '';
  late final String _initialStart;
  late final String _initialEnd;
  final households = [HouseholdDraft(name: 'Household 1')];

  /// Automatic defaults and category selection alone are not entered work.
  bool get hasMeaningfulInputs =>
      amount.trim().isNotEmpty ||
      consumption.trim().isNotEmpty ||
      method != category.defaultMethod ||
      periodStart != _initialStart ||
      periodEnd != _initialEnd ||
      households.length != 1 ||
      households.any(
        (household) =>
            household.name != 'Household 1' ||
            household.headcount.trim() != '1' ||
            household.occupants.any(
              (occupant) =>
                  occupant.measured.trim().isNotEmpty ||
                  occupant.days.trim().isNotEmpty ||
                  occupant.mode != OccupancyMode.fullPeriod ||
                  occupant.ranges.any(
                    (range) =>
                        range.start.trim().isNotEmpty ||
                        range.end.trim().isNotEmpty,
                  ),
            ),
      );

  int get periodDays =>
      inclusiveDays(parseDate(periodStart)!, parseDate(periodEnd)!);

  void selectCategory(BillCategory value) {
    category = value;
    method = value.defaultMethod;
  }

  Map<String, String> validateDetails() {
    final errors = <String, String>{};
    if (parsePhpCents(amount) == null) {
      errors['amount'] =
          'Enter a nonnegative PHP amount with at most 2 decimal places.';
    }
    final start = parseDate(periodStart);
    final end = parseDate(periodEnd);
    if (start == null) {
      errors['periodStart'] = 'Enter a valid date as YYYY-MM-DD.';
    }
    if (end == null) errors['periodEnd'] = 'Enter a valid date as YYYY-MM-DD.';
    if (start != null && end != null && end.isBefore(start)) {
      errors['periodEnd'] = 'End date must be on or after the start date.';
    }
    if (method == AllocationMethod.hybrid) {
      final usage = parseConsumption(consumption);
      if (usage == null || usage <= 0) {
        errors['consumption'] = 'Enter total consumption greater than zero.';
      }
    }
    return errors;
  }

  Map<String, String> validateHouseholds() {
    final errors = <String, String>{};
    if (households.isEmpty) {
      errors['households'] = 'Add at least one household.';
    }
    for (var h = 0; h < households.length; h++) {
      if (households[h].name.trim().isEmpty) {
        errors['h$h.name'] = 'Enter a household name.';
      }
      final count = households[h].count;
      if (count == null || count < 1) {
        errors['h$h.headcount'] =
            'Enter a whole number from 1 to ${HouseholdDraft.maxOccupants}.';
      }
    }
    return errors;
  }

  int occupancyDays(OccupantDraft occupant) => switch (occupant.mode) {
    OccupancyMode.manualDays => int.parse(occupant.days.trim()),
    OccupancyMode.fullPeriod => periodDays,
    OccupancyMode.dateRanges => occupant.ranges.fold(
      0,
      (sum, range) =>
          sum + inclusiveDays(parseDate(range.start)!, parseDate(range.end)!),
    ),
  };

  Map<String, String> validateUsage() {
    final errors = <String, String>{};
    final start = parseDate(periodStart)!;
    final end = parseDate(periodEnd)!;
    for (var h = 0; h < households.length; h++) {
      final household = households[h];
      for (var o = 0; o < (household.count ?? 0); o++) {
        final occupant = household.occupants[o];
        final key = 'h$h.o$o';
        if (occupant.measured.trim().isNotEmpty &&
            parseConsumption(occupant.measured) == null) {
          errors['$key.measured'] =
              'Enter nonnegative measured usage, or leave blank.';
        }
        if (occupant.mode == OccupancyMode.manualDays) {
          final days = int.tryParse(occupant.days.trim());
          if (!RegExp(r'^\d+$').hasMatch(occupant.days.trim()) ||
              days == null ||
              days < 1 ||
              days > periodDays) {
            errors['$key.days'] = 'Enter whole days from 1 to $periodDays.';
          }
        }
        if (occupant.mode == OccupancyMode.dateRanges) {
          if (occupant.ranges.isEmpty) {
            errors['$key.ranges'] = 'Add an occupancy range.';
          }
          final valid = <(DateTime, DateTime)>[];
          for (var r = 0; r < occupant.ranges.length; r++) {
            final range = occupant.ranges[r];
            final from = parseDate(range.start);
            final to = parseDate(range.end);
            final rangeKey = '$key.r$r';
            if (from == null || from.isBefore(start) || from.isAfter(end)) {
              errors['$rangeKey.start'] =
                  'Enter a valid date within the bill period.';
            }
            if (to == null || to.isBefore(start) || to.isAfter(end)) {
              errors['$rangeKey.end'] =
                  'Enter a valid date within the bill period.';
            }
            if (from != null && to != null) {
              if (to.isBefore(from)) {
                errors['$rangeKey.end'] = 'End must be on or after start.';
              } else if (valid.any(
                (prior) => !to.isBefore(prior.$1) && !from.isAfter(prior.$2),
              )) {
                errors['$rangeKey.start'] =
                    'Ranges must not overlap, including shared dates.';
              }
              valid.add((from, to));
            }
          }
        }
      }
    }
    return errors;
  }

  /// Call only after field validation succeeds.
  Bill toBill() => Bill(
    totalAmountCents: parsePhpCents(amount)!,
    totalConsumption: method == AllocationMethod.hybrid
        ? parseConsumption(consumption)
        : null,
    households: [
      for (final household in households)
        Household(
          name: household.name.trim(),
          occupants: [
            for (final occupant in household.occupants.take(household.count!))
              Occupant(
                occupancyDays: occupancyDays(occupant),
                measuredConsumption: occupant.measured.trim().isEmpty
                    ? null
                    : parseConsumption(occupant.measured),
              ),
          ],
        ),
    ],
  );
}

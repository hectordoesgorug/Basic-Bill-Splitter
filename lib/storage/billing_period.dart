class AssignedMonth {
  const AssignedMonth(this.year, this.month);

  final int year;
  final int month;

  String get key =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is AssignedMonth && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);
}

/// Assigns an inclusive period to the month with the most covered days.
/// Ties go to the latest month. UTC calendar arithmetic avoids timezone shifts.
AssignedMonth assignBillingMonth(DateTime start, DateTime end) {
  final from = DateTime.utc(start.year, start.month, start.day);
  final to = DateTime.utc(end.year, end.month, end.day);
  if (to.isBefore(from)) {
    throw ArgumentError('Billing period end must not precede its start');
  }
  final counts = <AssignedMonth, int>{};
  for (
    var day = from;
    !day.isAfter(to);
    day = day.add(const Duration(days: 1))
  ) {
    final month = AssignedMonth(day.year, day.month);
    counts.update(month, (value) => value + 1, ifAbsent: () => 1);
  }
  return counts.entries.reduce((best, entry) {
    if (entry.value > best.value) return entry;
    if (entry.value == best.value &&
        (entry.key.year > best.key.year ||
            (entry.key.year == best.key.year &&
                entry.key.month > best.key.month))) {
      return entry;
    }
    return best;
  }).key;
}

bool billingPeriodsOverlap(
  DateTime leftStart,
  DateTime leftEnd,
  DateTime rightStart,
  DateTime rightEnd,
) {
  final a = DateTime.utc(leftStart.year, leftStart.month, leftStart.day);
  final b = DateTime.utc(leftEnd.year, leftEnd.month, leftEnd.day);
  final c = DateTime.utc(rightStart.year, rightStart.month, rightStart.day);
  final d = DateTime.utc(rightEnd.year, rightEnd.month, rightEnd.day);
  if (b.isBefore(a) || d.isBefore(c)) {
    throw ArgumentError('Billing periods must not be reversed');
  }
  return !b.isBefore(c) && !d.isBefore(a);
}

/// Continues the calendar-day cadence of the prior inclusive billing period.
(DateTime start, DateTime end) nextBillingPeriod(
  DateTime previousStart,
  DateTime previousEnd,
) {
  final start = DateTime.utc(
    previousEnd.year,
    previousEnd.month,
    previousEnd.day,
  ).add(const Duration(days: 1));
  final nextMonth = DateTime.utc(start.year, start.month + 1, start.day);
  final end = nextMonth.subtract(const Duration(days: 1));
  return (start, end);
}

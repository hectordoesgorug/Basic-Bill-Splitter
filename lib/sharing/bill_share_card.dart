import 'package:material_ui/material_ui.dart';

import '../calculation/bill_models.dart';
import '../storage/saved_bill_record.dart';
import '../workflow/bill_draft.dart';

class ShareBillHousehold {
  const ShareBillHousehold({
    required this.name,
    required this.amountCents,
    required this.occupantAmountsCents,
  });

  final String name;
  final int amountCents;
  final List<int>? occupantAmountsCents;
}

class ShareBillCardData {
  ShareBillCardData({
    required this.category,
    required this.startDate,
    required this.endDate,
    required this.totalAmountCents,
    required List<ShareBillHousehold> households,
  }) : households = List.unmodifiable(households);

  final String category;
  final String startDate;
  final String endDate;
  final int totalAmountCents;
  final List<ShareBillHousehold> households;

  factory ShareBillCardData.fromCalculation({
    required BillCategory category,
    required String startDate,
    required String endDate,
    required Bill bill,
    required BillAllocation allocation,
  }) => ShareBillCardData(
    category: category.label,
    startDate: startDate,
    endDate: endDate,
    totalAmountCents: bill.totalAmountCents,
    households: [
      for (final result in allocation.households)
        ShareBillHousehold(
          name: result.household.name,
          amountCents: result.amountCents,
          occupantAmountsCents: result.occupants
              ?.map((item) => item.amountCents)
              .toList(),
        ),
    ],
  );

  factory ShareBillCardData.fromSavedRecord(SavedBillRecord record) {
    final snapshot = record.snapshot;
    final households = snapshot['households']! as List;
    return ShareBillCardData(
      category: BillCategory.values
          .firstWhere((category) => category.name == record.category)
          .label,
      startDate: record.startDate,
      endDate: record.endDate,
      totalAmountCents: snapshot['totalAmountCents']! as int,
      households: [
        for (final value in households)
          _savedHousehold(value as Map<String, Object?>),
      ],
    );
  }

  static ShareBillHousehold _savedHousehold(Map<String, Object?> household) {
    final occupants = household['occupants']! as List;
    final amounts = [
      for (final value in occupants)
        (value as Map<String, Object?>)['amountCents'] as int?,
    ];
    return ShareBillHousehold(
      name: household['name']! as String,
      amountCents: household['amountCents']! as int,
      occupantAmountsCents: amounts.any((amount) => amount == null)
          ? null
          : amounts.cast<int>(),
    );
  }
}

class ShareBillCard extends StatelessWidget {
  const ShareBillCard({super.key, required this.data});

  final ShareBillCardData data;

  static const _accent = Color(0xFF176B60);
  static const _ink = Color(0xFF17312D);
  static const _subtle = Color(0xFF5D6D69);
  static const _surface = Color(0xFFF7FAF8);
  static const _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static String _dateLabel(String value) {
    final parts = value.split('-').map(int.parse).toList();
    final date = DateTime.utc(parts[0], parts[1], parts[2]);
    return '${date.day.toString().padLeft(2, '0')} ${_monthNames[date.month - 1]} ${date.year}';
  }

  @override
  Widget build(BuildContext context) => Material(
    color: _surface,
    borderRadius: BorderRadius.circular(24),
    child: Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _accent.withAlpha(55)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: const BoxDecoration(
              color: _accent,
              borderRadius: BorderRadius.vertical(top: Radius.circular(23)),
            ),
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
            child: Row(
              children: [
                const Icon(Icons.receipt_long, color: Colors.white, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'BASIC BILL SPLITTER',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${data.category} bill',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${_dateLabel(data.startDate)} – ${_dateLabel(data.endDate)}',
                  style: const TextStyle(color: _subtle, fontSize: 14),
                ),
                const SizedBox(height: 14),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _accent.withAlpha(35)),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'TOTAL BILL',
                        style: TextStyle(
                          color: _subtle,
                          fontSize: 11,
                          letterSpacing: 1,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formatPhp(data.totalAmountCents),
                        key: const ValueKey('shareCardTotal'),
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'HOUSEHOLD BREAKDOWN',
                  style: TextStyle(
                    color: _subtle,
                    fontSize: 11,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                for (var h = 0; h < data.households.length; h++) ...[
                  if (h > 0) const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _accent.withAlpha(35)),
                    ),
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                data.households[h].name,
                                key: ValueKey('shareHouseholdName$h'),
                                style: const TextStyle(
                                  color: _ink,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              formatPhp(data.households[h].amountCents),
                              key: ValueKey('shareHouseholdAmount$h'),
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                color: _accent,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        if (data.households[h].occupantAmountsCents
                            case final amounts?) ...[
                          const SizedBox(height: 10),
                          for (var o = 0; o < amounts.length; o++)
                            Padding(
                              padding: const EdgeInsets.only(top: 5),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Occupant ${o + 1}',
                                      style: const TextStyle(
                                        color: _subtle,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    formatPhp(amounts[o]),
                                    key: ValueKey('shareOccupantAmount$h-$o'),
                                    style: const TextStyle(
                                      color: _ink,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                const Divider(color: Color(0xFFD9E4E0)),
                const SizedBox(height: 6),
                const Center(
                  child: Text(
                    'Splitter · Basic Bill Splitter',
                    style: TextStyle(color: _subtle, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

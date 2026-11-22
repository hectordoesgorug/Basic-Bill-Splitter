import 'package:material_ui/material_ui.dart';

import '../currency/currency.dart';
import '../workflow/bill_draft.dart';
import '../calculation/bill_models.dart';
import '../storage/saved_bill_record.dart';

class SavedComputationView extends StatelessWidget {
  const SavedComputationView({super.key, required this.record});

  final SavedBillRecord record;

  List<Map<String, Object?>> get _households =>
      (record.snapshot['households']! as List).cast<Map<String, Object?>>();

  Iterable<Map<String, Object?>> get _occupants sync* {
    for (final household in _households) {
      yield* (household['occupants']! as List).cast<Map<String, Object?>>();
    }
  }

  String _money(int cents) =>
      formatCurrency(cents, record.currencyCode, includeCode: true);

  Widget _step(BuildContext context, String title, List<Widget> contents) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...contents,
            ],
          ),
        ),
      );

  Widget _savedAllocations(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var h = 0; h < _households.length; h++) ...[
        if (h > 0) const SizedBox(height: 8),
        Text(
          '${_households[h]['name']}: ${_money(_households[h]['amountCents']! as int)}',
          key: ValueKey('computationHouseholdAmount$h'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        if (record.snapshot['allocationMethod'] != 'equalPerHousehold')
          for (
            var o = 0;
            o < (_households[h]['occupants']! as List).length;
            o++
          )
            if (((_households[h]['occupants']! as List)[o]
                    as Map<String, Object?>)['amountCents']
                case final int cents)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 4),
                child: Text('Occupant ${o + 1}: ${_money(cents)}'),
              ),
      ],
    ],
  );

  Widget _equalExplanation(BuildContext context) {
    final total = record.snapshot['totalAmountCents']! as int;
    final count = _households.length;
    final baseCents = total ~/ count;
    final extraCents = total % count;
    return Column(
      children: [
        _step(context, 'Step 1 — Divide the bill', [
          Text('Total bill: ${_money(total)}.'),
          Text('$count participating households share equally.'),
          Text(
            'Equal share starts at ${_money(baseCents)} per household; $extraCents remaining cent(s) are assigned by household input order.',
          ),
        ]),
        _step(context, 'Step 2 — Saved household amounts', [
          _savedAllocations(context),
          const SizedBox(height: 8),
          const Text(
            'This method does not define individual occupant amounts.',
          ),
        ]),
      ],
    );
  }

  Widget _personDaysExplanation(BuildContext context) {
    final occupants = _occupants.toList(growable: false);
    final totalDays = occupants.fold<int>(
      0,
      (sum, occupant) => sum + (occupant['occupancyDays']! as int),
    );
    return Column(
      children: [
        _step(context, 'Step 1 — Count person-days', [
          for (var h = 0; h < _households.length; h++)
            for (
              var o = 0;
              o < (_households[h]['occupants']! as List).length;
              o++
            )
              Builder(
                builder: (context) {
                  final days =
                      (((_households[h]['occupants']! as List)[o]
                              as Map<String, Object?>)['occupancyDays']!
                          as int);
                  return Text(
                    '${_households[h]['name']} · Occupant ${o + 1}: $days / $totalDays person-days (${(days / totalDays * 100).toStringAsFixed(2)}%).',
                  );
                },
              ),
          Text('Total: $totalDays person-days.'),
        ]),
        _step(context, 'Step 2 — Determine proportional shares', [
          Text(
            'Each occupant weight is their days divided by $totalDays total person-days.',
          ),
          const Text('Occupant weights are combined into household shares.'),
        ]),
        _step(context, 'Step 3 — Reconcile cents', [
          Text(
            'The bill is ${_money(record.snapshot['totalAmountCents']! as int)}.',
          ),
          const Text(
            'Fractional cents are reconciled by largest remainder; ties follow input order.',
          ),
        ]),
        _step(context, 'Step 4 — Saved amounts', [_savedAllocations(context)]),
      ],
    );
  }

  Widget _hybridExplanation(BuildContext context) {
    final category = BillCategory.values.firstWhere(
      (value) => value.name == record.category,
    );
    final totalCents = record.snapshot['totalAmountCents']! as int;
    final totalConsumption = record.snapshot['totalConsumption']! as num;
    final measured = _occupants
        .map((occupant) => occupant['measuredConsumption'] as num?)
        .whereType<num>()
        .fold<double>(0, (sum, value) => sum + value.toDouble());
    final residual = totalConsumption.toDouble() - measured;
    final personDays = _occupants.fold<int>(
      0,
      (sum, occupant) => sum + (occupant['occupancyDays']! as int),
    );
    final rate = totalCents / 100 / totalConsumption;
    return Column(
      children: [
        _step(context, 'Step 1 — Find the unit rate', [
          Text('Bill amount: ${_money(totalCents)}.'),
          Text(
            'Total consumption: ${formatQuantity(totalConsumption)} ${category.unit}.',
          ),
          Text(
            'Displayed unit rate: ${record.currencyCode} ${rate.toStringAsFixed(6)} per ${category.unit}.',
          ),
          const Text(
            'The displayed rate is rounded for explanation; saved cents below are authoritative.',
          ),
        ]),
        _step(context, 'Step 2 — Apply measured usage', [
          for (var h = 0; h < _households.length; h++)
            for (
              var o = 0;
              o < (_households[h]['occupants']! as List).length;
              o++
            )
              Builder(
                builder: (context) {
                  final occupant =
                      ((_households[h]['occupants']! as List)[o]
                          as Map<String, Object?>);
                  final value = occupant['measuredConsumption'];
                  return Text(
                    '${_households[h]['name']} · Occupant ${o + 1}: ${value is num ? '${formatQuantity(value)} ${category.unit} measured' : 'no measured usage specified'}, ${occupant['occupancyDays']} occupancy day(s).',
                  );
                },
              ),
          Text('Total measured: ${formatQuantity(measured)} ${category.unit}.'),
          Text(
            'Residual consumption: ${formatQuantity(totalConsumption)} − ${formatQuantity(measured)} = ${formatQuantity(residual)} ${category.unit}.',
          ),
        ]),
        _step(context, 'Step 3 — Share residual consumption', [
          Text('The residual is distributed across $personDays person-days.'),
          const Text(
            'Every participating occupant shares the residual by occupancy days, including occupants with measured usage.',
          ),
          const Text(
            'An occupant charge combines their measured usage with their person-day portion of the residual, priced at the unit rate.',
          ),
        ]),
        _step(context, 'Step 4 — Reconcile cents', [
          const Text(
            'Household cents are reconciled first. Occupant cents are then reconciled within each household using largest remainders and input-order ties.',
          ),
          _savedAllocations(context),
        ]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final method = AllocationMethod.values.firstWhere(
      (value) => value.name == record.snapshot['allocationMethod'],
    );
    return ListView(
      key: const ValueKey('savedComputation'),
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          methodLabel(method),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'This explanation uses the saved inputs and historical allocations. It does not recalculate the bill.',
        ),
        const SizedBox(height: 12),
        switch (method) {
          AllocationMethod.equalPerHousehold => _equalExplanation(context),
          AllocationMethod.personDays => _personDaysExplanation(context),
          AllocationMethod.hybrid => _hybridExplanation(context),
        },
      ],
    );
  }
}

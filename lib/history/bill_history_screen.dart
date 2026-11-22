import 'package:material_ui/material_ui.dart';

import '../calculation/bill_models.dart';
import '../storage/bill_repository.dart';
import '../storage/saved_bill_record.dart';
import '../sharing/bill_share_card.dart';
import '../sharing/bill_share_export.dart';
import '../workflow/bill_draft.dart';

const _monthNames = [
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

class BillHistoryScreen extends StatefulWidget {
  const BillHistoryScreen({
    super.key,
    required this.repository,
    required this.category,
  });

  final BillRepository repository;
  final BillCategory category;

  @override
  State<BillHistoryScreen> createState() => _BillHistoryScreenState();
}

class _BillHistoryScreenState extends State<BillHistoryScreen> {
  List<SavedBillRecord> _records = const [];
  int? _year;
  Object? _loadError;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory(initial: true);
  }

  Future<void> _loadHistory({bool initial = false}) async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final all = await widget.repository.allRecords();
      final records = all
          .where((record) => record.category == widget.category.name)
          .toList(growable: false);
      final years = records.map((record) => record.assignedYear).toList();
      if (!mounted) return;
      setState(() {
        _records = records;
        _year = initial || _year == null
            ? years.isEmpty
                  ? DateTime.now().year
                  : years.reduce((a, b) => a > b ? a : b)
            : _year;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  List<SavedBillRecord> get _visibleRecords {
    final records =
        _records
            .where((record) => record.assignedYear == _year)
            .toList(growable: false)
          ..sort((a, b) => b.assignedMonth.compareTo(a.assignedMonth));
    return records;
  }

  Map<int, SavedBillRecord> get _monthlyRecords => {
    for (final record in _visibleRecords) record.assignedMonth: record,
  };

  Future<void> _openRecord(SavedBillRecord record) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SavedBillDetailScreen(record: record),
      ),
    );
    if (mounted) await _loadHistory();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('${widget.category.label} History')),
    body: SafeArea(
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? _HistoryError(onRetry: () => _loadHistory())
          : LayoutBuilder(
              builder: (context, constraints) {
                final largeText =
                    MediaQuery.textScalerOf(context).scale(14) > 19;
                if (largeText || constraints.maxHeight < 540) {
                  return SingleChildScrollView(
                    child: Column(
                      children: [
                        SizedBox(height: 310, child: _annualGraph()),
                        const Divider(height: 1),
                        _billList(shrinkWrap: true),
                      ],
                    ),
                  );
                }
                return Column(
                  children: [
                    Expanded(flex: 2, child: _annualGraph()),
                    const Divider(height: 1),
                    Expanded(flex: 3, child: _billList()),
                  ],
                );
              },
            ),
    ),
  );

  Widget _annualGraph() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
    child: Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              key: const ValueKey('historyPreviousYear'),
              tooltip: 'Previous year',
              onPressed: () => setState(() => _year = _year! - 1),
              icon: const Icon(Icons.chevron_left),
            ),
            Text(
              '$_year',
              key: const ValueKey('historySelectedYear'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            IconButton(
              key: const ValueKey('historyNextYear'),
              tooltip: 'Next year',
              onPressed: () => setState(() => _year = _year! + 1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        Expanded(
          child: AnnualBillGraph(
            year: _year!,
            recordsByMonth: _monthlyRecords,
            months: _monthNames,
          ),
        ),
      ],
    ),
  );

  Widget _billList({bool shrinkWrap = false}) {
    final records = _visibleRecords;
    if (records.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No saved ${widget.category.label.toLowerCase()} bills for $_year.',
            key: const ValueKey('historyEmpty'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: records.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final record = records[index];
        final month = _monthNames[record.assignedMonth - 1];
        final cents = record.snapshot['totalAmountCents']! as int;
        return ListTile(
          key: ValueKey('history-record-${record.id}'),
          title: Text('$month ${record.assignedYear}'),
          subtitle: Text(
            '${_dateLabel(record.startDate)} – ${_dateLabel(record.endDate)}',
          ),
          trailing: Text(
            formatPhp(cents),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          onTap: () => _openRecord(record),
        );
      },
    );
  }

  static String _dateLabel(String value) {
    final parts = value.split('-').map(int.parse).toList();
    final date = DateTime.utc(parts[0], parts[1], parts[2]);
    return '${date.day.toString().padLeft(2, '0')} ${_monthNames[date.month - 1]} ${date.year}';
  }
}

class AnnualBillGraph extends StatelessWidget {
  const AnnualBillGraph({
    super.key,
    required this.year,
    required this.recordsByMonth,
    required this.months,
  });

  final int year;
  final Map<int, SavedBillRecord> recordsByMonth;
  final List<String> months;

  String _axisLabel(int cents) {
    final pesos = cents ~/ 100;
    if (pesos >= 1000000) return '₱${pesos ~/ 1000000}m';
    if (pesos >= 10000) return '₱${pesos ~/ 1000}k';
    return formatPhp(cents);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final textScale = MediaQuery.textScalerOf(context).scale(12) / 12;
      final scroll = constraints.maxWidth < 320 || textScale > 1.4;
      final graphWidth = scroll ? 540.0 : constraints.maxWidth;
      var maximum = recordsByMonth.values.fold<int>(0, (value, record) {
        final cents = record.snapshot['totalAmountCents']! as int;
        return cents > value ? cents : value;
      });
      if (maximum == 0) maximum = 100;

      final graph = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 54,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(_axisLabel(maximum)),
                ),
                const Text('₱0'),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, plot) => Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var month = 1; month <= 12; month++)
                    Expanded(
                      child: _monthBar(context, month, plot.maxHeight, maximum),
                    ),
                ],
              ),
            ),
          ),
        ],
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Amount (PHP)'),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: scroll
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(width: graphWidth, child: graph),
                  )
                : graph,
          ),
        ],
      );
    },
  );

  Widget _monthBar(
    BuildContext context,
    int month,
    double availableHeight,
    int maximum,
  ) {
    final record = recordsByMonth[month];
    final cents = record?.snapshot['totalAmountCents'] as int?;
    final semantics = cents == null
        ? '${months[month - 1]} $year: no saved bill'
        : '${months[month - 1]} $year: ${formatPhp(cents)}';
    final barColor = Theme.of(context).colorScheme.primary;
    final height = cents == null
        ? 0.0
        : cents == 0
        ? 3.0
        : (cents / maximum * (availableHeight - 26)).clamp(
            3.0,
            availableHeight - 26,
          );
    return Semantics(
      label: semantics,
      child: Tooltip(
        message: semantics,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: Column(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: 14,
                    height: height,
                    decoration: BoxDecoration(
                      color: cents == null
                          ? Colors.transparent
                          : cents == 0
                          ? barColor.withAlpha(120)
                          : barColor,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(5),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 24,
                child: Center(
                  child: Text(
                    months[month - 1].substring(0, 3),
                    maxLines: 1,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryError extends StatelessWidget {
  const _HistoryError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 40),
          const SizedBox(height: 12),
          const Text(
            'Saved bills could not be loaded.',
            key: ValueKey('historyLoadError'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey('historyRetry'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}

class SavedBillDetailScreen extends StatelessWidget {
  const SavedBillDetailScreen({super.key, required this.record});

  final SavedBillRecord record;

  @override
  Widget build(BuildContext context) {
    final card = ShareBillCardData.fromSavedRecord(record);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${card.category} · ${record.assignedYear}'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Card'),
              Tab(text: 'Details'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _SavedCardView(data: card),
            _SavedDetailsView(record: record),
          ],
        ),
      ),
    );
  }
}

class _SavedCardView extends StatelessWidget {
  const _SavedCardView({required this.data});

  final ShareBillCardData data;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: ShareBillCard(data: data),
            ),
          ),
        ),
      ),
      SafeArea(
        minimum: const EdgeInsets.all(16),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const ValueKey('historyShare'),
            onPressed: () => shareBillCard(context, data),
            icon: const Icon(Icons.share),
            label: const Text('Share'),
          ),
        ),
      ),
    ],
  );
}

class _SavedDetailsView extends StatelessWidget {
  const _SavedDetailsView({required this.record});

  final SavedBillRecord record;

  String _modeLabel(String mode) => switch (mode) {
    'manualDays' => 'Manual days',
    'dateRanges' => 'Date ranges',
    _ => 'Full Period',
  };

  @override
  Widget build(BuildContext context) {
    final snapshot = record.snapshot;
    final category = BillCategory.values.firstWhere(
      (value) => value.name == record.category,
    );
    final method = AllocationMethod.values.firstWhere(
      (value) => value.name == snapshot['allocationMethod'],
    );
    final households = snapshot['households']! as List;
    final assignedMonth =
        '${_monthNames[record.assignedMonth - 1]} ${record.assignedYear}';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(category.label, style: Theme.of(context).textTheme.headlineSmall),
        Text(
          'Billing period: ${_dateLabel(record.startDate)} – ${_dateLabel(record.endDate)}',
        ),
        Text('Assigned month: $assignedMonth'),
        Text('Total bill: ${formatPhp(snapshot['totalAmountCents']! as int)}'),
        Text('Allocation method: ${methodLabel(method)}'),
        if (snapshot['totalConsumption'] case final num consumption)
          Text(
            'Total consumption: ${formatQuantity(consumption)} ${category.unit}',
          ),
        const SizedBox(height: 12),
        for (var h = 0; h < households.length; h++)
          _household(context, h, households[h] as Map<String, Object?>),
      ],
    );
  }

  Widget _household(
    BuildContext context,
    int index,
    Map<String, Object?> household,
  ) {
    final occupants = household['occupants']! as List;
    return Card(
      key: ValueKey('savedHousehold$index'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              household['name']! as String,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text('${occupants.length} occupant(s)'),
            const SizedBox(height: 8),
            Text(
              'Household amount: ${formatPhp(household['amountCents']! as int)}',
            ),
            for (var o = 0; o < occupants.length; o++)
              _occupant(context, o, occupants[o] as Map<String, Object?>),
          ],
        ),
      ),
    );
  }

  Widget _occupant(
    BuildContext context,
    int index,
    Map<String, Object?> occupant,
  ) {
    final mode = occupant['mode']! as String;
    final ranges = occupant['ranges']! as List;
    final measured = occupant['measuredConsumption'];
    final cents = occupant['amountCents'];
    final category = BillCategory.values.firstWhere(
      (value) => value.name == record.category,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 12, left: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Occupant ${index + 1}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            'Duration: ${occupant['occupancyDays']} days · ${_modeLabel(mode)}',
          ),
          if (mode == 'manualDays')
            Text('Manual days: ${occupant['manualDays']}'),
          if (mode == 'dateRanges')
            for (final value in ranges)
              Text(
                'Range: ${_dateLabel((value as Map<String, Object?>)['start']! as String)} – ${_dateLabel(value['end']! as String)}',
              ),
          Text(
            measured is num
                ? 'Measured consumption: ${formatQuantity(measured)} ${category.unit}'
                : 'Measured consumption: not specified',
          ),
          if (cents is int) Text('Occupant amount: ${formatPhp(cents)}'),
        ],
      ),
    );
  }

  static String _dateLabel(String value) {
    final parts = value.split('-').map(int.parse).toList();
    final date = DateTime.utc(parts[0], parts[1], parts[2]);
    return '${date.day.toString().padLeft(2, '0')} ${_monthNames[date.month - 1]} ${date.year}';
  }
}

import 'package:material_ui/material_ui.dart';

import '../calculation/bill_calculator.dart';
import '../calculation/bill_models.dart';
import 'bill_draft.dart';

class BillWorkflow extends StatefulWidget {
  const BillWorkflow({super.key, this.draft});

  final BillDraft? draft;

  @override
  State<BillWorkflow> createState() => _BillWorkflowState();
}

class _BillWorkflowState extends State<BillWorkflow> {
  late BillDraft _draft = widget.draft ?? BillDraft();
  final _scroll = ScrollController();
  Map<String, String> _errors = {};
  int _step = 0;
  int _revision = 0;
  Bill? _bill;
  BillAllocation? _allocation;

  static const _titles = [
    'Bill Details',
    'Households',
    'Usage & Duration',
    'Review',
    'Results',
  ];

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _go(int step) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _step = step;
      _errors = {};
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  void _back() {
    if (_step > 0) _go(_step - 1);
  }

  void _next() {
    final errors = switch (_step) {
      0 => _draft.validateDetails(),
      1 => _draft.validateHouseholds(),
      2 => _draft.validateUsage(),
      _ => <String, String>{},
    };
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
      return;
    }
    if (_step == 1) {
      for (final household in _draft.households) {
        household.prepareOccupants();
      }
    }
    if (_step == 2) {
      final bill = _draft.toBill();
      try {
        _allocation = const BillCalculator().calculate(
          bill,
          method: _draft.method,
        );
        _bill = bill;
      } on ArgumentError {
        // Scalar fields were validated above; the engine checks aggregate usage.
        final message =
            'Combined measured usage must not exceed ${_draft.consumption} ${_draft.category.unit}.';
        final usageErrors = <String, String>{'usage': message};
        for (var h = 0; h < _draft.households.length; h++) {
          final household = _draft.households[h];
          for (var o = 0; o < household.count!; o++) {
            if (household.occupants[o].measured.trim().isNotEmpty) {
              usageErrors['h$h.o$o.measured'] = message;
            }
          }
        }
        setState(() => _errors = usageErrors);
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
        return;
      }
    }
    _go(_step + 1);
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _newCalculation() async {
    if (!await _confirm(
      'Start a new calculation?',
      'This clears the current draft and results.',
      'Start new',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _draft = BillDraft();
      _bill = null;
      _allocation = null;
      _revision++;
    });
    _go(0);
  }

  Widget _field(
    String id,
    String label,
    String value,
    ValueChanged<String> update, {
    bool numeric = false,
    String? hint,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      key: ValueKey(id),
      initialValue: value,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      textCapitalization: numeric
          ? TextCapitalization.none
          : TextCapitalization.sentences,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: _errors[id],
      ),
      onChanged: (text) {
        update(text);
        if (_errors.containsKey(id)) setState(() => _errors.remove(id));
      },
    ),
  );

  Widget _date(
    String id,
    String label,
    String value,
    ValueChanged<String> update,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: _DateField(
      key: ValueKey(id),
      label: label,
      value: value,
      error: _errors[id],
      onChanged: (text) {
        update(text);
        if (_errors.containsKey(id)) setState(() => _errors.remove(id));
      },
    ),
  );

  Widget _dropdown<T>(
    String id,
    String label,
    T value,
    List<T> values,
    String Function(T) describe,
    ValueChanged<T> update,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: DropdownButtonFormField<T>(
      key: ValueKey(id),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final item in values)
          DropdownMenuItem(value: item, child: Text(describe(item))),
      ],
      onChanged: (item) {
        if (item != null) setState(() => update(item));
      },
    ),
  );

  Widget _card(List<Widget> children) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Text(text, style: Theme.of(context).textTheme.titleLarge),
  );

  List<Widget> _details() => [
    const Padding(
      padding: EdgeInsets.only(bottom: 24),
      child: Text(
        'Split one residential bill. Your draft stays here while you move between steps; it is not saved when the app closes.',
      ),
    ),
    _dropdown(
      'category',
      'Category',
      _draft.category,
      BillCategory.values,
      (category) => category.label,
      (category) {
        _draft.selectCategory(category);
        _revision++;
      },
    ),
    _dropdown(
      'method-${_draft.category.name}',
      'Allocation method',
      _draft.method,
      AllocationMethod.values,
      methodLabel,
      (method) => _draft.method = method,
    ),
    _field(
      'amount',
      'Bill amount (PHP)',
      _draft.amount,
      (text) => _draft.amount = text,
      numeric: true,
      hint: '1234.56',
    ),
    _date(
      'periodStart',
      'Period start',
      _draft.periodStart,
      (text) => _draft.periodStart = text,
    ),
    _date(
      'periodEnd',
      'Period end',
      _draft.periodEnd,
      (text) => _draft.periodEnd = text,
    ),
    if (_draft.method == AllocationMethod.hybrid) ...[
      _field(
        'consumption',
        'Total consumption (${_draft.category.unit})',
        _draft.consumption,
        (text) => _draft.consumption = text,
        numeric: true,
      ),
      const Text(
        'Measured usage is charged directly. Remaining usage is shared by the occupancy days of every participant, including metered occupants.',
      ),
    ],
  ];

  List<Widget> _households() => [
    const Padding(
      padding: EdgeInsets.only(bottom: 16),
      child: Text(
        'Add the households sharing this bill and the number of participating occupants in each.',
      ),
    ),
    for (var h = 0; h < _draft.households.length; h++)
      _card([
        Row(
          children: [
            Expanded(child: _heading('Household ${h + 1}')),
            if (_draft.households.length > 1)
              IconButton(
                tooltip: 'Remove household ${h + 1}',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  final household = _draft.households[h];
                  if (!await _confirm(
                    'Remove household?',
                    'Remove ${household.name} and its occupant inputs from this draft?',
                    'Remove',
                  )) {
                    return;
                  }
                  if (!mounted) return;
                  setState(() {
                    _draft.households.remove(household);
                    _errors = {};
                    _revision++;
                  });
                },
              ),
          ],
        ),
        _field(
          'h$h.name',
          'Household name',
          _draft.households[h].name,
          (text) => _draft.households[h].name = text,
        ),
        _field(
          'h$h.headcount',
          'Occupant headcount',
          _draft.households[h].headcount,
          (text) => _draft.households[h].headcount = text,
          numeric: true,
        ),
      ]),
    OutlinedButton.icon(
      key: const ValueKey('addHousehold'),
      onPressed: () => setState(() {
        _draft.households.add(
          HouseholdDraft(name: 'Household ${_draft.households.length + 1}'),
        );
      }),
      icon: const Icon(Icons.add),
      label: const Text('Add household'),
    ),
  ];

  List<Widget> _usage() => [
    Text(
      'Bill period: ${_draft.periodStart} to ${_draft.periodEnd} (${_draft.periodDays} days, inclusive).',
    ),
    const SizedBox(height: 16),
    if (_draft.method != AllocationMethod.hybrid)
      const Padding(
        padding: EdgeInsets.only(bottom: 16),
        child: Text(
          'Measured usage is optional and does not affect this method.',
        ),
      ),
    if (_draft.method == AllocationMethod.equalPerHousehold)
      const Padding(
        padding: EdgeInsets.only(bottom: 16),
        child: Text(
          'Households receive equal shares. Occupant inputs are recorded for review; no individual monetary split is calculated.',
        ),
      ),
    for (var h = 0; h < _draft.households.length; h++) ...[
      _heading(_draft.households[h].name.trim()),
      for (var o = 0; o < _draft.households[h].count!; o++)
        _occupantFields(h, o),
    ],
  ];

  Widget _occupantFields(int h, int o) {
    final occupant = _draft.households[h].occupants[o];
    final key = 'h$h.o$o';
    return _card([
      _heading('Occupant ${o + 1}'),
      _field(
        '$key.measured',
        'Measured usage (${_draft.category.unit}, optional)',
        occupant.measured,
        (text) => occupant.measured = text,
        numeric: true,
      ),
      _dropdown(
        '$key.mode',
        'Occupancy duration',
        occupant.mode,
        OccupancyMode.values,
        modeLabel,
        (mode) => occupant.mode = mode,
      ),
      if (occupant.mode == OccupancyMode.fullPeriod)
        Text('Full Period: ${_draft.periodDays} days'),
      if (occupant.mode == OccupancyMode.manualDays)
        _field(
          '$key.days',
          'Occupancy days',
          occupant.days,
          (text) => occupant.days = text,
          numeric: true,
        ),
      if (occupant.mode == OccupancyMode.dateRanges) ...[
        const Text(
          'Both dates count. Ranges for this occupant must not overlap.',
        ),
        for (var r = 0; r < occupant.ranges.length; r++) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: Text('Range ${r + 1}')),
              if (occupant.ranges.length > 1)
                IconButton(
                  tooltip: 'Remove range ${r + 1}',
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () => setState(() {
                    occupant.ranges.removeAt(r);
                    _errors = {};
                    _revision++;
                  }),
                ),
            ],
          ),
          _date(
            '$key.r$r.start',
            'Range start',
            occupant.ranges[r].start,
            (text) => occupant.ranges[r].start = text,
          ),
          _date(
            '$key.r$r.end',
            'Range end',
            occupant.ranges[r].end,
            (text) => occupant.ranges[r].end = text,
          ),
        ],
        OutlinedButton.icon(
          key: ValueKey('$key.addRange'),
          onPressed: () =>
              setState(() => occupant.ranges.add(OccupancyRangeDraft())),
          icon: const Icon(Icons.add),
          label: const Text('Add date range'),
        ),
      ],
    ]);
  }

  String _durationSummary(OccupantDraft occupant, Occupant input) {
    final ranges = occupant.mode == OccupancyMode.dateRanges
        ? ' · ${occupant.ranges.map((r) => '${r.start} to ${r.end}').join('; ')}'
        : '';
    return '${modeLabel(occupant.mode)} · ${input.occupancyDays} days$ranges';
  }

  Widget _occupantSummary(
    int h,
    int o,
    Occupant input, {
    int? cents,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Occupant ${o + 1}${cents == null ? '' : ' · ${formatPhp(cents)}'}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(_durationSummary(_draft.households[h].occupants[o], input)),
        Text(
          input.measuredConsumption == null
              ? 'Measured usage: not specified'
              : 'Measured usage: ${_draft.households[h].occupants[o].measured.trim()} ${_draft.category.unit}',
        ),
      ],
    ),
  );

  List<Widget> _summary({required bool results}) {
    final bill = _bill!;
    return [
      _card([
        Text(
          _draft.category.label,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          formatPhp(bill.totalAmountCents),
          key: const ValueKey('billTotal'),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          '${_draft.periodStart} to ${_draft.periodEnd} · ${_draft.periodDays} days',
        ),
        Text(methodLabel(_draft.method)),
        if (bill.totalConsumption != null)
          Text(
            'Total consumption: ${_draft.consumption.trim()} ${_draft.category.unit}',
          ),
      ]),
      if (results)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            _draft.method == AllocationMethod.equalPerHousehold
                ? 'Household totals are equal apart from reconciled cents. No individual monetary split is defined.'
                : 'Occupant amounts add up to each household total; household totals add up to the bill. Fractional cents are reconciled by largest remainder.',
          ),
        ),
      for (var h = 0; h < bill.households.length; h++)
        _card([
          Text(
            bill.households[h].name,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (results)
            Text(
              formatPhp(_allocation!.households[h].amountCents),
              key: ValueKey('householdTotal$h'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          Text('${bill.households[h].occupants.length} occupant(s)'),
          const Divider(),
          for (var o = 0; o < bill.households[h].occupants.length; o++)
            _occupantSummary(
              h,
              o,
              bill.households[h].occupants[o],
              cents: results
                  ? _allocation!.households[h].occupants
                        ?.elementAt(o)
                        .amountCents
                  : null,
            ),
        ]),
      if (!results)
        const Text(
          'Check these inputs before viewing the calculated amounts. Use Back to make changes.',
        ),
    ];
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _step == 0,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _back();
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Basic Bill Splitter'),
        leading: _step == 0
            ? null
            : IconButton(
                tooltip: 'Back',
                onPressed: _back,
                icon: const Icon(Icons.arrow_back),
              ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            LinearProgressIndicator(value: (_step + 1) / _titles.length),
            Expanded(
              child: SingleChildScrollView(
                key: ValueKey('step$_step-$_revision'),
                controller: _scroll,
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Step ${_step + 1} of 5',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _titles[_step],
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 24),
                        if (_errors.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(
                              _errors['usage'] ??
                                  'Check the highlighted fields to continue.',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        ...switch (_step) {
                          0 => _details(),
                          1 => _households(),
                          2 => _usage(),
                          3 => _summary(results: false),
                          _ => _summary(results: true),
                        },
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Row(
          children: [
            if (_step > 0) ...[
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('back'),
                  onPressed: _back,
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(width: 16),
            ],
            Expanded(
              child: FilledButton(
                key: const ValueKey('next'),
                onPressed: _step == 4 ? _newCalculation : _next,
                child: Text(
                  _step == 4
                      ? 'New calculation'
                      : _step == 3
                      ? 'Calculate'
                      : 'Continue',
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DateField extends StatefulWidget {
  const _DateField({
    super.key,
    required this.label,
    required this.value,
    required this.error,
    required this.onChanged,
  });

  final String label;
  final String value;
  final String? error;
  final ValueChanged<String> onChanged;

  @override
  State<_DateField> createState() => _DateFieldState();
}

class _DateFieldState extends State<_DateField> {
  late final _controller = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: parseDate(_controller.text) ?? DateTime.now(),
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 31),
    );
    if (selected == null || !mounted) return;
    _controller.text = dateText(selected);
    widget.onChanged(_controller.text);
  }

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: _controller,
    keyboardType: TextInputType.datetime,
    decoration: InputDecoration(
      labelText: widget.label,
      hintText: 'YYYY-MM-DD',
      errorText: widget.error,
      suffixIcon: IconButton(
        tooltip: 'Choose ${widget.label.toLowerCase()}',
        onPressed: _pick,
        icon: const Icon(Icons.calendar_month_outlined),
      ),
    ),
    onChanged: widget.onChanged,
  );
}

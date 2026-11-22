import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import '../calculation/bill_calculator.dart';
import '../calculation/bill_models.dart';
import '../app/app_menu.dart';
import '../storage/bill_repository.dart';
import '../storage/billing_period.dart';
import '../storage/saved_bill_record.dart';
import 'bill_draft.dart';
import 'date_range_fields.dart';
import 'household_section.dart';
import '../sharing/bill_share_card.dart';
import '../sharing/bill_share_export.dart';

class BillWorkflow extends StatefulWidget {
  const BillWorkflow({
    super.key,
    required this.draft,
    required this.repository,
    required this.onHome,
    required this.version,
    this.darkMode = false,
    this.onDarkModeChanged,
  });

  final BillDraft draft;
  final BillRepository repository;
  final VoidCallback onHome;
  final Future<String?> version;
  final bool darkMode;
  final Future<bool> Function(bool enabled)? onDarkModeChanged;

  @override
  State<BillWorkflow> createState() => _BillWorkflowState();
}

class _BillWorkflowState extends State<BillWorkflow> {
  late final BillDraft _draft = widget.draft;
  final _accentIndices = <HouseholdDraft, int>{};
  int _nextAccent = 0;
  final _scroll = ScrollController();
  Map<String, String> _errors = {};
  int _step = 0;
  bool _detailsValidated = false;
  bool _householdsValidated = false;
  bool _usageValidated = false;
  Bill? _bill;
  BillAllocation? _allocation;
  String? _savedRecordId;
  String? _savedCreatedAt;
  String? _savedSignature;
  bool _saving = false;
  bool _sharing = false;
  int _overlapRequest = 0;
  String? _acknowledgedOverlap;

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

  bool _canVisit(int step) {
    if (step == 0) return true;
    if (!_detailsValidated || _draft.validateDetails().isNotEmpty) return false;
    if (step == 1) return true;
    if (!_householdsValidated || _draft.validateHouseholds().isNotEmpty) {
      return false;
    }
    for (final household in _draft.households) {
      household.prepareOccupants();
    }
    if (step == 2) return true;
    if (!_usageValidated || _draft.validateUsage().isNotEmpty) return false;
    if (step == 3) return true;
    return _allocation != null && _bill != null;
  }

  void _changed() {
    if (_step == 0) _detailsValidated = false;
    if (_step <= 1) _householdsValidated = false;
    if (_step <= 2) _usageValidated = false;
    _bill = null;
    _allocation = null;
  }

  Future<void> _selectTab(int step) async {
    if (_saving || !_canVisit(step)) return;
    if (_step == 4 && step < 4) {
      final confirmed = await _confirm(
        'Revisit calculation?',
        'You can review earlier inputs, but changing them will invalidate the current results. You will need to calculate again to update the totals.',
        'Continue',
      );
      if (!confirmed || !mounted) return;
    }
    _go(step);
  }

  Future<void> _back() async {
    if (_saving) return;
    if (_step == 4) {
      await _selectTab(3);
    } else if (_step > 0) {
      _go(_step - 1);
    } else {
      await _returnHome();
    }
  }

  void _next() {
    final errors = switch (_step) {
      0 => _draft.validateDetails(),
      1 => _draft.validateHouseholds(),
      2 => _draft.validateUsage(),
      3 => {
        ..._draft.validateDetails(),
        ..._draft.validateHouseholds(),
        ..._draft.validateUsage(),
      },
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
    if (_step == 0) _detailsValidated = true;
    if (_step == 1) {
      _householdsValidated = true;
      for (final household in _draft.households) {
        household.prepareOccupants();
      }
    }
    if (_step == 2) _usageValidated = true;
    if (_step == 3) {
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
            'Combined measured usage must not exceed ${formatQuantity(bill.totalConsumption!)} ${_draft.category.unit}.';
        final usageErrors = <String, String>{'usage': message};
        for (var h = 0; h < _draft.households.length; h++) {
          final household = _draft.households[h];
          for (var o = 0; o < household.count!; o++) {
            if (household.occupants[o].measured.trim().isNotEmpty) {
              usageErrors['h$h.o$o.measured'] = message;
            }
          }
        }
        setState(() {
          _errors = usageErrors;
          _usageValidated = false;
          _step = 2;
        });
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

  Future<bool> _confirmDiscard() async {
    if (_saving) return false;
    if (_savedCalculationIsCurrent || !_draft.hasMeaningfulInputs) return true;
    return _confirm(
      'Discard this calculation?',
      'Leave this calculation and discard its unsaved inputs and results?',
      'Discard',
    );
  }

  Map<String, Object?> _currentSnapshot() {
    final bill = _bill!;
    final allocation = _allocation!;
    return {
      'category': _draft.category.name,
      'totalAmountCents': bill.totalAmountCents,
      'billingStart': _draft.periodStart,
      'billingEnd': _draft.periodEnd,
      'allocationMethod': _draft.method.name,
      'totalConsumption': bill.totalConsumption,
      'draftTotalConsumption': _draft.consumption,
      'households': [
        for (var h = 0; h < bill.households.length; h++)
          {
            'name': bill.households[h].name,
            'occupantCount': bill.households[h].occupants.length,
            'amountCents': allocation.households[h].amountCents,
            'occupants': [
              for (var o = 0; o < bill.households[h].occupants.length; o++)
                {
                  'occupancyDays':
                      bill.households[h].occupants[o].occupancyDays,
                  'measuredConsumption':
                      bill.households[h].occupants[o].measuredConsumption,
                  'draftMeasured': _draft.households[h].occupants[o].measured,
                  'mode': _draft.households[h].occupants[o].mode.name,
                  'manualDays':
                      _draft.households[h].occupants[o].mode ==
                          OccupancyMode.manualDays
                      ? _draft.households[h].occupants[o].days
                      : null,
                  'ranges':
                      _draft.households[h].occupants[o].mode ==
                          OccupancyMode.dateRanges
                      ? [
                          for (final range
                              in _draft.households[h].occupants[o].ranges)
                            {'start': range.start, 'end': range.end},
                        ]
                      : const [],
                  'amountCents': allocation.households[h].occupants == null
                      ? null
                      : allocation.households[h].occupants![o].amountCents,
                },
            ],
          },
      ],
    };
  }

  String _currentSignature() => jsonEncode(_currentSnapshot());

  bool get _savedCalculationIsCurrent =>
      _savedRecordId != null &&
      _savedSignature != null &&
      _allocation != null &&
      _savedSignature == _currentSignature();

  void _message(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _monthLabel(int year, int month) {
    const names = [
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
    return '${names[month - 1]} $year';
  }

  Future<bool> _confirmReplacement(SavedBillRecord existing) {
    final category = BillCategory.values
        .firstWhere((value) => value.name == existing.category)
        .label;
    return _confirm(
      'Replace existing bill?',
      'A bill for $category in ${_monthLabel(existing.assignedYear, existing.assignedMonth)} is already saved. Replacing it will permanently overwrite the existing bill details and calculations. This action cannot be undone.',
      'Replace',
    );
  }

  Future<void> _save({bool exitAfterSuccess = false}) async {
    if (_saving) return;
    if (_bill == null || _allocation == null || !_canVisit(4)) {
      _message('Calculate this bill again before saving.');
      return;
    }
    setState(() => _saving = true);
    try {
      final snapshot = _currentSnapshot();
      final signature = jsonEncode(snapshot);
      if (_savedCalculationIsCurrent) {
        _message('Already saved.');
        if (exitAfterSuccess && mounted) widget.onHome();
        return;
      }

      final start = parseDate(_draft.periodStart);
      final end = parseDate(_draft.periodEnd);
      if (start == null || end == null || end.isBefore(start)) {
        _message('The billing period is invalid. Correct it before saving.');
        return;
      }
      final assigned = assignBillingMonth(start, end);
      final existing = await widget.repository.find(
        _draft.category.name,
        assigned.year,
        assigned.month,
      );
      if (!mounted) return;

      final mustConfirm = existing != null
          ? existing.id != _savedRecordId || signature != _savedSignature
          : _savedRecordId != null && signature != _savedSignature;
      if (mustConfirm) {
        final confirmed = existing != null
            ? await _confirmReplacement(existing)
            : await _confirm(
                'Update saved bill?',
                'This saved calculation has changed. Updating it will replace its previously saved details and calculations.',
                'Update',
              );
        if (!confirmed || !mounted) return;
      }

      final candidate = SavedBillRecord.create(
        category: _draft.category.name,
        assignedMonth: assigned,
        startDate: _draft.periodStart,
        endDate: _draft.periodEnd,
        snapshot: snapshot,
        id: _savedRecordId,
        createdAt: _savedCreatedAt,
      );
      var result = await widget.repository.save(
        candidate,
        movingRecordId: _savedRecordId,
        replaceRecordId: mustConfirm ? existing?.id : null,
      );
      if (!mounted) return;
      if (result.conflict case final conflict?) {
        if (!await _confirmReplacement(conflict) || !mounted) return;
        result = await widget.repository.save(
          candidate,
          movingRecordId: _savedRecordId,
          replaceRecordId: conflict.id,
        );
      }
      if (!result.succeeded) {
        _message(
          'A saved bill changed while saving. Review the conflict and retry.',
        );
        return;
      }
      final saved = result.record!;
      _savedRecordId = saved.id;
      _savedCreatedAt = saved.createdAt;
      _savedSignature = signature;
      _message('Bill saved successfully.');
      if (exitAfterSuccess && mounted) widget.onHome();
    } catch (_) {
      if (mounted) {
        _message(
          'The bill could not be saved. Your calculation is still available; try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _exitResults() async {
    if (_savedCalculationIsCurrent) {
      widget.onHome();
      return;
    }
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save before exiting?'),
        content: const Text(
          'This calculation has not been saved, or has changed since it was saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            child: const Text('Exit Without Saving'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: const Text('Save & Exit'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'discard') {
      widget.onHome();
    } else if (action == 'save') {
      await _save(exitAfterSuccess: true);
    }
  }

  Future<void> _shareResults() async {
    if (_saving || _sharing) return;
    if (_bill == null || _allocation == null || !_canVisit(4)) {
      _message('Calculate this bill again before sharing.');
      return;
    }
    setState(() => _sharing = true);
    try {
      await shareBillCard(
        context,
        ShareBillCardData.fromCalculation(
          category: _draft.category,
          startDate: _draft.periodStart,
          endDate: _draft.periodEnd,
          bill: _bill!,
          allocation: _allocation!,
        ),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _returnHome() async {
    if (!await _confirmDiscard() || !mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    widget.onHome();
  }

  Future<void> _warnForOverlap(String start, String end) async {
    final request = ++_overlapRequest;
    final parsedStart = parseDate(start);
    final parsedEnd = parseDate(end);
    if (parsedStart == null ||
        parsedEnd == null ||
        parsedEnd.isBefore(parsedStart)) {
      return;
    }
    final key = '${_draft.category.name}:$start:$end';
    if (_acknowledgedOverlap == key) return;
    try {
      final overlaps = await widget.repository.overlapping(
        category: _draft.category.name,
        startDate: start,
        endDate: end,
        excludeId: _savedRecordId,
      );
      if (!mounted ||
          request != _overlapRequest ||
          _draft.periodStart != start ||
          _draft.periodEnd != end ||
          overlaps.isEmpty) {
        return;
      }
      final continueAnyway = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Overlapping billing period'),
          content: const Text(
            'This billing period overlaps a previously saved bill for the same category. Some dates may be covered by both calculations.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Change Dates'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continue Anyway'),
            ),
          ],
        ),
      );
      if (continueAnyway == true && mounted) _acknowledgedOverlap = key;
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved bills could not be checked for overlap.'),
        ),
      );
    }
  }

  Future<void> _clearHouseholds() async {
    final meaningful =
        _draft.households.length != 1 ||
        _draft.households.single.name != 'Household 1' ||
        _draft.households.single.headcount != '1' ||
        _draft.households.single.occupants.any(_occupantHasUsage);
    if (meaningful &&
        !await _confirm(
          'Clear households?',
          'Reset households and their occupant inputs?',
          'Clear',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _draft.households
        ..clear()
        ..add(HouseholdDraft(name: 'Household 1'));
      _errors.clear();
      _changed();
    });
  }

  bool _occupantHasUsage(OccupantDraft occupant) =>
      occupant.measured.isNotEmpty ||
      occupant.days.isNotEmpty ||
      occupant.mode != OccupancyMode.fullPeriod ||
      occupant.ranges.any(
        (range) => range.start.isNotEmpty || range.end.isNotEmpty,
      );

  Future<void> _clearUsage() async {
    final meaningful = _draft.households.any(
      (household) => household.occupants.any(_occupantHasUsage),
    );
    if (meaningful &&
        !await _confirm(
          'Clear usage?',
          'Reset all occupant usage and duration inputs?',
          'Clear',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      for (final household in _draft.households) {
        household.clearUsage();
      }
      _errors.clear();
      _changed();
    });
  }

  Widget _householdSection(int h, List<Widget> children, {Widget? action}) {
    final household = _draft.households[h];
    final index = _accentIndices.putIfAbsent(household, () => _nextAccent++);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final palette = dark
        ? [
            Colors.teal.shade300,
            Colors.blue.shade300,
            Colors.purple.shade300,
            Colors.orange.shade300,
            Colors.pink.shade300,
            Colors.indigo.shade300,
          ]
        : [
            Colors.teal.shade700,
            Colors.blue.shade700,
            Colors.purple.shade700,
            Colors.orange.shade800,
            Colors.pink.shade700,
            Colors.indigo.shade700,
          ];
    return HouseholdSection(
      key: ObjectKey(household),
      name: household.name.trim().isEmpty
          ? 'Household ${h + 1}'
          : household.name.trim(),
      accent: palette[index % palette.length],
      action: action,
      children: children,
    );
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
      onChanged: (text) => setState(() {
        update(text);
        _changed();
        _errors.remove(id);
      }),
    ),
  );

  Widget _range(
    String id,
    String startId,
    String endId,
    String start,
    String end,
    void Function(String start, String end) update, {
    bool billing = false,
  }) => DateRangeFields(
    id: id,
    startId: startId,
    endId: endId,
    start: start,
    end: end,
    startLabel: billing ? 'Period start' : 'Range start',
    endLabel: billing ? 'Period end' : 'Range end',
    startError: _errors[startId],
    endError: _errors[endId],
    firstDate: billing ? null : parseDate(_draft.periodStart),
    lastDate: billing ? null : parseDate(_draft.periodEnd),
    pickerLabel: billing ? 'Choose Billing Period' : 'Choose occupancy dates',
    showManualFields: !billing,
    onChanged: (from, to) {
      final changed = from != start || to != end;
      setState(() {
        update(from, to);
        _changed();
        _errors.remove(startId);
        _errors.remove(endId);
      });
      if (billing && changed) unawaited(_warnForOverlap(from, to));
    },
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
        if (item != null) {
          setState(() {
            update(item);
            _changed();
          });
        }
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

  static const _tabLabels = [
    'Details',
    'Households',
    'Usage',
    'Review',
    'Results',
  ];

  Widget _workflowTabs() => LayoutBuilder(
    builder: (context, constraints) {
      final colors = Theme.of(context).colorScheme;
      final textScaler = MediaQuery.textScalerOf(context);
      final scrollTabs =
          constraints.maxWidth < 360 || textScaler.scale(12) > 15;
      final tabWidth = textScaler.scale(12) > 15
          ? textScaler.scale(12) * 8.5
          : 80.0;
      final tabs = [
        for (var i = 0; i < _tabLabels.length; i++) _workflowTab(i, colors),
      ];
      return Material(
        color: colors.surface,
        child: scrollTabs
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final tab in tabs)
                      SizedBox(width: tabWidth, child: tab),
                  ],
                ),
              )
            : Row(children: [for (final tab in tabs) Expanded(child: tab)]),
      );
    },
  );

  Widget _workflowTab(int index, ColorScheme colors) {
    final selected = _step == index;
    final enabled = _canVisit(index);
    final label = _tabLabels[index];
    return Semantics(
      key: ValueKey('tab-$label'),
      label: label,
      selected: selected,
      enabled: enabled,
      button: true,
      excludeSemantics: true,
      child: InkWell(
        onTap: enabled ? () => _selectTab(index) : null,
        child: SizedBox(
          height: 48,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text(
                      label,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: !enabled
                            ? colors.onSurface.withAlpha(100)
                            : selected
                            ? colors.primary
                            : colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
              Container(
                key: ValueKey('tab-indicator-$label'),
                height: 3,
                width: double.infinity,
                color: selected ? colors.primary : Colors.transparent,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Text(text, style: Theme.of(context).textTheme.titleLarge),
  );

  List<Widget> _details() => [
    _heading(_draft.category.label),
    const Padding(
      padding: EdgeInsets.only(bottom: 24),
      child: Text(
        'Your draft stays here while you move between steps; it is not saved when the app closes.',
      ),
    ),
    _dropdown(
      'method',
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
    _range(
      'period',
      'periodStart',
      'periodEnd',
      _draft.periodStart,
      _draft.periodEnd,
      (start, end) {
        _draft.periodStart = start;
        _draft.periodEnd = end;
      },
      billing: true,
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
      _householdSection(
        h,
        [
          _field(
            'h$h.name',
            'Household name',
            _draft.households[h].name,
            (text) => _draft.households[h].name = text,
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Number of Occupants',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                Semantics(
                  label: 'Occupants, ${_draft.households[h].count ?? 0}',
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        key: ValueKey('h$h.headcount.decrement'),
                        tooltip: 'Decrease occupants',
                        onPressed: (_draft.households[h].count ?? 0) <= 0
                            ? null
                            : () => setState(() {
                                final household = _draft.households[h];
                                household.headcount = '${household.count! - 1}';
                                _errors.remove('h$h.headcount');
                                _changed();
                              }),
                        icon: const Icon(Icons.remove),
                      ),
                      SizedBox(
                        width: 48,
                        child: Text(
                          '${_draft.households[h].count ?? 0}',
                          key: ValueKey('h$h.headcount.value'),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        key: ValueKey('h$h.headcount.increment'),
                        tooltip: 'Increase occupants',
                        onPressed:
                            (_draft.households[h].count ?? 0) >=
                                HouseholdDraft.maxOccupants
                            ? null
                            : () => setState(() {
                                final household = _draft.households[h];
                                household.headcount =
                                    '${(household.count ?? 0) + 1}';
                                household.prepareOccupants();
                                _errors.remove('h$h.headcount');
                                _changed();
                              }),
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_errors['h$h.headcount'] != null)
            Text(
              _errors['h$h.headcount']!,
              key: ValueKey('h$h.headcount.error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
              textAlign: TextAlign.center,
            ),
        ],
        action: _draft.households.length <= 1
            ? null
            : IconButton(
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
                    _changed();
                  });
                },
              ),
      ),
    OutlinedButton.icon(
      key: const ValueKey('addHousehold'),
      onPressed: () => setState(() {
        _draft.households.add(
          HouseholdDraft(name: 'Household ${_draft.households.length + 1}'),
        );
        _changed();
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
    for (var h = 0; h < _draft.households.length; h++)
      _householdSection(h, [
        for (var o = 0; o < _draft.households[h].count!; o++)
          _occupantFields(h, o),
      ]),
  ];

  Widget _occupantFields(int h, int o) {
    final occupant = _draft.households[h].occupants[o];
    final key = 'h$h.o$o';
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: _card([
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            'Occupant ${o + 1}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
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
                      _changed();
                    }),
                  ),
              ],
            ),
            _range(
              '$key.r$r',
              '$key.r$r.start',
              '$key.r$r.end',
              occupant.ranges[r].start,
              occupant.ranges[r].end,
              (start, end) {
                occupant.ranges[r].start = start;
                occupant.ranges[r].end = end;
              },
            ),
          ],
          OutlinedButton.icon(
            key: ValueKey('$key.addRange'),
            onPressed: () => setState(() {
              occupant.ranges.add(OccupancyRangeDraft());
              _changed();
            }),
            icon: const Icon(Icons.add),
            label: const Text('Add date range'),
          ),
        ],
      ]),
    );
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
    padding: const EdgeInsets.fromLTRB(12, 8, 0, 8),
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
              : 'Measured usage: ${formatQuantity(input.measuredConsumption!)} ${_draft.category.unit}',
        ),
      ],
    ),
  );

  List<Widget> _summary({required bool results}) {
    final bill = results ? _bill! : _draft.toBill();
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
            'Total consumption: ${formatQuantity(bill.totalConsumption!)} ${_draft.category.unit}',
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
        _householdSection(h, [
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
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _back();
    },
    child: Scaffold(
      appBar: AppBar(
        leading: AppMenu(
          version: widget.version,
          repository: widget.repository,
          confirmExit: _confirmDiscard,
          darkMode: widget.darkMode,
          onDarkModeChanged: widget.onDarkModeChanged,
          hasActiveDraft: true,
          onDataReset: widget.onHome,
        ),
        actions: [
          IconButton(
            tooltip: 'Back',
            onPressed: _back,
            icon: const Icon(Icons.arrow_back),
          ),
          IconButton(
            key: const ValueKey('goHome'),
            tooltip: 'Home',
            onPressed: _returnHome,
            icon: const Icon(Icons.home_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _workflowTabs(),
            Expanded(
              child: SingleChildScrollView(
                key: ValueKey('step$_step'),
                controller: _scroll,
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
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
            if (_step != 4) ...[
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('back'),
                  onPressed: _back,
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(width: 8),
              if (_step == 1 || _step == 2) ...[
                Expanded(
                  child: TextButton(
                    key: const ValueKey('clear'),
                    onPressed: _step == 1 ? _clearHouseholds : _clearUsage,
                    child: const Text('Clear'),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: FilledButton(
                  key: const ValueKey('next'),
                  onPressed: _next,
                  child: Text(_step == 3 ? 'Calculate' : 'Next'),
                ),
              ),
            ] else ...[
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('save'),
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('share'),
                  onPressed: _saving || _sharing ? null : _shareResults,
                  child: _sharing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Share'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('exit'),
                  onPressed: _saving ? null : _exitResults,
                  child: const Text('Exit'),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

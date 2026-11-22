import 'package:material_ui/material_ui.dart';

Future<DateTimeRange?> showAccessibleDateRangePicker({
  required BuildContext context,
  required DateTime firstDate,
  required DateTime lastDate,
  required String title,
  DateTimeRange? initialDateRange,
}) => showDialog<DateTimeRange>(
  context: context,
  useSafeArea: true,
  builder: (_) => _AccessibleDateRangeDialog(
    firstDate: DateUtils.dateOnly(firstDate),
    lastDate: DateUtils.dateOnly(lastDate),
    title: title,
    initialDateRange: initialDateRange,
  ),
);

class _AccessibleDateRangeDialog extends StatefulWidget {
  const _AccessibleDateRangeDialog({
    required this.firstDate,
    required this.lastDate,
    required this.title,
    this.initialDateRange,
  });

  final DateTime firstDate;
  final DateTime lastDate;
  final String title;
  final DateTimeRange? initialDateRange;

  @override
  State<_AccessibleDateRangeDialog> createState() =>
      _AccessibleDateRangeDialogState();
}

class _AccessibleDateRangeDialogState
    extends State<_AccessibleDateRangeDialog> {
  late DateTime? _start = widget.initialDateRange?.start;
  late DateTime? _end = widget.initialDateRange?.end;
  late DateTime _focus = _end ?? _start ?? DateTime.now();

  bool get _complete =>
      _start != null && _end != null && !_end!.isBefore(_start!);

  void _select(DateTime value) {
    final date = DateUtils.dateOnly(value);
    setState(() {
      if (_start == null || _end != null || date.isBefore(_start!)) {
        _start = date;
        _end = null;
      } else {
        _end = date;
      }
      _focus = date;
    });
  }

  String _date(DateTime? value) {
    if (value == null) return 'Select';
    return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
  }

  void _confirm() {
    if (!_complete) return;
    Navigator.of(context).pop(DateTimeRange(start: _start!, end: _end!));
  }

  Widget _calendar() => CalendarDatePicker(
    key: ValueKey('${_focus.year}-${_focus.month}-${_focus.day}'),
    initialDate: _focus.isBefore(widget.firstDate)
        ? widget.firstDate
        : _focus.isAfter(widget.lastDate)
        ? widget.lastDate
        : _focus,
    firstDate: widget.firstDate,
    lastDate: widget.lastDate,
    onDateChanged: _select,
  );

  Widget _selectionSummary(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Semantics(
          liveRegion: true,
          label: 'Selected dates: ${_date(_start)} to ${_date(_end)}',
          child: Text(
            '${_date(_start)}  –  ${_date(_end)}',
            key: const ValueKey('dateRangeSelectionSummary'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _start == null || _end != null
              ? 'Select a start date, then an end date.'
              : 'Now select an end date.',
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );

  Widget _actions(BuildContext context, {required bool fullScreen}) => Padding(
    padding: EdgeInsets.fromLTRB(16, 8, 16, fullScreen ? 16 : 12),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 56,
          child: FilledButton(
            key: const ValueKey('dateRangeConfirm'),
            onPressed: _complete ? _confirm : null,
            child: const Text('OK'),
          ),
        ),
        const SizedBox(height: 4),
        TextButton(
          key: const ValueKey('dateRangeCancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final fullScreen =
        media.size.width < 440 || media.textScaler.scale(14) > 21;
    if (fullScreen) {
      return Scaffold(
        appBar: AppBar(
          leading: CloseButton(onPressed: () => Navigator.of(context).pop()),
          title: Text(widget.title),
        ),
        body: SafeArea(
          child: Column(
            children: [
              _selectionSummary(context),
              Expanded(
                child: SingleChildScrollView(child: Center(child: _calendar())),
              ),
              _actions(context, fullScreen: true),
            ],
          ),
        ),
      );
    }

    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: media.size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _selectionSummary(context),
            Flexible(
              child: SingleChildScrollView(child: Center(child: _calendar())),
            ),
            _actions(context, fullScreen: false),
          ],
        ),
      ),
    );
  }
}

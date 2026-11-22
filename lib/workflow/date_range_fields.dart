import 'package:material_ui/material_ui.dart';

import 'bill_draft.dart';

/// One range picker with manual fields retained as an alternative.
class DateRangeFields extends StatefulWidget {
  const DateRangeFields({
    super.key,
    required this.id,
    required this.startId,
    required this.endId,
    required this.start,
    required this.end,
    required this.onChanged,
    this.startLabel = 'Range start',
    this.endLabel = 'Range end',
    this.startError,
    this.endError,
    this.firstDate,
    this.lastDate,
    this.pickerLabel = 'Choose occupancy dates',
  });

  final String id;
  final String startId;
  final String endId;
  final String start;
  final String end;
  final String startLabel;
  final String endLabel;
  final String? startError;
  final String? endError;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final String pickerLabel;
  final void Function(String start, String end) onChanged;

  @override
  State<DateRangeFields> createState() => _DateRangeFieldsState();
}

class _DateRangeFieldsState extends State<DateRangeFields> {
  late final _start = TextEditingController(text: widget.start);
  late final _end = TextEditingController(text: widget.end);

  @override
  void didUpdateWidget(DateRangeFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.start != oldWidget.start && _start.text != widget.start) {
      _start.text = widget.start;
    }
    if (widget.end != oldWidget.end && _end.text != widget.end) {
      _end.text = widget.end;
    }
  }

  @override
  void dispose() {
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final first = DateUtils.dateOnly(widget.firstDate ?? DateTime(1));
    final last = DateUtils.dateOnly(widget.lastDate ?? DateTime(9999, 12, 31));
    final parsedStart = parseDate(_start.text);
    final parsedEnd = parseDate(_end.text);
    final start = parsedStart == null ? null : DateUtils.dateOnly(parsedStart);
    final end = parsedEnd == null ? null : DateUtils.dateOnly(parsedEnd);
    final valid =
        start != null &&
        end != null &&
        !end.isBefore(start) &&
        !start.isBefore(first) &&
        !end.isAfter(last);
    final selected = await showDateRangePicker(
      context: context,
      firstDate: first,
      lastDate: last,
      initialDateRange: valid ? DateTimeRange(start: start, end: end) : null,
      helpText: widget.pickerLabel,
      saveText: 'Use dates',
      // The standard header uses a non-flexible start-date label. A compact
      // headline fits narrow screens with large text without limiting scaling.
      builder: (context, child) => DatePickerTheme(
        data: DatePickerTheme.of(context).copyWith(
          rangePickerHeaderHeadlineStyle: Theme.of(context)
              .textTheme
              .titleMedium,
        ),
        child: child!,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _start.text = dateText(selected.start);
      _end.text = dateText(selected.end);
    });
    widget.onChanged(_start.text, _end.text);
  }

  Widget _field(
    String id,
    String label,
    TextEditingController controller,
    String? error,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      key: ValueKey(id),
      controller: controller,
      keyboardType: TextInputType.datetime,
      decoration: InputDecoration(
        labelText: label,
        hintText: 'YYYY-MM-DD',
        errorText: error,
      ),
      onChanged: (_) => widget.onChanged(_start.text, _end.text),
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      OutlinedButton.icon(
        key: ValueKey('${widget.id}.pickDates'),
        onPressed: _pick,
        icon: const Icon(Icons.date_range_outlined),
        label: Text(widget.pickerLabel),
      ),
      const SizedBox(height: 16),
      _field(widget.startId, widget.startLabel, _start, widget.startError),
      _field(widget.endId, widget.endLabel, _end, widget.endError),
    ],
  );
}

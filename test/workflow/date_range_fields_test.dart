import 'package:basic_bill_splitter/workflow/bill_draft.dart';
import 'package:basic_bill_splitter/workflow/date_range_fields.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<ValueNotifier<(String, String)>> pumpRange(
    WidgetTester tester, {
    String start = '2026-11-02',
    String end = '2026-11-04',
    bool showManualFields = true,
  }) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final values = ValueNotifier((start, end));
    addTearDown(values.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: ValueListenableBuilder(
                valueListenable: values,
                builder: (context, pair, child) => DateRangeFields(
                  id: 'range',
                  showManualFields: showManualFields,
                  startId: 'start',
                  endId: 'end',
                  start: pair.$1,
                  end: pair.$2,
                  firstDate: DateTime.utc(2026, 11, 1),
                  lastDate: DateTime.utc(2026, 11, 30),
                  onChanged: (start, end) => values.value = (start, end),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return values;
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('range.pickDates')));
    await tester.pumpAndSettle();
    expect(find.byType(DateRangePickerDialog), findsOneWidget);
  }

  Future<void> choose(WidgetTester tester, String start, String end) async {
    await tester.tap(find.text(start).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(end).first);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'billing summary is read-only, accessible and updates after edits',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final values = await pumpRange(tester, showManualFields: false);
        expect(find.byType(TextFormField), findsNothing);
        final summary = find.byKey(const ValueKey('range.summary'));
        expect(tester.widget<Text>(summary).data, '02 Nov 2026 - 04 Nov 2026');
        expect(
          tester.getSemantics(summary),
          matchesSemantics(
            label: 'Billing period\n02 Nov 2026 - 04 Nov 2026',
            textDirection: TextDirection.ltr,
          ),
        );
        await open(tester);
        await choose(tester, '10', '12');
        await tester.tap(find.text('Use dates'));
        await tester.pumpAndSettle();
        expect(values.value, ('2026-11-10', '2026-11-12'));
        expect(find.text('10 Nov 2026 - 12 Nov 2026'), findsOneWidget);
        await open(tester);
        final dialog = tester.widget<DateRangePickerDialog>(
          find.byType(DateRangePickerDialog),
        );
        expect(dialog.initialDateRange!.start, DateTime(2026, 11, 10));
        expect(dialog.initialDateRange!.end, DateTime(2026, 11, 12));
        await choose(tester, '14', '14');
        await tester.tap(find.text('Use dates'));
        await tester.pumpAndSettle();
        expect(values.value, ('2026-11-14', '2026-11-14'));
        expect(find.text('14 Nov 2026 - 14 Nov 2026'), findsOneWidget);
        await open(tester);
        await choose(tester, '16', '17');
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        expect(values.value, ('2026-11-14', '2026-11-14'));
        expect(find.text('14 Nov 2026 - 14 Nov 2026'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('one calendar selects both dates and edits the existing pair', (
    tester,
  ) async {
    final values = await pumpRange(tester);
    await open(tester);
    var dialog = tester.widget<DateRangePickerDialog>(
      find.byType(DateRangePickerDialog),
    );
    expect(dialog.firstDate, DateTime(2026, 11, 1));
    expect(dialog.lastDate, DateTime(2026, 11, 30));
    expect(dialog.initialDateRange!.start, DateTime(2026, 11, 2));
    expect(dialog.initialDateRange!.end, DateTime(2026, 11, 4));
    await choose(tester, '10', '12');
    await tester.tap(find.text('Use dates'));
    await tester.pumpAndSettle();
    expect(values.value, ('2026-11-10', '2026-11-12'));
    expect(
      inclusiveDays(parseDate(values.value.$1)!, parseDate(values.value.$2)!),
      3,
    );
    await open(tester);
    dialog = tester.widget<DateRangePickerDialog>(
      find.byType(DateRangePickerDialog),
    );
    expect(dialog.initialDateRange!.start, DateTime(2026, 11, 10));
    expect(dialog.initialDateRange!.end, DateTime(2026, 11, 12));
    await choose(tester, '14', '14');
    await tester.tap(find.text('Use dates'));
    await tester.pumpAndSettle();
    expect(values.value, ('2026-11-14', '2026-11-14'));
    expect(
      inclusiveDays(parseDate(values.value.$1)!, parseDate(values.value.$2)!),
      1,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'cancel leaves the original dates intact after calendar selection',
    (tester) async {
      final values = await pumpRange(tester);
      await open(tester);
      await choose(tester, '10', '12');
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(values.value, ('2026-11-02', '2026-11-04'));
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('start')))
            .controller!
            .text,
        '2026-11-02',
      );
    },
  );

  testWidgets(
    'manual entries and out-of-period values are never clamped on cancellation',
    (tester) async {
      final values = await pumpRange(
        tester,
        start: '2026-10-31',
        end: 'invalid date',
      );
      await open(tester);
      final dialog = tester.widget<DateRangePickerDialog>(
        find.byType(DateRangePickerDialog),
      );
      expect(dialog.initialDateRange, isNull);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(values.value, ('2026-10-31', 'invalid date'));
      await tester.enterText(find.byKey(const ValueKey('start')), '2026-11-07');
      await tester.enterText(find.byKey(const ValueKey('end')), '2026-11-30');
      await tester.pumpAndSettle();
      await open(tester);
      final updated = tester.widget<DateRangePickerDialog>(
        find.byType(DateRangePickerDialog),
      );
      expect(updated.initialDateRange!.end, DateTime(2026, 11, 30));
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(values.value, ('2026-11-07', '2026-11-30'));
    },
  );
}

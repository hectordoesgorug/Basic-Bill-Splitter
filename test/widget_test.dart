import 'package:basic_bill_splitter/calculation/bill_models.dart';
import 'package:basic_bill_splitter/main.dart';
import 'package:basic_bill_splitter/workflow/bill_draft.dart';
import 'package:basic_bill_splitter/workflow/bill_workflow.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

BillDraft validDraft() => BillDraft(today: DateTime(2026, 11, 1))
  ..amount = '1000.00'
  ..consumption = '100';

Future<void> pumpDraft(WidgetTester tester, BillDraft draft) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: BillWorkflow(draft: draft),
    ),
  );
}

Future<void> enter(WidgetTester tester, String key, String text) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.enterText(finder, text);
  await tester.pump();
}

Future<void> next(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('next')));
  await tester.pumpAndSettle();
}

Future<void> back(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('back')));
  await tester.pumpAndSettle();
}

Future<void> select(WidgetTester tester, String key, String label) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('app opens bill details with Material 3', (tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.text('Bill Details'), findsOneWidget);
    expect(find.text('Basic Bill Splitter'), findsOneWidget);
    expect(
      Theme.of(tester.element(find.byType(BillWorkflow))).useMaterial3,
      isTrue,
    );
    expect(find.text('Flutter Demo'), findsNothing);
  });

  testWidgets('bill details reject invalid fields before continuing', (
    tester,
  ) async {
    await pumpDraft(tester, validDraft());
    await enter(tester, 'amount', '1.999');
    await enter(tester, 'periodEnd', '2026-10-01');
    await enter(tester, 'consumption', '0');
    await next(tester);
    expect(find.text('Bill Details'), findsOneWidget);
    expect(find.textContaining('at most 2 decimal places'), findsOneWidget);
    expect(find.textContaining('on or after the start date'), findsOneWidget);
    expect(find.textContaining('greater than zero'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('categories choose defaults and permit a one-bill override', (
    tester,
  ) async {
    final draft = validDraft();
    await pumpDraft(tester, draft);
    for (final category in BillCategory.values.skip(1)) {
      await select(tester, 'category', category.label);
      expect(draft.method, category.defaultMethod);
      final method = tester.widget<DropdownButtonFormField<AllocationMethod>>(
        find.byKey(ValueKey('method-${category.name}')),
      );
      expect(method.initialValue, category.defaultMethod);
    }
    await select(tester, 'method-miscellaneous', 'Person-days');
    expect(draft.method, AllocationMethod.personDays);
    expect(draft.amount, '1000.00');
    expect(BillDraft().method, AllocationMethod.hybrid);
  });

  testWidgets(
    'hybrid form integrates with engine and preserves backward edits',
    (tester) async {
      final draft = validDraft();
      await pumpDraft(tester, draft);
      await next(tester);
      await enter(tester, 'h0.name', 'Apartment A');
      await tester.ensureVisible(find.byKey(const ValueKey('addHousehold')));
      await tester.tap(find.byKey(const ValueKey('addHousehold')));
      await tester.pumpAndSettle();
      await enter(tester, 'h1.name', 'Apartment B');
      await next(tester);
      expect(find.text('Usage & Duration'), findsOneWidget);
      await enter(tester, 'h0.o0.measured', '20');
      await select(tester, 'h0.o0.mode', 'Manual days');
      await enter(tester, 'h0.o0.days', '30');
      await select(tester, 'h1.o0.mode', 'Manual days');
      await enter(tester, 'h1.o0.days', '10');
      await next(tester);
      expect(find.text('Review'), findsOneWidget);
      expect(find.text('Apartment A'), findsOneWidget);
      await next(tester);
      expect(find.text('Results'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('householdTotal0'))).data,
        '₱800.00',
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('householdTotal1'))).data,
        '₱200.00',
      );
      expect(find.text('Occupant 1 · ₱800.00'), findsOneWidget);
      expect(find.text('Occupant 1 · ₱200.00'), findsOneWidget);

      await back(tester); // Review
      await back(tester); // Usage
      expect(draft.households[0].occupants[0].measured, '20');
      await enter(tester, 'h0.o0.measured', '0');
      await next(tester);
      await next(tester);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('householdTotal0'))).data,
        '₱750.00',
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('householdTotal1'))).data,
        '₱250.00',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('aggregate measured usage has field-level engine errors', (
    tester,
  ) async {
    final draft = validDraft();
    await pumpDraft(tester, draft);
    await next(tester);
    await next(tester);
    await enter(tester, 'h0.o0.measured', '101');
    await next(tester);
    expect(find.text('Usage & Duration'), findsOneWidget);
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('h0.o0.measured')),
        matching: find.byType(TextField),
      ),
    );
    expect(field.decoration?.errorText, contains('must not exceed 100'));
    await enter(tester, 'h0.o0.measured', '100');
    await next(tester);
    expect(find.text('Review'), findsOneWidget);
  });

  testWidgets('headcount and duration errors stay at their step', (
    tester,
  ) async {
    await pumpDraft(tester, validDraft());
    await next(tester);
    await enter(tester, 'h0.name', '');
    await enter(tester, 'h0.headcount', '0');
    await next(tester);
    expect(find.text('Households'), findsOneWidget);
    expect(find.text('Enter a household name.'), findsOneWidget);
    expect(find.textContaining('whole number from 1 to 100'), findsOneWidget);
    await enter(tester, 'h0.name', 'A');
    await enter(tester, 'h0.headcount', '1');
    await next(tester);
    await select(tester, 'h0.o0.mode', 'Manual days');
    await enter(tester, 'h0.o0.days', '31');
    await next(tester);
    expect(find.text('Enter whole days from 1 to 30.'), findsOneWidget);
  });

  testWidgets('date ranges count inclusively and reject shared dates', (
    tester,
  ) async {
    final draft = validDraft();
    await pumpDraft(tester, draft);
    await next(tester);
    await next(tester);
    await select(tester, 'h0.o0.mode', 'Date ranges');
    await enter(tester, 'h0.o0.r0.start', '2026-11-01');
    await enter(tester, 'h0.o0.r0.end', '2026-11-05');
    await tester.ensureVisible(find.byKey(const ValueKey('h0.o0.addRange')));
    await tester.tap(find.byKey(const ValueKey('h0.o0.addRange')));
    await tester.pumpAndSettle();
    await enter(tester, 'h0.o0.r1.start', '2026-11-05');
    await enter(tester, 'h0.o0.r1.end', '2026-11-06');
    await next(tester);
    expect(find.textContaining('Ranges must not overlap'), findsOneWidget);
    await enter(tester, 'h0.o0.r1.start', '2026-11-06');
    await next(tester);
    expect(find.text('Review'), findsOneWidget);
    expect(find.textContaining('Date ranges · 6 days'), findsOneWidget);
    await back(tester);
    final field = find.descendant(
      of: find.byKey(const ValueKey('h0.o0.r1.start')),
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(field).controller.text, '2026-11-06');
  });

  testWidgets('equal household results show inputs without occupant money', (
    tester,
  ) async {
    final draft = validDraft()..selectCategory(BillCategory.miscellaneous);
    draft.households.single.headcount = '2';
    await pumpDraft(tester, draft);
    await next(tester);
    await next(tester);
    await next(tester);
    await next(tester);
    expect(find.text('Results'), findsOneWidget);
    expect(find.text('Occupant 1'), findsOneWidget);
    expect(find.text('Occupant 2'), findsOneWidget);
    expect(find.textContaining('Occupant 1 · ₱'), findsNothing);
    expect(
      find.textContaining('No individual monetary split is defined'),
      findsOneWidget,
    );
    expect(find.text('Full Period · 30 days'), findsNWidgets(2));
  });

  testWidgets(
    'system Back retains draft and new calculation requires confirmation',
    (tester) async {
      final draft = validDraft();
      await pumpDraft(tester, draft);
      await next(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Bill Details'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('amount')))
            .initialValue,
        '1000.00',
      );
      await next(tester);
      await next(tester);
      await next(tester);
      await next(tester);
      await next(tester);
      expect(find.text('Start a new calculation?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Results'), findsOneWidget);
      await next(tester);
      await tester.tap(find.text('Start new'));
      await tester.pumpAndSettle();
      expect(find.text('Bill Details'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('amount')))
            .initialValue,
        '',
      );
    },
  );

  testWidgets('navigation stays above the software keyboard', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await pumpDraft(tester, validDraft());
    final button = find.byKey(const ValueKey('next'));
    expect(tester.getBottomRight(button).dy, lessThanOrEqualTo(544));
    await next(tester);
    expect(find.text('Households'), findsOneWidget);
    expect(tester.getBottomRight(button).dy, lessThanOrEqualTo(544));
    expect(
      tester.getBottomRight(find.byKey(const ValueKey('back'))).dy,
      lessThanOrEqualTo(544),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone width and large text remain scrollable without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: BillWorkflow(draft: validDraft()),
      ),
    );
    await next(tester);
    await next(tester);
    await next(tester);
    await next(tester);
    expect(find.text('Results'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

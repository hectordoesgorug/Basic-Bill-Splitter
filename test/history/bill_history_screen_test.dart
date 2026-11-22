import 'package:basic_bill_splitter/app/home_screen.dart';
import 'package:basic_bill_splitter/storage/bill_repository.dart';
import 'package:basic_bill_splitter/storage/billing_period.dart';
import 'package:basic_bill_splitter/storage/saved_bill_record.dart';
import 'package:basic_bill_splitter/workflow/bill_draft.dart';
import 'package:basic_bill_splitter/workflow/bill_workflow.dart';
import 'package:basic_bill_splitter/history/bill_history_screen.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

SavedBillRecord savedBill({
  String id = 'bill',
  String category = 'electricity',
  int year = 2026,
  int month = 10,
  int amountCents = 10000,
  String householdName = 'Household 1',
  String method = 'personDays',
  String currencyCode = 'PHP',
}) {
  final start =
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-01';
  final end = start;
  return SavedBillRecord.create(
    category: category,
    assignedMonth: AssignedMonth(year, month),
    startDate: start,
    endDate: end,
    now: DateTime.utc(year, month, 2),
    snapshot: {
      'category': category,
      'totalAmountCents': amountCents,
      'billingStart': start,
      'billingEnd': end,
      'allocationMethod': method,
      'totalConsumption': null,
      'draftTotalConsumption': '',
      'households': [
        {
          'name': householdName,
          'occupantCount': 1,
          'amountCents': amountCents,
          'occupants': [
            {
              'occupancyDays': 1,
              'measuredConsumption': null,
              'draftMeasured': '',
              'mode': 'fullPeriod',
              'manualDays': null,
              'ranges': <Object?>[],
              'amountCents': method == 'equalPerHousehold' ? null : amountCents,
            },
          ],
        },
      ],
    },
    id: id,
    currencyCode: currencyCode,
  );
}

Future<void> add(BillRepository repository, SavedBillRecord record) async {
  await repository.save(record);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('History menu groups six categories and preserves a draft', (
    tester,
  ) async {
    final repository = InMemoryBillRepository();
    await add(repository, savedBill());
    final draft = BillDraft(today: DateTime(2026, 11, 1))..amount = '73.21';

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(initialDraft: draft, repository: repository),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('appMenu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    for (final category in BillCategory.values) {
      expect(
        find.byKey(ValueKey('historyCategory-${category.name}')),
        findsOneWidget,
      );
    }
    await tester.tap(find.byKey(const ValueKey('historyCategory-electricity')));
    await tester.pumpAndSettle();
    expect(find.byType(BillHistoryScreen), findsOneWidget);
    expect(find.text('Electricity History'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(BillWorkflow), findsOneWidget);
    expect(
      tester.widget<BillWorkflow>(find.byType(BillWorkflow)).draft,
      same(draft),
    );
    expect(draft.amount, '73.21');
  });

  testWidgets(
    'year graph and list use assigned category months, including zero',
    (tester) async {
      final repository = InMemoryBillRepository();
      await add(
        repository,
        savedBill(id: 'sep', year: 2025, month: 9, amountCents: 250000),
      );
      await add(repository, savedBill(id: 'zero', month: 10, amountCents: 0));
      await add(
        repository,
        savedBill(id: 'nov', month: 11, amountCents: 310000),
      );
      await add(
        repository,
        savedBill(id: 'water', category: 'water', month: 11),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BillHistoryScreen(
            repository: repository,
            category: BillCategory.electricity,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2026'), findsOneWidget);
      expect(find.byTooltip('October 2026: PHP ₱0.00'), findsOneWidget);
      expect(find.byTooltip('November 2026: PHP ₱3,100.00'), findsOneWidget);
      expect(find.byKey(const ValueKey('history-record-zero')), findsOneWidget);
      expect(find.byKey(const ValueKey('history-record-nov')), findsOneWidget);
      expect(find.byKey(const ValueKey('history-record-sep')), findsNothing);
      expect(find.byKey(const ValueKey('history-record-water')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('historyPreviousYear')));
      await tester.pumpAndSettle();
      expect(find.text('2025'), findsOneWidget);
      expect(find.byKey(const ValueKey('history-record-sep')), findsOneWidget);
      expect(find.byKey(const ValueKey('history-record-zero')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('historyNextYear')));
      await tester.pumpAndSettle();
      expect(find.text('2026'), findsOneWidget);
    },
  );

  testWidgets('mixed currency graph labels amounts without conversion', (
    tester,
  ) async {
    final repository = InMemoryBillRepository();
    await add(repository, savedBill(id: 'php', month: 10, currencyCode: 'PHP'));
    await add(repository, savedBill(id: 'usd', month: 11, currencyCode: 'USD'));
    await tester.pumpWidget(
      MaterialApp(
        home: BillHistoryScreen(
          repository: repository,
          category: BillCategory.electricity,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Amount (mixed currencies)'), findsOneWidget);
    expect(
      find.text('Multiple currencies shown. Amounts are not converted.'),
      findsOneWidget,
    );
    expect(find.byTooltip('October 2026: PHP ₱100.00'), findsOneWidget);
    expect(find.byTooltip('November 2026: USD \$100.00'), findsOneWidget);
  });

  testWidgets('empty year navigation differs from repository errors', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BillHistoryScreen(
          repository: InMemoryBillRepository(),
          category: BillCategory.water,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('historyEmpty')), findsOneWidget);
    expect(find.byKey(const ValueKey('historyLoadError')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('historyNextYear')));
    await tester.pumpAndSettle();
    expect(find.text('${DateTime.now().year + 1}'), findsOneWidget);
  });

  testWidgets(
    'History deletion confirms and removes only the selected record',
    (tester) async {
      final repository = InMemoryBillRepository();
      await add(repository, savedBill(id: 'delete-me', month: 11));
      await add(repository, savedBill(id: 'keep-me', month: 12));
      await tester.pumpWidget(
        MaterialApp(
          home: BillHistoryScreen(
            repository: repository,
            category: BillCategory.electricity,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final selected = find.byKey(const ValueKey('history-record-delete-me'));
      await tester.longPress(selected);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('historyDelete-delete-me')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('historyDelete-delete-me')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Electricity · November 2026'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await repository.allRecords(), hasLength(2));

      await tester.longPress(selected);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('historyDelete-delete-me')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(await repository.find('electricity', 2026, 11), isNull);
      expect((await repository.find('electricity', 2026, 12))!.id, 'keep-me');
    },
  );

  testWidgets('saved details show the stored snapshot without edit controls', (
    tester,
  ) async {
    final repository = InMemoryBillRepository();
    final record = savedBill(
      id: 'detail',
      month: 11,
      amountCents: 12345,
      householdName: 'Shared home',
    );
    await add(repository, record);
    await tester.pumpWidget(
      MaterialApp(
        home: BillHistoryScreen(
          repository: repository,
          category: BillCategory.electricity,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('history-record-detail')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();

    expect(find.text('Assigned month: November 2026'), findsOneWidget);
    expect(find.text('Total bill: PHP ₱123.45'), findsOneWidget);
    expect(find.text('Household amount: PHP ₱123.45'), findsOneWidget);
    expect(find.text('Occupant amount: PHP ₱123.45'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Delete'), findsNothing);

    final household = find.byKey(const ValueKey('savedHousehold0'));
    expect(
      find.descendant(of: household, matching: find.text('Shared home')),
      findsOneWidget,
    );
    await tester.tap(find.text('Computation'));
    await tester.pumpAndSettle();
    expect(find.text('Step 1 — Count person-days'), findsOneWidget);
    expect(find.text('Total: 1 person-days.'), findsOneWidget);
    expect(
      find.textContaining('does not recalculate the bill'),
      findsOneWidget,
    );
  });

  testWidgets('saved equal-per-household details omit occupant amounts', (
    tester,
  ) async {
    final record = savedBill(
      id: 'equal',
      category: 'miscellaneous',
      method: 'equalPerHousehold',
    );
    await tester.pumpWidget(
      MaterialApp(home: SavedBillDetailScreen(record: record)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.text('Household amount: PHP ₱100.00'), findsOneWidget);
    expect(find.textContaining('Occupant amount:'), findsNothing);
  });
}

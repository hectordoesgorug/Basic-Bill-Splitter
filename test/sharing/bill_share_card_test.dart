import 'dart:typed_data';

import 'package:basic_bill_splitter/app/app_platform.dart';
import 'package:basic_bill_splitter/calculation/bill_calculator.dart';
import 'package:basic_bill_splitter/calculation/bill_models.dart';
import 'package:basic_bill_splitter/history/bill_history_screen.dart';
import 'package:basic_bill_splitter/sharing/bill_share_card.dart';
import 'package:basic_bill_splitter/sharing/bill_share_export.dart';
import 'package:basic_bill_splitter/storage/billing_period.dart';
import 'package:basic_bill_splitter/storage/saved_bill_record.dart';
import 'package:basic_bill_splitter/workflow/bill_draft.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

SavedBillRecord savedRecord({String method = 'personDays'}) =>
    SavedBillRecord.create(
      category: 'electricity',
      assignedMonth: const AssignedMonth(2026, 11),
      startDate: '2026-10-23',
      endDate: '2026-11-22',
      id: 'share-card',
      now: DateTime.utc(2026, 11, 23),
      snapshot: {
        'category': 'electricity',
        'totalAmountCents': 12345,
        'billingStart': '2026-10-23',
        'billingEnd': '2026-11-22',
        'allocationMethod': method,
        'totalConsumption': 100.25,
        'draftTotalConsumption': '100.25',
        'households': [
          {
            'name': 'A very long household name that should wrap instead of colliding with the amount',
            'occupantCount': 1,
            'amountCents': 12345,
            'occupants': [
              {
                'occupancyDays': 31,
                'measuredConsumption': 20.5,
                'draftMeasured': '20.5',
                'mode': 'fullPeriod',
                'manualDays': null,
                'ranges': <Object?>[],
                'amountCents': method == 'equalPerHousehold' ? null : 12345,
              },
            ],
          },
        ],
      },
    );

ShareBillCardData calculationCard() {
  final bill = Bill(
    totalAmountCents: 12345,
    totalConsumption: 100.25,
    households: [
      Household(
        name: 'A very long household name that should wrap instead of colliding with the amount',
        occupants: [
          const Occupant(occupancyDays: 31, measuredConsumption: 20.5),
        ],
      ),
    ],
  );
  final allocation = const BillCalculator().calculate(
    bill,
    method: AllocationMethod.personDays,
  );
  return ShareBillCardData.fromCalculation(
    category: BillCategory.electricity,
    startDate: '2026-10-23',
    endDate: '2026-11-22',
    bill: bill,
    allocation: allocation,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Uint8List? sharedPng;
  setUp(() {
    sharedPng = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppPlatform.channel, (call) async {
          if (call.method == 'sharePng') {
            sharedPng = (call.arguments as Map)['png'] as Uint8List;
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppPlatform.channel, null);
  });

  testWidgets('share card shows only the concise monetary breakdown', (
    tester,
  ) async {
    final data = calculationCard();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: ShareBillCard(data: data)),
        ),
      ),
    );
    expect(find.text('Electricity bill'), findsOneWidget);
    expect(find.text('₱123.45'), findsNWidgets(3));
    expect(find.textContaining('23 October 2026'), findsOneWidget);
    expect(find.textContaining('Occupant 1'), findsOneWidget);
    expect(find.textContaining('Person-days'), findsNothing);
    expect(find.textContaining('Measured usage'), findsNothing);
    expect(find.textContaining('Total consumption'), findsNothing);
    expect(find.textContaining('Fractional cents'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('equal-per-household card does not invent occupant amounts', (
    tester,
  ) async {
    final data = ShareBillCardData.fromSavedRecord(
      savedRecord(method: 'equalPerHousehold'),
    );
    await tester.pumpWidget(MaterialApp(home: ShareBillCard(data: data)));
    expect(find.text('Occupant 1'), findsNothing);
    expect(find.text('₱123.45'), findsNWidgets(2));
  });

  testWidgets('PNG renderer captures the whole scrollable card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = ShareBillCardData(
      category: 'Electricity',
      startDate: '2026-10-23',
      endDate: '2026-11-22',
      totalAmountCents: 12345,
      households: [
        for (var i = 0; i < 8; i++)
          ShareBillHousehold(
            name: 'Household ${i + 1}',
            amountCents: 12345,
            occupantAmountsCents: [12345],
          ),
      ],
    );
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(width: 400, child: ShareBillCard(data: data)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    expect(boundary.size.height, greaterThan(700));
    final png = await tester.runAsync(
      () => renderBillShareCardPng(boundary, devicePixelRatio: 1),
    );
    expect(png, isNotNull);
    final bytes = png!;
    expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    final dimensions = ByteData.sublistView(bytes);
    expect(dimensions.getUint32(16, Endian.big), greaterThanOrEqualTo(1080));
    expect(dimensions.getUint32(20, Endian.big), greaterThan(2100));
  });

  testWidgets(
    'PNG share renders the complete card and passes image/png bytes',
    (tester) async {
      tester.view.physicalSize = const Size(400, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final data = ShareBillCardData(
        category: 'Electricity',
        startDate: '2026-10-23',
        endDate: '2026-11-22',
        totalAmountCents: 12345,
        households: [
          for (var i = 0; i < 8; i++)
            ShareBillHousehold(
              name: 'Household ${i + 1}',
              amountCents: 12345,
              occupantAmountsCents: [12345],
            ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  key: const ValueKey('shareNow'),
                  onPressed: () => shareBillCard(context, data),
                  child: const Text('Share'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('shareNow')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        for (var attempt = 0; attempt < 100 && sharedPng == null; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pumpAndSettle();

      expect(sharedPng, isNotNull);
      expect(sharedPng!.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      final png = ByteData.sublistView(sharedPng!);
      final width = png.getUint32(16, Endian.big);
      final height = png.getUint32(20, Endian.big);
      expect(width, greaterThanOrEqualTo(1080));
      expect(height, greaterThan(700));
      expect(find.text('Share'), findsOneWidget);
    },
  );

  testWidgets('History shares its saved snapshot as a PNG', (tester) async {
    final record = savedRecord();
    final originalSnapshot = record.snapshot;
    await tester.pumpWidget(
      MaterialApp(home: SavedBillDetailScreen(record: record)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ShareBillCard), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('historyShare')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 100 && sharedPng == null; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pumpAndSettle();

    expect(sharedPng, isNotNull);
    expect(sharedPng!.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    expect(record.snapshot, originalSnapshot);
    expect(find.text('Details'), findsOneWidget);
  });
}

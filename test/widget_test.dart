import 'dart:io';

import 'package:basic_bill_splitter/app/app_platform.dart';
import 'package:basic_bill_splitter/workflow/household_section.dart';
import 'package:flutter/services.dart';
import 'package:basic_bill_splitter/calculation/bill_models.dart';
import 'package:basic_bill_splitter/main.dart';
import 'package:basic_bill_splitter/app/home_screen.dart';
import 'package:basic_bill_splitter/workflow/bill_draft.dart';
import 'package:basic_bill_splitter/workflow/bill_workflow.dart';
import 'package:basic_bill_splitter/storage/bill_repository.dart';
import 'package:basic_bill_splitter/storage/billing_period.dart';
import 'package:basic_bill_splitter/storage/saved_bill_record.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

class RetryBillRepository extends InMemoryBillRepository {
  bool failWrites = true;

  @override
  Future<SaveBillResult> save(
    SavedBillRecord record, {
    String? movingRecordId,
    String? replaceRecordId,
  }) {
    if (failWrites) throw StateError('simulated write failure');
    return super.save(
      record,
      movingRecordId: movingRecordId,
      replaceRecordId: replaceRecordId,
    );
  }
}

BillDraft validDraft() => BillDraft(today: DateTime(2026, 11, 1))
  ..amount = '1000.00'
  ..consumption = '100';

Future<void> pumpDraft(WidgetTester tester, BillDraft draft) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: HomeScreen(initialDraft: draft),
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
  final footerBack = find.byKey(const ValueKey('back'));
  await tester.tap(
    footerBack.evaluate().isNotEmpty ? footerBack : find.byTooltip('Back'),
  );
  await tester.pumpAndSettle();
  if (find.text('Revisit calculation?').evaluate().isNotEmpty) {
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
  }
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
  TestWidgetsFlutterBinding.ensureInitialized();
  final nativeCalls = <MethodCall>[];
  final platformCalls = <MethodCall>[];
  final version = RegExp(
    r'^version:\s*(\S+)',
    multiLine: true,
  ).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1)!;
  setUp(() {
    nativeCalls.clear();
    platformCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppPlatform.channel, (call) async {
          nativeCalls.add(call);
          return switch (call.method) {
            'getVersion' => version,
            'openRepository' => true,
            'savedBills' || 'overlappingBills' => <String>[],
            'findSavedBill' || 'latestSavedBill' => null,
            _ => null,
          };
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          platformCalls.add(call);
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppPlatform.channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  for (final category in BillCategory.values) {
    testWidgets('Home starts ${category.name} with its default method', (
      tester,
    ) async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('homeBanner')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('appVersion'))).data,
        'Version $version',
      );
      final button = find.byKey(ValueKey('billType-${category.name}'));
      final icon = tester.widget<Icon>(
        find.descendant(of: button, matching: find.byType(Icon)),
      );
      expect(
        icon.icon,
        {
          BillCategory.electricity: Icons.bolt,
          BillCategory.water: Icons.water_drop,
          BillCategory.internet: Icons.wifi,
          BillCategory.rent: Icons.home,
          BillCategory.lpg: Icons.local_fire_department,
          BillCategory.miscellaneous: Icons.more_horiz,
        }[category],
      );
      expect(icon.size, 24);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      final draft = tester
          .widget<BillWorkflow>(find.byType(BillWorkflow))
          .draft;
      expect(draft.category, category);
      expect(draft.method, category.defaultMethod);
      expect(find.text(category.label), findsOneWidget);
      expect(find.byKey(const ValueKey('category')), findsNothing);
      expect(find.text('Category'), findsNothing);
      expect(draft.hasMeaningfulInputs, isFalse);
      await tester.tap(find.byKey(const ValueKey('goHome')));
      await tester.pumpAndSettle();
      expect(find.text('Discard this calculation?'), findsNothing);
      expect(find.text('Choose a bill type'), findsOneWidget);
    });
  }

  testWidgets(
    'Home banner, six choices and native GitHub action are available',
    (tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();
      final image = tester.widget<Image>(
        find.byKey(const ValueKey('homeBanner')),
      );
      expect((image.image as AssetImage).assetName, 'assets/banner.png');
      for (final category in BillCategory.values) {
        expect(
          find.byKey(ValueKey('billType-${category.name}')),
          findsOneWidget,
        );
      }
      expect(find.text('Misc'), findsOneWidget);
      final link = find.byKey(const ValueKey('visitGitHub'));
      await tester.ensureVisible(link);
      await tester.tap(link);
      await tester.pumpAndSettle();
      expect(
        nativeCalls.where((call) => call.method == 'openRepository'),
        hasLength(1),
      );
      expect(
        nativeCalls.where((call) => call.method == 'getVersion'),
        hasLength(1),
      );
    },
  );

  testWidgets('footer stays at the bottom above the system navigation inset', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 24);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    final versionLabel = find.byKey(const ValueKey('appVersion'));
    expect(tester.getBottomRight(versionLabel).dy, closeTo(956, 1));
    final lastButton = find.byKey(const ValueKey('billType-miscellaneous'));
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('homeFooter'))).dy,
      greaterThan(tester.getBottomRight(lastButton).dy + 100),
    );
    expect(
      tester.getBottomRight(find.byKey(const ValueKey('visitGitHub'))).dy,
      lessThan(tester.getTopLeft(versionLabel).dy),
    );
    final image = tester.widget<Image>(
      find.byKey(const ValueKey('githubMark')),
    );
    expect(
      (image.image as AssetImage).assetName,
      'assets/github-mark-black.png',
    );
    expect(image.excludeFromSemantics, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'footer scrolls into view with large text on a short dark screen',
    (tester) async {
      tester.view.physicalSize = const Size(360, 600);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(bottom: 24);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const HomeScreen(),
        ),
      );
      await tester.pumpAndSettle();
      final versionLabel = find.byKey(const ValueKey('appVersion'));
      expect(tester.getBottomRight(versionLabel).dy, greaterThan(600));
      await tester.ensureVisible(versionLabel);
      await tester.pumpAndSettle();
      expect(tester.getBottomRight(versionLabel).dy, lessThanOrEqualTo(576));
      final link = find.byKey(const ValueKey('visitGitHub'));
      await tester.ensureVisible(link);
      await tester.tap(link);
      await tester.pumpAndSettle();
      expect(
        nativeCalls.where((call) => call.method == 'openRepository'),
        hasLength(1),
      );
      final mark = tester.widget<Image>(
        find.byKey(const ValueKey('githubMark')),
      );
      expect(
        (mark.image as AssetImage).assetName,
        'assets/github-mark-white.png',
      );
      expect(find.text('Version $version'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'left hamburger and title-free bars preserve workflow navigation',
    (tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();
      void checkBar() {
        expect(tester.widget<AppBar>(find.byType(AppBar)).title, isNull);
        expect(find.text('Splitter'), findsNothing);
        expect(find.byIcon(Icons.menu), findsOneWidget);
        expect(find.byIcon(Icons.more_vert), findsNothing);
        expect(find.byTooltip('Menu'), findsOneWidget);
        final menu = find.byKey(const ValueKey('appMenu'));
        expect(tester.getCenter(menu).dx, lessThan(56));
        expect(tester.getCenter(menu).dy, lessThan(80));
      }

      checkBar();
      await tester.tap(find.byKey(const ValueKey('billType-electricity')));
      await tester.pumpAndSettle();
      checkBar();
      expect(find.byTooltip('Home'), findsOneWidget);
      expect(find.byTooltip('Back'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a bill type'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('billType-water')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('How to'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Details — enter'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Choose a bill type'), findsOneWidget);
      checkBar();
    },
  );

  testWidgets('GitHub failure is visible without losing Home', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppPlatform.channel, (call) async {
          if (call.method == 'getVersion') return version;
          throw PlatformException(code: 'NO_BROWSER');
        });
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    final link = find.byKey(const ValueKey('visitGitHub'));
    await tester.ensureVisible(link);
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not open GitHub'), findsOneWidget);
    expect(find.text('Choose a bill type'), findsOneWidget);
  });

  testWidgets('About and How to work while Settings remains disabled', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    Future<void> openMenu() async {
      await tester.tap(find.byKey(const ValueKey('appMenu')));
      await tester.pumpAndSettle();
    }

    await openMenu();
    final historyItem = find.ancestor(
      of: find.text('History'),
      matching: find.byType(PopupMenuItem<String>),
    );
    expect(tester.widget<PopupMenuItem<String>>(historyItem).enabled, isTrue);
    final settingsItem = find.ancestor(
      of: find.text('Settings — Coming soon'),
      matching: find.byType(PopupMenuItem<String>),
    );
    expect(tester.widget<PopupMenuItem<String>>(settingsItem).enabled, isFalse);
    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();
    expect(find.text('About Basic Bill Splitter'), findsOneWidget);
    expect(find.text('Version $version'), findsNWidgets(2));
    expect(
      find.textContaining('offline shared-bill calculator'),
      findsOneWidget,
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await openMenu();
    await tester.tap(find.text('How to'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Details — enter'), findsOneWidget);
    expect(find.textContaining('including metered occupants'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a bill type'), findsOneWidget);
  });

  testWidgets('Home and first-step system Back confirm entered work', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.tap(find.byKey(const ValueKey('billType-electricity')));
    await tester.pumpAndSettle();
    await enter(tester, 'amount', '12.34');
    await tester.tap(find.byKey(const ValueKey('goHome')));
    await tester.pumpAndSettle();
    expect(find.text('Discard this calculation?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    final amount = find.descendant(
      of: find.byKey(const ValueKey('amount')),
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(amount).controller.text, '12.34');
    expect(
      tester.widget<BillWorkflow>(find.byType(BillWorkflow)).draft.amount,
      '12.34',
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Discard this calculation?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a bill type'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('billType-water')));
    await tester.pumpAndSettle();
    final draft = tester.widget<BillWorkflow>(find.byType(BillWorkflow)).draft;
    expect(draft.amount, '');
    expect(draft.category, BillCategory.water);
  });

  testWidgets(
    'billing and occupant calendars update pairs within the bill period',
    (tester) async {
      tester.view.physicalSize = const Size(430, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final draft = validDraft();
      await pumpDraft(tester, draft);
      final billing = find.byKey(const ValueKey('period.pickDates'));
      await tester.ensureVisible(billing);
      await tester.tap(billing);
      await tester.pumpAndSettle();
      var dialog = tester.widget<DateRangePickerDialog>(
        find.byType(DateRangePickerDialog),
      );
      expect(dialog.initialDateRange!.start, DateTime(2026, 11, 1));
      expect(find.byKey(const ValueKey('periodStart')), findsNothing);
      expect(find.byKey(const ValueKey('periodEnd')), findsNothing);
      await tester.tap(find.text('3').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('20').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use dates'));
      await tester.pumpAndSettle();
      expect(draft.periodStart, '2026-11-03');
      expect(draft.periodEnd, '2026-11-20');
      expect(draft.periodDays, 18);
      expect(find.text('03 Nov 2026 - 20 Nov 2026'), findsOneWidget);
      await next(tester);
      await back(tester);
      expect(find.text('03 Nov 2026 - 20 Nov 2026'), findsOneWidget);
      await tester.ensureVisible(billing);
      await tester.tap(billing);
      await tester.pumpAndSettle();
      dialog = tester.widget<DateRangePickerDialog>(
        find.byType(DateRangePickerDialog),
      );
      expect(dialog.initialDateRange!.start, DateTime(2026, 11, 3));
      expect(dialog.initialDateRange!.end, DateTime(2026, 11, 20));
      await tester.tap(find.text('10').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('12').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('03 Nov 2026 - 20 Nov 2026'), findsOneWidget);
      expect(draft.periodStart, '2026-11-03');
      expect(draft.periodEnd, '2026-11-20');
      await next(tester);
      await next(tester);
      await select(tester, 'h0.o0.mode', 'Date ranges');
      final occupancy = find.byKey(const ValueKey('h0.o0.r0.pickDates'));
      await tester.ensureVisible(occupancy);
      await tester.tap(occupancy);
      await tester.pumpAndSettle();
      dialog = tester.widget<DateRangePickerDialog>(
        find.byType(DateRangePickerDialog),
      );
      expect(dialog.firstDate, DateTime(2026, 11, 3));
      expect(dialog.lastDate, DateTime(2026, 11, 20));
      await tester.tap(find.text('6').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('8').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use dates'));
      await tester.pumpAndSettle();
      final range = draft.households.single.occupants.single.ranges.single;
      expect(range.start, '2026-11-06');
      expect(range.end, '2026-11-08');
      await next(tester);
      expect(find.text('Review').last, findsOneWidget);
      expect(
        find.text('Date ranges · 3 days · 2026-11-06 to 2026-11-08'),
        findsOneWidget,
      );
      await back(tester);
      await tester.ensureVisible(occupancy);
      await tester.tap(occupancy);
      await tester.pumpAndSettle();
      await tester.tap(find.text('10').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('12').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(range.start, '2026-11-06');
      expect(range.end, '2026-11-08');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Exit confirms work and uses Android activity navigation', (
    tester,
  ) async {
    await pumpDraft(tester, validDraft());
    Future<void> exitMenu() async {
      await tester.tap(find.byKey(const ValueKey('appMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Exit'));
      await tester.pumpAndSettle();
    }

    await exitMenu();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
      platformCalls.where((call) => call.method == 'SystemNavigator.pop'),
      isEmpty,
    );
    await exitMenu();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(
      platformCalls.where((call) => call.method == 'SystemNavigator.pop'),
      hasLength(1),
    );
  });

  testWidgets('household identity keeps accents through steps and removals', (
    tester,
  ) async {
    final draft = validDraft();
    draft.households.single.name = 'First unit';
    draft.households.addAll([
      HouseholdDraft(name: 'Second unit'),
      HouseholdDraft(name: 'Third unit'),
    ]);
    await pumpDraft(tester, draft);
    await next(tester);
    expect(find.text('Number of Occupants'), findsNWidgets(3));
    final colors = {
      for (final household in draft.households)
        household: tester
            .widget<HouseholdSection>(find.byKey(ObjectKey(household)))
            .accent,
    };
    expect(colors.values.toSet(), hasLength(3));
    for (var step = 2; step <= 4; step++) {
      await next(tester);
      for (final household in draft.households) {
        final section = tester.widget<HouseholdSection>(
          find.byKey(ObjectKey(household)),
        );
        expect(section.accent, colors[household]);
        expect(section.name, household.name);
      }
    }
    final nameStyle = tester.widget<Text>(find.text('First unit')).style!;
    final occupantStyle = tester
        .widget<Text>(find.textContaining('Occupant 1 ·').first)
        .style!;
    expect(nameStyle.fontSize!, greaterThan(occupantStyle.fontSize!));
    await back(tester);
    await back(tester);
    await back(tester);
    final remove = find.byTooltip('Remove household 1');
    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    for (final household in draft.households) {
      expect(
        tester
            .widget<HouseholdSection>(find.byKey(ObjectKey(household)))
            .accent,
        colors[household],
      );
    }
    await tester.ensureVisible(find.byKey(const ValueKey('addHousehold')));
    await tester.tap(find.byKey(const ValueKey('addHousehold')));
    await tester.pumpAndSettle();
    for (final household in draft.households.take(2)) {
      expect(
        tester
            .widget<HouseholdSection>(find.byKey(ObjectKey(household)))
            .accent,
        colors[household],
      );
    }
  });

  testWidgets(
    'Home and nested households support small screens, dark theme and large text',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final name =
          'A long household name with enough detail to wrap onto multiple lines';
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const HomeScreen(),
        ),
      );
      await tester.pumpAndSettle();
      final misc = find.byKey(const ValueKey('billType-miscellaneous'));
      await tester.ensureVisible(misc);
      await tester.tap(misc);
      await tester.pumpAndSettle();
      await enter(tester, 'amount', '10');
      await next(tester);
      await enter(tester, 'h0.name', name);
      await next(tester);
      final draft = tester
          .widget<BillWorkflow>(find.byType(BillWorkflow))
          .draft;
      await select(tester, 'h0.o0.mode', 'Date ranges');
      await enter(tester, 'h0.o0.r0.start', draft.periodStart);
      await enter(tester, 'h0.o0.r0.end', draft.periodEnd);
      final dates = find.byKey(const ValueKey('h0.o0.r0.pickDates'));
      await tester.ensureVisible(dates);
      await tester.tap(dates);
      await tester.pumpAndSettle();
      expect(find.byType(DateRangePickerDialog), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      await next(tester);
      await next(tester);
      expect(find.text(name), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Review and Results format quantities without rounding inputs', (
    tester,
  ) async {
    final draft = validDraft()
      ..amount = '100.00'
      ..consumption = '3.00007';
    draft.households.single.occupants.single.measured = '1.23456';
    final second = HouseholdDraft(name: 'Second household');
    second.occupants.single.measured = '0';
    draft.households.add(second);

    await pumpDraft(tester, draft);
    await next(tester);
    await next(tester);
    await next(tester);
    expect(find.text('Review').last, findsOneWidget);
    expect(find.text('Total consumption: 3.00 kWh'), findsOneWidget);
    expect(find.text('Measured usage: 1.23 kWh'), findsOneWidget);
    expect(find.text('Measured usage: 0.00 kWh'), findsOneWidget);
    expect(find.text('Full Period · 30 days'), findsNWidgets(2));
    expect(find.text('1 occupant(s)'), findsNWidgets(2));
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('billTotal'))).data,
      '₱100.00',
    );

    await next(tester);
    expect(find.text('Results').last, findsOneWidget);
    expect(find.text('Total consumption: 3.00 kWh'), findsOneWidget);
    expect(find.text('Measured usage: 1.23 kWh'), findsOneWidget);
    expect(find.text('Measured usage: 0.00 kWh'), findsOneWidget);
    // These allocations require the full input precision, not displayed values.
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('householdTotal0'))).data,
      '₱70.58',
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('householdTotal1'))).data,
      '₱29.42',
    );

    await back(tester);
    await back(tester);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('h0.o0.measured')))
          .initialValue,
      '1.23456',
    );
    await back(tester);
    await back(tester);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('consumption')))
          .initialValue,
      '3.00007',
    );
    expect(draft.households.first.occupants.single.measured, '1.23456');
    expect(tester.takeException(), isNull);
  });

  testWidgets('app opens Home with Material 3', (tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.text('Choose a bill type'), findsOneWidget);
    expect(find.text('Splitter'), findsNothing);
    expect(tester.widget<AppBar>(find.byType(AppBar)).title, isNull);
    expect(
      Theme.of(tester.element(find.byType(HomeScreen))).useMaterial3,
      isTrue,
    );
    expect(find.byKey(const ValueKey('homeBanner')), findsOneWidget);
    expect(find.text('Flutter Demo'), findsNothing);
  });

  testWidgets('bill details reject invalid fields before continuing', (
    tester,
  ) async {
    final draft = validDraft()..periodEnd = '2026-10-01';
    await pumpDraft(tester, draft);
    await enter(tester, 'amount', '1.999');
    await enter(tester, 'consumption', '0');
    await next(tester);
    expect(find.text('Bill Details'), findsOneWidget);
    expect(find.textContaining('at most 2 decimal places'), findsOneWidget);
    expect(find.textContaining('on or after the start date'), findsOneWidget);
    expect(find.textContaining('greater than zero'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected category permits a one-bill method override', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    final selector = find.byKey(const ValueKey('billType-miscellaneous'));
    await tester.ensureVisible(selector);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    final draft = tester.widget<BillWorkflow>(find.byType(BillWorkflow)).draft;
    expect(draft.category, BillCategory.miscellaneous);
    expect(draft.method, AllocationMethod.equalPerHousehold);
    expect(find.byKey(const ValueKey('category')), findsNothing);
    await select(tester, 'method', 'Person-days');
    expect(draft.method, AllocationMethod.personDays);
    expect(draft.category, BillCategory.miscellaneous);
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
      expect(find.text('Review').last, findsOneWidget);
      expect(find.text('Apartment A'), findsOneWidget);
      await next(tester);
      expect(find.text('Results').last, findsOneWidget);
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
    expect(find.text('Review').last, findsOneWidget);
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
    expect(find.text('Review').last, findsOneWidget);
  });

  testWidgets('headcount and duration errors stay at their step', (
    tester,
  ) async {
    await pumpDraft(tester, validDraft());
    await next(tester);
    await enter(tester, 'h0.name', '');
    await tester.tap(find.byKey(const ValueKey('h0.headcount.decrement')));
    await tester.pump();
    await next(tester);
    expect(find.text('Households').last, findsOneWidget);
    expect(find.text('Enter a household name.'), findsOneWidget);
    expect(find.textContaining('whole number from 1 to 10'), findsOneWidget);
    await enter(tester, 'h0.name', 'A');
    await tester.tap(find.byKey(const ValueKey('h0.headcount.increment')));
    await tester.pump();
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
    expect(find.text('Review').last, findsOneWidget);
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
    expect(find.text('Results').last, findsOneWidget);
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
    'system Back retains draft and Results Exit requires confirmation',
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
      await tester.tap(find.byKey(const ValueKey('exit')));
      await tester.pumpAndSettle();
      expect(find.text('Save before exiting?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Results').last, findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('exit')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Exit Without Saving'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a bill type'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('billType-water')));
      await tester.tap(find.byKey(const ValueKey('billType-water')));
      await tester.pumpAndSettle();
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
    expect(find.text('Households').last, findsOneWidget);
    expect(tester.getBottomRight(button).dy, lessThanOrEqualTo(544));
    expect(
      tester.getBottomRight(find.byKey(const ValueKey('back'))).dy,
      lessThanOrEqualTo(544),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('flat tabs and occupant label fit a normal portrait screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpDraft(tester, validDraft());
    for (final label in [
      'Details',
      'Households',
      'Usage',
      'Review',
      'Results',
    ]) {
      expect(find.byKey(ValueKey('tab-$label')), findsOneWidget);
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Number of Occupants'), findsNothing);
    final primary = Theme.of(
      tester.element(find.byKey(const ValueKey('tab-indicator-Details'))),
    ).colorScheme.primary;
    expect(
      tester
          .widget<Container>(
            find.byKey(const ValueKey('tab-indicator-Details')),
          )
          .color,
      primary,
    );
    expect(
      tester
          .widget<Container>(
            find.byKey(const ValueKey('tab-indicator-Results')),
          )
          .color,
      Colors.transparent,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'tabs unlock after validation and headcount uses bounded stepper',
    (tester) async {
      await pumpDraft(tester, validDraft());
      final reviewSemantics = tester
          .getSemantics(find.byKey(const ValueKey('tab-Review')))
          .getSemanticsData();
      expect(reviewSemantics.label, 'Review');
      await tester.tap(find.byKey(const ValueKey('tab-Review')));
      await tester.pumpAndSettle();
      expect(find.text('Bill Details'), findsOneWidget);
      await next(tester);
      expect(find.text('Number of Occupants'), findsOneWidget);
      expect(find.byKey(const ValueKey('h0.headcount.value')), findsOneWidget);
      expect(find.text('1').last, findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('h0.headcount.decrement')));
      await tester.pump();
      expect(find.text('0').last, findsOneWidget);
      await next(tester);
      expect(find.textContaining('whole number from 1 to 10'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('h0.headcount.increment')));
      await tester.pump();
      await next(tester);
      expect(find.text('Usage & Duration'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tab-Households')));
      await tester.pumpAndSettle();
      for (var i = 0; i < 9; i++) {
        await tester.tap(find.byKey(const ValueKey('h0.headcount.increment')));
        await tester.pump();
      }
      expect(find.text('10').last, findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('h0.headcount.increment')),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets('Clear Usage confirms and preserves bill and household details', (
    tester,
  ) async {
    final draft = validDraft();
    await pumpDraft(tester, draft);
    await next(tester);
    await enter(tester, 'h0.name', 'Apartment A');
    await next(tester);
    await enter(tester, 'h0.o0.measured', '12');
    await select(tester, 'h0.o0.mode', 'Manual days');
    await enter(tester, 'h0.o0.days', '10');
    await tester.tap(find.byKey(const ValueKey('clear')));
    await tester.pumpAndSettle();
    expect(find.text('Clear usage?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(draft.households.single.occupants.single.measured, '12');
    await tester.tap(find.byKey(const ValueKey('clear')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear').last);
    await tester.pumpAndSettle();
    expect(draft.amount, '1000.00');
    expect(draft.households.single.name, 'Apartment A');
    expect(draft.households.single.headcount, '1');
    expect(draft.households.single.occupants.single.measured, '');
    expect(
      draft.households.single.occupants.single.mode,
      OccupancyMode.fullPeriod,
    );
    expect(draft.households.single.occupants.single.days, '');
  });

  testWidgets(
    'Households Clear resets only household data after confirmation',
    (tester) async {
      final draft = validDraft();
      await pumpDraft(tester, draft);
      await next(tester);
      await enter(tester, 'h0.name', 'Apartment A');
      await tester.tap(find.byKey(const ValueKey('h0.headcount.increment')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('clear')));
      await tester.pumpAndSettle();
      expect(find.text('Clear households?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(draft.households.single.name, 'Apartment A');
      expect(draft.households.single.headcount, '2');
      await tester.tap(find.byKey(const ValueKey('clear')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear').last);
      await tester.pumpAndSettle();
      expect(draft.households, hasLength(1));
      expect(draft.households.single.name, 'Household 1');
      expect(draft.households.single.headcount, '1');
      expect(draft.households.single.occupants, hasLength(1));
      expect(draft.amount, '1000.00');
    },
  );

  testWidgets(
    'Results revisit cancel preserves results; edits require recalculation',
    (tester) async {
      final draft = validDraft();
      await pumpDraft(tester, draft);
      await next(tester);
      await next(tester);
      await next(tester);
      await next(tester);
      expect(find.text('Results').last, findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const ValueKey('save')))
            .onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const ValueKey('share')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Revisit calculation?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Results').last, findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const ValueKey('save')))
            .onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const ValueKey('share')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tab-Details')));
      await tester.pumpAndSettle();
      await enter(tester, 'amount', '2000.00');
      await tester.tap(find.byKey(const ValueKey('tab-Results')));
      await tester.pumpAndSettle();
      expect(find.text('Bill Details'), findsOneWidget);
      await next(tester);
      await next(tester);
      await next(tester);
      await next(tester);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('billTotal'))).data,
        '₱2,000.00',
      );
    },
  );

  testWidgets('Results Share sends a PNG without saving the calculation', (
    tester,
  ) async {
    final repository = InMemoryBillRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: HomeScreen(initialDraft: validDraft(), repository: repository),
      ),
    );
    await next(tester);
    await next(tester);
    await next(tester);
    await next(tester);
    await tester.tap(find.byKey(const ValueKey('share')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      for (
        var attempt = 0;
        attempt < 100 && !nativeCalls.any((call) => call.method == 'sharePng');
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pumpAndSettle();

    expect(nativeCalls.map((call) => call.method), contains('sharePng'));
    final shareCall = nativeCalls.singleWhere(
      (call) => call.method == 'sharePng',
    );
    final png = (shareCall.arguments as Map)['png'] as Uint8List;
    expect(png.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    expect(await repository.allRecords(), isEmpty);
    expect(find.text('Results').last, findsOneWidget);
  });

  testWidgets('Save persists current results and updates after recalculation', (
    tester,
  ) async {
    final repository = InMemoryBillRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: HomeScreen(initialDraft: validDraft(), repository: repository),
      ),
    );
    await next(tester);
    await next(tester);
    await next(tester);
    await next(tester);
    expect(find.text('Results').last, findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('save')));
    await tester.pumpAndSettle();
    expect(find.text('Bill saved successfully.'), findsOneWidget);
    expect(find.text('Results').last, findsOneWidget);
    expect(await repository.allRecords(), hasLength(1));
    final firstSnapshot = (await repository.allRecords()).single.snapshot;
    final firstHousehold = (firstSnapshot['households']! as List).single as Map;
    expect(firstHousehold['occupantCount'], 1);
    expect(
      (firstHousehold['occupants']! as List).single['amountCents'],
      firstHousehold['amountCents'],
    );
    await tester.pump(const Duration(seconds: 5));

    await tester.tap(find.byKey(const ValueKey('save')));
    await tester.pumpAndSettle();
    expect(find.text('Already saved.'), findsOneWidget);
    expect(await repository.allRecords(), hasLength(1));

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tab-Details')));
    await tester.pumpAndSettle();
    await enter(tester, 'amount', '2000.00');
    await next(tester);
    await next(tester);
    await next(tester);
    await next(tester);
    expect(find.text('Results').last, findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Replace existing bill?'), findsOneWidget);
    await tester.tap(find.text('Replace'));
    await tester.pumpAndSettle();
    expect(await repository.allRecords(), hasLength(1));
    expect(
      (await repository.allRecords()).single.snapshot['totalAmountCents'],
      200000,
    );
    expect(find.text('Results').last, findsOneWidget);
  });

  testWidgets('Save failure keeps Results and allows retry', (tester) async {
    final repository = RetryBillRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: HomeScreen(initialDraft: validDraft(), repository: repository),
      ),
    );
    await next(tester);
    await next(tester);
    await next(tester);
    await next(tester);
    await tester.tap(find.byKey(const ValueKey('save')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'The bill could not be saved. Your calculation is still available; try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Results').last, findsOneWidget);
    expect(await repository.allRecords(), isEmpty);

    repository.failWrites = false;
    await tester.pump(const Duration(seconds: 5));
    await tester.tap(find.byKey(const ValueKey('save')));
    await tester.pumpAndSettle();
    expect(find.text('Bill saved successfully.'), findsOneWidget);
    expect(await repository.allRecords(), hasLength(1));
  });

  testWidgets('equal-per-household save keeps occupant allocations absent', (
    tester,
  ) async {
    final repository = InMemoryBillRepository();
    final draft = validDraft()..selectCategory(BillCategory.miscellaneous);
    draft.households.single.headcount = '2';
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: HomeScreen(initialDraft: draft, repository: repository),
      ),
    );
    await next(tester);
    await next(tester);
    await next(tester);
    await next(tester);
    await tester.tap(find.byKey(const ValueKey('save')));
    await tester.pumpAndSettle();
    final savedHousehold =
        ((await repository.allRecords()).single.snapshot['households']! as List)
                .single
            as Map;
    expect(savedHousehold['occupants'], hasLength(2));
    expect(
      (savedHousehold['occupants']! as List).map(
        (o) => (o as Map)['amountCents'],
      ),
      everyElement(isNull),
    );
  });

  testWidgets('overlapping billing selection warns but allows continuing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = InMemoryBillRepository();
    await repository.save(
      SavedBillRecord.create(
        category: BillCategory.electricity.name,
        assignedMonth: const AssignedMonth(2026, 11),
        startDate: '2026-10-23',
        endDate: '2026-11-22',
        snapshot: const {},
        now: DateTime.utc(2026, 11, 22),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: HomeScreen(initialDraft: validDraft(), repository: repository),
      ),
    );
    final periodPicker = find.byKey(const ValueKey('period.pickDates'));
    await tester.ensureVisible(periodPicker);
    await tester.tap(periodPicker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('3').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('20').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use dates'));
    await tester.pumpAndSettle();
    expect(find.text('Overlapping billing period'), findsOneWidget);
    await tester.tap(find.text('Continue Anyway'));
    await tester.pumpAndSettle();
    expect(find.text('Bill Details'), findsOneWidget);
    await next(tester);
    expect(find.text('Households').last, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new category draft proposes the next saved billing period', (
    tester,
  ) async {
    final repository = InMemoryBillRepository();
    await repository.save(
      SavedBillRecord.create(
        category: BillCategory.electricity.name,
        assignedMonth: const AssignedMonth(2026, 11),
        startDate: '2026-10-23',
        endDate: '2026-11-22',
        snapshot: const {'totalAmountCents': 10000},
        now: DateTime.utc(2026, 11, 22),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: HomeScreen(repository: repository),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('billType-electricity')));
    await tester.pumpAndSettle();
    expect(find.text('23 Nov 2026 - 22 Dec 2026'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Results Exit offers Save and Exit Without Saving', (
    tester,
  ) async {
    final repository = InMemoryBillRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: HomeScreen(initialDraft: validDraft(), repository: repository),
      ),
    );
    await next(tester);
    await next(tester);
    await next(tester);
    await next(tester);
    await tester.tap(find.byKey(const ValueKey('exit')));
    await tester.pumpAndSettle();
    expect(find.text('Save before exiting?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Results').last, findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('exit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save & Exit'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a bill type'), findsOneWidget);
    expect(await repository.allRecords(), hasLength(1));
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
        home: HomeScreen(initialDraft: validDraft()),
      ),
    );
    await next(tester);
    await next(tester);
    await next(tester);
    await next(tester);
    expect(find.text('Results').last, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

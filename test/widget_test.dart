import 'dart:io';

import 'package:basic_bill_splitter/app/app_platform.dart';
import 'package:basic_bill_splitter/workflow/household_section.dart';
import 'package:flutter/services.dart';
import 'package:basic_bill_splitter/calculation/bill_models.dart';
import 'package:basic_bill_splitter/main.dart';
import 'package:basic_bill_splitter/app/home_screen.dart';
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
          return call.method == 'getVersion' ? version : true;
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

  testWidgets(
    'About and How to are functional and future entries are disabled',
    (tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();
      Future<void> openMenu() async {
        await tester.tap(find.byKey(const ValueKey('appMenu')));
        await tester.pumpAndSettle();
      }

      await openMenu();
      for (final label in ['History — Coming soon', 'Settings — Coming soon']) {
        final item = find.ancestor(
          of: find.text(label),
          matching: find.byType(PopupMenuItem<String>),
        );
        expect(tester.widget<PopupMenuItem<String>>(item).enabled, isFalse);
      }
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
      expect(find.textContaining('1. Bill Details'), findsOneWidget);
      expect(
        find.textContaining('including metered occupants'),
        findsOneWidget,
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a bill type'), findsOneWidget);
    },
  );

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
      await tester.tap(find.text('3').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('20').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use dates'));
      await tester.pumpAndSettle();
      expect(draft.periodStart, '2026-11-03');
      expect(draft.periodEnd, '2026-11-20');
      expect(draft.periodDays, 18);
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
      expect(find.text('Review'), findsOneWidget);
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
    expect(find.text('Review'), findsOneWidget);
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
    expect(find.text('Results'), findsOneWidget);
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
    expect(find.text('Splitter'), findsOneWidget);
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
      expect(find.text('Discard this calculation?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Results'), findsOneWidget);
      await next(tester);
      await tester.tap(find.text('Discard'));
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
        home: HomeScreen(initialDraft: validDraft()),
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

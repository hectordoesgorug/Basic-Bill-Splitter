import 'package:basic_bill_splitter/app/app_platform.dart';
import 'package:basic_bill_splitter/app/settings_screen.dart';
import 'package:basic_bill_splitter/storage/bill_repository.dart';
import 'package:basic_bill_splitter/storage/billing_period.dart';
import 'package:basic_bill_splitter/storage/saved_bill_record.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

SavedBillRecord saved({String id = 'one', int cents = 5000}) =>
    SavedBillRecord.create(
      id: id,
      category: 'electricity',
      assignedMonth: const AssignedMonth(2026, 10),
      startDate: '2026-10-01',
      endDate: '2026-10-01',
      now: DateTime.utc(2026, 10, 2),
      snapshot: {
        'category': 'electricity',
        'totalAmountCents': cents,
        'billingStart': '2026-10-01',
        'billingEnd': '2026-10-01',
        'allocationMethod': 'personDays',
        'totalConsumption': null,
        'draftTotalConsumption': '',
        'households': [
          {
            'name': 'Household 1',
            'occupantCount': 1,
            'amountCents': cents,
            'occupants': [
              {
                'occupancyDays': 1,
                'measuredConsumption': null,
                'draftMeasured': '',
                'mode': 'fullPeriod',
                'manualDays': null,
                'ranges': <Object?>[],
                'amountCents': cents,
              },
            ],
          },
        ],
      },
    );

class FailingWipeRepository extends InMemoryBillRepository {
  @override
  Future<int> deleteAll() async => throw StateError('simulated failure');
}

Future<void> pumpSettings(
  WidgetTester tester, {
  required BillRepository repository,
  bool hasDraft = false,
  bool darkMode = false,
  Future<bool> Function(bool)? onDarkModeChanged,
  VoidCallback? onReset,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              key: const ValueKey('openSettings'),
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => SettingsScreen(
                    repository: repository,
                    hasActiveDraft: hasDraft,
                    darkMode: darkMode,
                    onDarkModeChanged: onDarkModeChanged ?? (_) async => true,
                    onDataReset: onReset ?? () {},
                  ),
                ),
              ),
              child: const Text('Home'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('openSettings')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppPlatform.channel, (call) async {
          calls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppPlatform.channel, null);
  });

  testWidgets(
    'Settings exposes all five functions and the backup privacy notice',
    (tester) async {
      await pumpSettings(
        tester,
        repository: InMemoryBillRepository(),
        hasDraft: true,
      );
      expect(find.text('Backup'), findsOneWidget);
      expect(find.text('Restore'), findsOneWidget);
      expect(find.text('Clear All'), findsOneWidget);
      expect(find.text('Wipe Data'), findsOneWidget);
      expect(find.text('Dark Mode'), findsOneWidget);
      expect(find.textContaining('not encrypted'), findsOneWidget);
      expect(find.text('No saved bills to delete'), findsOneWidget);
      expect(
        tester
            .widget<ListTile>(find.byKey(const ValueKey('settingsClearAll')))
            .enabled,
        isTrue,
      );
    },
  );

  testWidgets(
    'empty backup uses the document picker without changing records',
    (tester) async {
      final repository = InMemoryBillRepository();
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AppPlatform.channel, (call) async {
            calls.add(call);
            if (call.method == 'createBackup') return true;
            return null;
          });
      await pumpSettings(tester, repository: repository);

      await tester.tap(find.byKey(const ValueKey('settingsBackup')));
      await tester.pumpAndSettle();

      final call = calls.singleWhere((item) => item.method == 'createBackup');
      final arguments = call.arguments as Map;
      expect(arguments['records'], isEmpty);
      expect((arguments['filename'] as String), startsWith('Splitter-Backup-'));
      expect((arguments['filename'] as String), endsWith('.zip'));
      expect(await repository.allRecords(), isEmpty);
      expect(find.text('Backup exported successfully.'), findsOneWidget);
    },
  );

  testWidgets('backup exports the complete saved snapshot without mutation', (
    tester,
  ) async {
    final repository = InMemoryBillRepository();
    final record = saved();
    await repository.save(record);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppPlatform.channel, (call) async {
          calls.add(call);
          if (call.method == 'createBackup') return true;
          return null;
        });
    await pumpSettings(tester, repository: repository);
    await tester.tap(find.byKey(const ValueKey('settingsBackup')));
    await tester.pumpAndSettle();

    final call = calls.singleWhere((item) => item.method == 'createBackup');
    expect((call.arguments as Map)['records'], [record.encode()]);
    expect((await repository.allRecords()).single.encode(), record.encode());
  });

  testWidgets('cancelled backup does not claim success', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppPlatform.channel, (call) async {
          calls.add(call);
          return null;
        });
    await pumpSettings(tester, repository: InMemoryBillRepository());
    await tester.tap(find.byKey(const ValueKey('settingsBackup')));
    await tester.pumpAndSettle();
    expect(find.text('Backup exported successfully.'), findsNothing);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets(
    'confirmed restore replaces records and clears the active draft',
    (tester) async {
      final repository = InMemoryBillRepository();
      await repository.save(saved());
      final incoming = saved(id: 'restored', cents: 7500);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AppPlatform.channel, (call) async {
            calls.add(call);
            if (call.method == 'pickBackup') {
              return {
                'formatVersion': 1,
                'recordCount': 1,
                'records': [incoming.encode()],
              };
            }
            return null;
          });
      var reset = false;
      await pumpSettings(
        tester,
        repository: repository,
        hasDraft: true,
        onReset: () => reset = true,
      );

      await tester.tap(find.byKey(const ValueKey('settingsRestore')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Replace saved bills?'), findsOneWidget);
      expect(
        find.textContaining('active calculation will also be discarded'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(reset, isTrue);
      expect((await repository.allRecords()).single.id, 'restored');
      expect(find.text('Home'), findsOneWidget);
    },
  );

  testWidgets('cancelled restore preserves records and current calculation', (
    tester,
  ) async {
    final repository = InMemoryBillRepository();
    await repository.save(saved());
    final incoming = saved(id: 'restored');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppPlatform.channel, (call) async {
          if (call.method == 'pickBackup') {
            return {
              'formatVersion': 1,
              'recordCount': 1,
              'records': [incoming.encode()],
            };
          }
          return null;
        });
    var reset = false;
    await pumpSettings(
      tester,
      repository: repository,
      hasDraft: true,
      onReset: () => reset = true,
    );
    await tester.tap(find.byKey(const ValueKey('settingsRestore')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(reset, isFalse);
    expect((await repository.allRecords()).single.id, 'one');
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('malformed restore is rejected before confirmation', (
    tester,
  ) async {
    final repository = InMemoryBillRepository();
    await repository.save(saved());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppPlatform.channel, (call) async {
          if (call.method == 'pickBackup') {
            return {
              'formatVersion': 1,
              'recordCount': 1,
              'records': ['{invalid'],
            };
          }
          return null;
        });
    await pumpSettings(tester, repository: repository);
    await tester.tap(find.byKey(const ValueKey('settingsRestore')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Replace saved bills?'), findsNothing);
    expect((await repository.allRecords()).single.id, 'one');
    expect(
      find.text(
        'Backup could not be restored. Existing saved bills were preserved.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Clear All cancellation preserves draft and saved bills', (
    tester,
  ) async {
    final repository = InMemoryBillRepository();
    await repository.save(saved());
    var reset = false;
    await pumpSettings(
      tester,
      repository: repository,
      hasDraft: true,
      onReset: () => reset = true,
    );
    await tester.tap(find.byKey(const ValueKey('settingsClearAll')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(reset, isFalse);
    expect(await repository.allRecords(), hasLength(1));
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('confirmed Clear All discards only the active calculation', (
    tester,
  ) async {
    final repository = InMemoryBillRepository();
    await repository.save(saved());
    var reset = false;
    await pumpSettings(
      tester,
      repository: repository,
      hasDraft: true,
      onReset: () => reset = true,
    );
    await tester.tap(find.byKey(const ValueKey('settingsClearAll')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Clear All'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(reset, isTrue);
    expect(await repository.allRecords(), hasLength(1));
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('Wipe Data requires confirmation and preserves Dark Mode state', (
    tester,
  ) async {
    final repository = InMemoryBillRepository();
    await repository.save(saved());
    var reset = false;
    var darkMode = true;
    await pumpSettings(
      tester,
      repository: repository,
      hasDraft: true,
      darkMode: darkMode,
      onDarkModeChanged: (value) async {
        darkMode = value;
        return true;
      },
      onReset: () => reset = true,
    );
    await tester.tap(find.byKey(const ValueKey('settingsWipeData')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await repository.allRecords(), hasLength(1));
    expect(reset, isFalse);
    expect(darkMode, isTrue);

    await tester.tap(find.byKey(const ValueKey('settingsWipeData')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilledButton, 'Wipe Data'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(await repository.allRecords(), isEmpty);
    expect(reset, isTrue);
    expect(darkMode, isTrue);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('failed wipe leaves saved records and Settings usable', (
    tester,
  ) async {
    final repository = FailingWipeRepository();
    await repository.save(saved());
    await pumpSettings(tester, repository: repository);
    await tester.tap(find.byKey(const ValueKey('settingsWipeData')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilledButton, 'Wipe Data'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(await repository.allRecords(), hasLength(1));
    expect(find.text('Settings'), findsOneWidget);
    expect(
      find.text('Saved bills could not be deleted. No success was reported.'),
      findsOneWidget,
    );
  });

  testWidgets('Dark Mode write failure is reported and toggle reverts', (
    tester,
  ) async {
    await pumpSettings(
      tester,
      repository: InMemoryBillRepository(),
      onDarkModeChanged: (_) async => false,
    );
    await tester.tap(find.byKey(const ValueKey('settingsDarkMode')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('settingsDarkMode')),
          )
          .value,
      isFalse,
    );
    expect(
      find.text('Dark Mode preference could not be saved.'),
      findsOneWidget,
    );
  });
}

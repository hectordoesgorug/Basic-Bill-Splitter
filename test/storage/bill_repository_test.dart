import 'dart:convert';

import 'package:basic_bill_splitter/storage/bill_repository.dart';
import 'package:basic_bill_splitter/storage/billing_period.dart';
import 'package:basic_bill_splitter/storage/saved_bill_record.dart';
import 'package:flutter_test/flutter_test.dart';

SavedBillRecord record({
  String id = 'record-1',
  int assignedMonth = 11,
  String start = '2026-10-23',
  String end = '2026-11-22',
  int cents = 10000,
  String currencyCode = 'PHP',
  DateTime? now,
}) => SavedBillRecord.create(
  category: 'electricity',
  assignedMonth: AssignedMonth(2026, assignedMonth),
  startDate: start,
  endDate: end,
  snapshot: {
    'category': 'electricity',
    'totalAmountCents': cents,
    'billingStart': start,
    'billingEnd': end,
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
            'occupancyDays': 31,
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
  id: id,
  currencyCode: currencyCode,
  now: now ?? DateTime.utc(2026, 11, 23),
);

void main() {
  test('record JSON round-trips with integer cents and stable metadata', () {
    final original = record();
    final decoded = SavedBillRecord.decode(original.encode());
    expect(decoded.id, original.id);
    expect(decoded.createdAt, original.createdAt);
    expect(decoded.snapshot['totalAmountCents'], 10000);
    expect(decoded.toJson(), original.toJson());
  });

  test('legacy records default to PHP and new currency codes round-trip', () {
    final php = record();
    final legacy = php.toJson()..remove('currencyCode');
    expect(SavedBillRecord.decode(jsonEncode(legacy)).currencyCode, 'PHP');

    final usd = record(currencyCode: 'USD');
    expect(SavedBillRecord.decode(usd.encode()).currencyCode, 'USD');
    expect(
      () => SavedBillRecord.create(
        category: 'electricity',
        assignedMonth: const AssignedMonth(2026, 11),
        startDate: '2026-10-23',
        endDate: '2026-11-22',
        snapshot: usd.snapshot,
        currencyCode: 'XYZ',
      ),
      throwsFormatException,
    );
  });

  test('rejects malformed and unsupported saved records', () {
    expect(() => SavedBillRecord.decode('{bad json'), throwsFormatException);
    expect(
      () => SavedBillRecord.decode('{"schemaVersion":2}'),
      throwsFormatException,
    );
    expect(
      () => SavedBillRecord.create(
        category: 'electricity',
        assignedMonth: const AssignedMonth(2026, 10),
        startDate: '2026-10-23',
        endDate: '2026-11-22',
        snapshot: const {},
      ),
      throwsArgumentError,
    );
  });

  test('validates snapshot reconciliation and equal allocations', () {
    final equal = SavedBillRecord.create(
      category: 'miscellaneous',
      assignedMonth: const AssignedMonth(2026, 11),
      startDate: '2026-11-01',
      endDate: '2026-11-30',
      snapshot: {
        'category': 'miscellaneous',
        'totalAmountCents': 10000,
        'billingStart': '2026-11-01',
        'billingEnd': '2026-11-30',
        'allocationMethod': 'equalPerHousehold',
        'totalConsumption': null,
        'draftTotalConsumption': '',
        'households': [
          {
            'name': 'Household 1',
            'occupantCount': 1,
            'amountCents': 10000,
            'occupants': [
              {
                'occupancyDays': 30,
                'measuredConsumption': null,
                'draftMeasured': '',
                'mode': 'fullPeriod',
                'manualDays': null,
                'ranges': <Object?>[],
                'amountCents': null,
              },
            ],
          },
        ],
      },
    );
    final decoded = SavedBillRecord.decode(equal.encode());
    final households = decoded.snapshot['households']! as List;
    final occupants = (households.single as Map)['occupants']! as List;
    expect((occupants.single as Map)['amountCents'], isNull);

    final malformed = record().toJson();
    malformed['snapshot'] = {'totalAmountCents': '10000'};
    expect(
      () => SavedBillRecord.decode(jsonEncode(malformed)),
      throwsFormatException,
    );
  });

  test(
    'first save persists and repeated unchanged save creates no duplicate',
    () async {
      final repository = InMemoryBillRepository();
      final first = record();
      expect((await repository.save(first)).succeeded, isTrue);

      final repeat = record(
        id: 'different-id',
        now: DateTime.utc(2026, 11, 24),
      );
      final result = await repository.save(repeat, movingRecordId: first.id);
      expect(result.alreadySaved, isTrue);
      expect(result.record!.id, first.id);
      expect(await repository.allRecords(), hasLength(1));
    },
  );

  test(
    'single-record deletion requires a matching snapshot timestamp',
    () async {
      final repository = InMemoryBillRepository();
      final first = record();
      final second = record(
        id: 'other',
        assignedMonth: 12,
        start: '2026-11-23',
        end: '2026-12-22',
      );
      await repository.save(first);
      await repository.save(second);

      expect(
        await repository.delete(first.id, expectedUpdatedAt: 'stale'),
        isFalse,
      );
      expect(
        await repository.delete(first.id, expectedUpdatedAt: first.updatedAt),
        isTrue,
      );
      expect(await repository.find('electricity', 2026, 11), isNull);
      expect((await repository.find('electricity', 2026, 12))!.id, second.id);
    },
  );

  test('concurrent repeated saves keep one category/month record', () async {
    final repository = InMemoryBillRepository();
    final first = record();
    final second = record(id: 'second', now: DateTime.utc(2026, 11, 24));
    final results = await Future.wait([
      repository.save(first),
      repository.save(second),
    ]);
    expect(results.where((result) => result.succeeded), hasLength(1));
    expect(await repository.allRecords(), hasLength(1));
  });

  test(
    'category and assigned month uniqueness requires explicit replacement',
    () async {
      final repository = InMemoryBillRepository();
      final first = record();
      await repository.save(first);
      final changed = record(id: 'record-2', cents: 20000);

      final conflict = await repository.save(changed);
      expect(conflict.conflict!.id, first.id);
      expect(
        (await repository.find(
          'electricity',
          2026,
          11,
        ))!.snapshot['totalAmountCents'],
        10000,
      );

      final replaced = await repository.save(
        changed,
        replaceRecordId: first.id,
      );
      expect(replaced.succeeded, isTrue);
      expect(replaced.record!.id, first.id);
      expect((await repository.allRecords()), hasLength(1));
      expect(
        (await repository.find(
          'electricity',
          2026,
          11,
        ))!.snapshot['totalAmountCents'],
        20000,
      );
    },
  );

  test(
    'moving a record preserves identity and frees its previous month',
    () async {
      final repository = InMemoryBillRepository();
      final source = record();
      await repository.save(source);
      final moved = record(
        id: source.id,
        assignedMonth: 12,
        start: '2026-11-23',
        end: '2026-12-22',
        cents: 12000,
      );

      final result = await repository.save(moved, movingRecordId: source.id);
      expect(result.succeeded, isTrue);
      expect(result.record!.id, source.id);
      expect(await repository.find('electricity', 2026, 11), isNull);
      expect(await repository.find('electricity', 2026, 12), isNotNull);
    },
  );

  test(
    'a move into an occupied month leaves both records until confirmed',
    () async {
      final repository = InMemoryBillRepository();
      final source = record();
      final destination = record(
        id: 'destination',
        assignedMonth: 12,
        start: '2026-11-23',
        end: '2026-12-22',
        cents: 12000,
      );
      await repository.save(source);
      await repository.save(destination);

      final moving = record(
        id: source.id,
        assignedMonth: 12,
        start: '2026-11-23',
        end: '2026-12-22',
        cents: 15000,
      );
      final conflict = await repository.save(moving, movingRecordId: source.id);
      expect(conflict.conflict!.id, destination.id);
      expect(await repository.allRecords(), hasLength(2));

      final replaced = await repository.save(
        moving,
        movingRecordId: source.id,
        replaceRecordId: destination.id,
      );
      expect(replaced.succeeded, isTrue);
      expect(replaced.record!.id, source.id);
      expect(await repository.allRecords(), hasLength(1));
      expect(await repository.find('electricity', 2026, 11), isNull);
    },
  );

  test('latest and inclusive overlap queries filter by category', () async {
    final repository = InMemoryBillRepository();
    await repository.save(record());
    await repository.save(
      record(
        id: 'water',
        assignedMonth: 12,
        start: '2026-11-23',
        end: '2026-12-22',
      ).copyWithCategory('water'),
    );

    expect(
      (await repository.latestForCategory('electricity'))!.endDate,
      '2026-11-22',
    );
    expect(
      await repository.overlapping(
        category: 'electricity',
        startDate: '2026-11-22',
        endDate: '2026-11-22',
      ),
      hasLength(1),
    );
    expect(
      await repository.overlapping(
        category: 'water',
        startDate: '2026-11-22',
        endDate: '2026-11-22',
      ),
      isEmpty,
    );
  });

  test(
    'replaceAll replaces the complete collection and deleteAll clears it',
    () async {
      final repository = InMemoryBillRepository();
      await repository.save(record(id: 'old'));
      final replacement = record(
        id: 'new',
        assignedMonth: 12,
        start: '2026-11-23',
        end: '2026-12-22',
        cents: 12500,
      );

      final restored = await repository.replaceAll([replacement]);
      expect(restored.map((item) => item.id), ['new']);
      expect(await repository.find('electricity', 2026, 11), isNull);
      expect(await repository.find('electricity', 2026, 12), isNotNull);
      expect(await repository.deleteAll(), 1);
      expect(await repository.allRecords(), isEmpty);
      expect(await repository.deleteAll(), 0);
    },
  );
}

extension on SavedBillRecord {
  SavedBillRecord copyWithCategory(String value) => SavedBillRecord(
    id: id,
    schemaVersion: schemaVersion,
    category: value,
    assignedYear: assignedYear,
    assignedMonth: assignedMonth,
    createdAt: createdAt,
    updatedAt: updatedAt,
    startDate: startDate,
    endDate: endDate,
    snapshot: snapshot,
  );
}

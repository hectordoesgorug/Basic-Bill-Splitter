import 'dart:convert';

import 'package:flutter/services.dart';

import 'saved_bill_record.dart';

class SaveBillResult {
  const SaveBillResult.saved(this.record)
    : conflict = null,
      alreadySaved = false;
  const SaveBillResult.conflict(this.conflict)
    : record = null,
      alreadySaved = false;
  const SaveBillResult.unchanged(this.record)
    : conflict = null,
      alreadySaved = true;

  final SavedBillRecord? record;
  final SavedBillRecord? conflict;
  final bool alreadySaved;

  bool get succeeded => record != null;
}

abstract interface class BillRepository {
  Future<List<SavedBillRecord>> allRecords();
  Future<SavedBillRecord?> find(String category, int year, int month);
  Future<SavedBillRecord?> latestForCategory(String category);
  Future<List<SavedBillRecord>> overlapping({
    required String category,
    required String startDate,
    required String endDate,
    String? excludeId,
  });
  Future<SaveBillResult> save(
    SavedBillRecord record, {
    String? movingRecordId,
    String? replaceRecordId,
  });
}

class PlatformBillRepository implements BillRepository {
  PlatformBillRepository(this.channel);

  final MethodChannel channel;

  Future<SavedBillRecord?> _decode(Object? value) async {
    if (value == null) return null;
    if (value is! String) {
      throw const FormatException('Invalid storage response');
    }
    return SavedBillRecord.decode(value);
  }

  @override
  Future<List<SavedBillRecord>> allRecords() async {
    final values = await channel.invokeListMethod<String>('savedBills');
    return (values ?? const <String>[])
        .map(SavedBillRecord.decode)
        .toList(growable: false);
  }

  @override
  Future<SavedBillRecord?> find(String category, int year, int month) async =>
      _decode(
        await channel.invokeMethod<String>('findSavedBill', {
          'category': category,
          'year': year,
          'month': month,
        }),
      );

  @override
  Future<SavedBillRecord?> latestForCategory(String category) async => _decode(
    await channel.invokeMethod<String>('latestSavedBill', {
      'category': category,
    }),
  );

  @override
  Future<List<SavedBillRecord>> overlapping({
    required String category,
    required String startDate,
    required String endDate,
    String? excludeId,
  }) async {
    final values = await channel.invokeListMethod<String>('overlappingBills', {
      'category': category,
      'startDate': startDate,
      'endDate': endDate,
      'excludeId': excludeId,
    });
    return (values ?? const <String>[])
        .map(SavedBillRecord.decode)
        .toList(growable: false);
  }

  @override
  Future<SaveBillResult> save(
    SavedBillRecord record, {
    String? movingRecordId,
    String? replaceRecordId,
  }) async {
    final response = await channel.invokeMapMethod<String, Object?>(
      'saveBill',
      {
        'record': record.encode(),
        'movingRecordId': movingRecordId,
        'replaceRecordId': replaceRecordId,
      },
    );
    if (response == null) throw StateError('Storage returned no save result');
    final saved = await _decode(response['record']);
    if (response['status'] == 'saved' && saved != null) {
      return SaveBillResult.saved(saved);
    }
    if (response['status'] == 'unchanged' && saved != null) {
      return SaveBillResult.unchanged(saved);
    }
    if (response['status'] == 'conflict') {
      return SaveBillResult.conflict(await _decode(response['conflict']));
    }
    throw StateError('Storage returned an invalid save result');
  }
}

/// In-memory repository for deterministic workflow and persistence tests.
class InMemoryBillRepository implements BillRepository {
  final Map<String, SavedBillRecord> _records = {};

  @override
  Future<List<SavedBillRecord>> allRecords() async =>
      List.unmodifiable(_records.values);

  @override
  Future<SavedBillRecord?> find(String category, int year, int month) async =>
      _records['$category:$year:$month'];

  @override
  Future<SavedBillRecord?> latestForCategory(String category) async {
    final matches =
        _records.values.where((r) => r.category == category).toList()
          ..sort((a, b) => b.endDate.compareTo(a.endDate));
    return matches.firstOrNull;
  }

  @override
  Future<List<SavedBillRecord>> overlapping({
    required String category,
    required String startDate,
    required String endDate,
    String? excludeId,
  }) async => _records.values
      .where(
        (r) =>
            r.category == category &&
            r.id != excludeId &&
            r.startDate.compareTo(endDate) <= 0 &&
            r.endDate.compareTo(startDate) >= 0,
      )
      .toList(growable: false);

  @override
  Future<SaveBillResult> save(
    SavedBillRecord record, {
    String? movingRecordId,
    String? replaceRecordId,
  }) async {
    final key = record.uniqueKey;
    final conflict = _records[key];
    if (conflict != null &&
        conflict.id != movingRecordId &&
        conflict.id != replaceRecordId) {
      return SaveBillResult.conflict(conflict);
    }
    final source = movingRecordId == null
        ? null
        : _records.values
              .where((candidate) => candidate.id == movingRecordId)
              .firstOrNull;
    if (movingRecordId != null && source == null) {
      throw StateError('The saved record being updated no longer exists');
    }
    if (source != null &&
        source.category == record.category &&
        source.assignedYear == record.assignedYear &&
        source.assignedMonth == record.assignedMonth &&
        source.startDate == record.startDate &&
        source.endDate == record.endDate &&
        jsonEncode(source.snapshot) == jsonEncode(record.snapshot)) {
      return SaveBillResult.unchanged(source);
    }
    if (source != null) _records.remove(source.uniqueKey);
    if (conflict != null) _records.remove(key);
    final saved = SavedBillRecord(
      id: source?.id ?? conflict?.id ?? record.id,
      schemaVersion: record.schemaVersion,
      category: record.category,
      assignedYear: record.assignedYear,
      assignedMonth: record.assignedMonth,
      createdAt: source?.createdAt ?? conflict?.createdAt ?? record.createdAt,
      updatedAt: record.updatedAt,
      startDate: record.startDate,
      endDate: record.endDate,
      snapshot: record.snapshot,
    );
    _records[key] = saved;
    return SaveBillResult.saved(saved);
  }
}

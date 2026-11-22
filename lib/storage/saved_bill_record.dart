import 'dart:convert';
import 'dart:math';

import 'billing_period.dart';

class SavedBillRecord {
  const SavedBillRecord({
    required this.id,
    required this.schemaVersion,
    required this.category,
    required this.assignedYear,
    required this.assignedMonth,
    required this.createdAt,
    required this.updatedAt,
    required this.startDate,
    required this.endDate,
    required this.snapshot,
  });

  static const currentSchemaVersion = 1;

  final String id;
  final int schemaVersion;
  final String category;
  final int assignedYear;
  final int assignedMonth;
  final String createdAt;
  final String updatedAt;
  final String startDate;
  final String endDate;
  final Map<String, Object?> snapshot;

  String get uniqueKey => '$category:$assignedYear:$assignedMonth';

  Map<String, Object?> toJson() => {
    'id': id,
    'schemaVersion': schemaVersion,
    'category': category,
    'assignedYear': assignedYear,
    'assignedMonth': assignedMonth,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'startDate': startDate,
    'endDate': endDate,
    'snapshot': snapshot,
  };

  String encode() => jsonEncode(toJson());

  factory SavedBillRecord.decode(String encoded) {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Saved bill must be a JSON object');
    }
    final version = decoded['schemaVersion'];
    if (version != currentSchemaVersion) {
      throw FormatException('Unsupported saved bill schema: $version');
    }
    final snapshot = decoded['snapshot'];
    if (snapshot is! Map<String, dynamic>) {
      throw const FormatException('Saved bill snapshot is invalid');
    }
    final record = SavedBillRecord(
      id: _requiredString(decoded, 'id'),
      schemaVersion: version as int,
      category: _requiredString(decoded, 'category'),
      assignedYear: _requiredInt(decoded, 'assignedYear'),
      assignedMonth: _requiredInt(decoded, 'assignedMonth'),
      createdAt: _requiredString(decoded, 'createdAt'),
      updatedAt: _requiredString(decoded, 'updatedAt'),
      startDate: _requiredString(decoded, 'startDate'),
      endDate: _requiredString(decoded, 'endDate'),
      snapshot: _freezeMap(snapshot),
    );
    final start = _parseDate(record.startDate);
    final end = _parseDate(record.endDate);
    if (record.assignedYear < 1 ||
        record.assignedMonth < 1 ||
        record.assignedMonth > 12 ||
        record.id.isEmpty ||
        start == null ||
        end == null ||
        end.isBefore(start) ||
        assignBillingMonth(start, end) !=
            AssignedMonth(record.assignedYear, record.assignedMonth) ||
        DateTime.tryParse(record.createdAt) == null ||
        DateTime.tryParse(record.updatedAt) == null) {
      throw const FormatException('Saved bill metadata is invalid');
    }
    _validateSnapshot(record);
    return record;
  }

  factory SavedBillRecord.create({
    required String category,
    required AssignedMonth assignedMonth,
    required String startDate,
    required String endDate,
    required Map<String, Object?> snapshot,
    String? id,
    String? createdAt,
    DateTime? now,
  }) {
    final start = _parseDate(startDate);
    final end = _parseDate(endDate);
    if (start == null ||
        end == null ||
        end.isBefore(start) ||
        assignBillingMonth(start, end) != assignedMonth) {
      throw ArgumentError('Saved bill period and assigned month must agree');
    }
    final timestamp = (now ?? DateTime.now()).toUtc().toIso8601String();
    return SavedBillRecord(
      id: id ?? _newId(),
      schemaVersion: currentSchemaVersion,
      category: category,
      assignedYear: assignedMonth.year,
      assignedMonth: assignedMonth.month,
      createdAt: createdAt ?? timestamp,
      updatedAt: timestamp,
      startDate: startDate,
      endDate: endDate,
      snapshot: _freezeMap(snapshot),
    );
  }

  static void _validateSnapshot(SavedBillRecord record) {
    void require(bool condition) {
      if (!condition) {
        throw const FormatException('Saved bill snapshot is inconsistent');
      }
    }

    const categories = {
      'electricity',
      'water',
      'internet',
      'rent',
      'lpg',
      'miscellaneous',
    };
    const methods = {'hybrid', 'personDays', 'equalPerHousehold'};
    final snapshot = record.snapshot;
    require(categories.contains(record.category));
    require(snapshot['category'] == record.category);
    require(snapshot['billingStart'] == record.startDate);
    require(snapshot['billingEnd'] == record.endDate);

    final totalCents = snapshot['totalAmountCents'];
    final method = snapshot['allocationMethod'];
    if (totalCents is! int || totalCents < 0) {
      throw const FormatException('Saved bill amount is invalid');
    }
    if (method is! String || !methods.contains(method)) {
      throw const FormatException('Saved bill allocation method is invalid');
    }
    final householdsValue = snapshot['households'];
    if (householdsValue is! List || householdsValue.isEmpty) {
      throw const FormatException('Saved bill households are invalid');
    }
    final households = householdsValue;

    final totalConsumption = snapshot['totalConsumption'];
    require(snapshot['draftTotalConsumption'] is String);
    require(
      totalConsumption == null ||
          (totalConsumption is num &&
              totalConsumption.isFinite &&
              totalConsumption >= 0),
    );
    if (method == 'hybrid') {
      require(totalConsumption is num && totalConsumption > 0);
    }

    var householdTotal = 0;
    for (final value in households) {
      if (value is! Map<String, Object?>) {
        throw const FormatException('Saved bill household is invalid');
      }
      final household = value;
      final name = household['name'];
      final count = household['occupantCount'];
      final cents = household['amountCents'];
      final occupants = household['occupants'];
      if (name is! String ||
          name.isEmpty ||
          count is! int ||
          count < 1 ||
          cents is! int ||
          cents < 0 ||
          occupants is! List ||
          occupants.length != count) {
        throw const FormatException('Saved bill household inputs are invalid');
      }
      householdTotal += cents;

      var occupantTotal = 0;
      for (final occupantValue in occupants) {
        if (occupantValue is! Map<String, Object?>) {
          throw const FormatException('Saved bill occupant is invalid');
        }
        final occupant = occupantValue;
        final days = occupant['occupancyDays'];
        final measured = occupant['measuredConsumption'];
        final rawMeasured = occupant['draftMeasured'];
        final mode = occupant['mode'];
        final manualDays = occupant['manualDays'];
        final ranges = occupant['ranges'];
        final occupantCents = occupant['amountCents'];
        if (days is! int || days < 1) {
          throw const FormatException(
            'Saved bill occupancy duration is invalid',
          );
        }
        require(
          measured == null ||
              (measured is num && measured.isFinite && measured >= 0),
        );
        require(rawMeasured is String);
        require(
          mode == 'manualDays' || mode == 'fullPeriod' || mode == 'dateRanges',
        );
        require(manualDays == null || manualDays is String);
        if (ranges is! List) {
          throw const FormatException(
            'Saved bill occupancy ranges are invalid',
          );
        }
        if (method == 'equalPerHousehold') {
          require(occupantCents == null);
        } else {
          require(occupantCents is int && occupantCents >= 0);
          occupantTotal += occupantCents as int;
        }
        if (mode == 'dateRanges') {
          if (ranges.isEmpty) {
            throw const FormatException(
              'Saved bill occupancy ranges are empty',
            );
          }
          for (final rangeValue in ranges) {
            if (rangeValue is! Map<String, Object?>) {
              throw const FormatException(
                'Saved bill occupancy range is invalid',
              );
            }
            final range = rangeValue;
            final start = range['start'];
            final end = range['end'];
            if (start is! String || end is! String) {
              throw const FormatException(
                'Saved bill occupancy dates are invalid',
              );
            }
            final parsedStart = _parseDate(start);
            final parsedEnd = _parseDate(end);
            if (parsedStart == null ||
                parsedEnd == null ||
                parsedEnd.isBefore(parsedStart)) {
              throw const FormatException(
                'Saved bill occupancy dates are invalid',
              );
            }
          }
        }
      }
      if (method != 'equalPerHousehold') {
        require(occupantTotal == cents);
      }
    }
    require(householdTotal == totalCents);
  }

  static DateTime? _parseDate(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return null;
    final parts = value.split('-').map(int.tryParse).toList();
    if (parts.any((part) => part == null)) return null;
    final date = DateTime.utc(parts[0]!, parts[1]!, parts[2]!);
    if (date.year.toString().padLeft(4, '0') !=
            parts[0]!.toString().padLeft(4, '0') ||
        date.month != parts[1] ||
        date.day != parts[2]) {
      return null;
    }
    return date;
  }

  static Map<String, Object?> _freezeMap(Map<String, Object?> map) =>
      Map.unmodifiable({
        for (final entry in map.entries) entry.key: _freeze(entry.value),
      });

  static Object? _freeze(Object? value) => switch (value) {
    Map<String, Object?> map => _freezeMap(map),
    List<Object?> list => List.unmodifiable(list.map(_freeze)),
    _ => value,
  };

  static String _newId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  static String _requiredString(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is! String || value.isEmpty) {
      throw FormatException('Saved bill $key is invalid');
    }
    return value;
  }

  static int _requiredInt(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is! int) throw FormatException('Saved bill $key is invalid');
    return value;
  }
}

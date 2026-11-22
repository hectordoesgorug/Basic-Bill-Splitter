import 'package:flutter/services.dart';

import '../storage/bill_repository.dart';

/// Android facilities used by the app shell, without additional packages.
abstract final class AppPlatform {
  static const channel = MethodChannel('basic_bill_splitter/app');
  static final BillRepository bills = PlatformBillRepository(channel);

  static Future<String?> version() async {
    try {
      return await channel.invokeMethod<String>('getVersion');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<bool> openRepository() async {
    try {
      return await channel.invokeMethod<bool>('openRepository') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<void> sharePng(Uint8List bytes) =>
      channel.invokeMethod<void>('sharePng', {'png': bytes});

  static Future<bool> darkMode() async =>
      await channel.invokeMethod<bool>('getDarkMode') ?? false;

  static Future<bool> setDarkMode(bool enabled) async =>
      await channel.invokeMethod<bool>('setDarkMode', {'enabled': enabled}) ??
      false;

  static Future<bool> createBackup({
    required List<String> records,
    required String filename,
  }) async =>
      await channel.invokeMethod<bool>('createBackup', {
        'records': records,
        'filename': filename,
      }) ??
      false;

  static Future<List<String>?> pickBackup() async {
    final response = await channel.invokeMapMethod<String, Object?>(
      'pickBackup',
    );
    if (response == null) return null;
    if (response['formatVersion'] != 1 || response['recordCount'] is! int) {
      throw const FormatException('Backup response is invalid');
    }
    final records = response['records'];
    if (records is! List ||
        records.length != response['recordCount'] ||
        records.any((record) => record is! String)) {
      throw const FormatException('Backup records are invalid');
    }
    return records.cast<String>();
  }

  static Future<void> exit() => SystemNavigator.pop();
}

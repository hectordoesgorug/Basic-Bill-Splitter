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

  static Future<void> exit() => SystemNavigator.pop();
}

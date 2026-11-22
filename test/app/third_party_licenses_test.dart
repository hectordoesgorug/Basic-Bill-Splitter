import 'dart:io';

import 'package:basic_bill_splitter/app/app_menu.dart';
import 'package:basic_bill_splitter/storage/bill_repository.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _licenseHarness(Brightness brightness) => MaterialApp(
  theme: ThemeData(useMaterial3: true, brightness: brightness),
  home: Scaffold(
    body: AppMenu(
      version: Future<String?>.value('1.0.0+1'),
      repository: InMemoryBillRepository(),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'native Android notice source contains complete Apache 2.0 terms',
    () async {
      final notice = await File('assets/native_android_licenses.txt')
          .readAsString();

      expect(notice, contains('androidx.core:core:1.13.1'));
      expect(notice, contains('com.getkeepsafe.relinker:relinker:1.4.5'));
      expect(notice, contains('org.jspecify:jspecify:1.0.0'));
      expect(notice, contains('Apache License'));
      expect(notice, contains('Version 2.0'));
      expect(notice, contains('END OF TERMS AND CONDITIONS'));
      expect(notice, contains('WITHOUT WARRANTIES OR CONDITIONS'));
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'About opens third-party licenses in $brightness theme and Back returns',
      (tester) async {
        await tester.pumpWidget(_licenseHarness(brightness));
        await tester.tap(find.byKey(const ValueKey('appMenu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('About'));
        await tester.pumpAndSettle();

        final action = find.byKey(const ValueKey('thirdPartyLicenses'));
        expect(action, findsOneWidget);
        await tester.tap(action);
        await tester.pumpAndSettle();

        expect(find.byType(LicensePage), findsOneWidget);
        expect(
          Theme.of(tester.element(find.byType(LicensePage))).brightness,
          brightness,
        );

        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('About Basic Bill Splitter'), findsOneWidget);

        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('appMenu')), findsOneWidget);
      },
    );
  }
}

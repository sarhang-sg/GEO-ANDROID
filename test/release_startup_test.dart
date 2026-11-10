import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_android/src/app_config.dart';
import 'package:geo_android/src/kurdish_localizations.dart';
import 'package:geo_android/src/local/android_local_runtime.dart';
import 'package:geo_android/src/local/bundled_presentation.dart';
import 'package:nav_kurd_local_core/nav_kurd_local_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'actual Android release opens its pinned web map before installing data',
    () async {
      final release = jsonDecode(
        await rootBundle.loadString('assets/application-release.json'),
      ) as Map;
      final native = {
        'version': AppConfig.appVersion,
        'versionCode': release['androidVersionCode'],
      };
      final map = await BundledPresentation.open(
        release['presentationVersion'] as String,
      );
      expect(utf8.decode(await map.read('/index.html')), contains('<html'));
      const channel = MethodChannel('navkurd/local_core');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'install');
        calls++;
        throw PlatformException(code: 'test_install_boundary');
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await expectLater(
        AndroidLocalRuntime.open({...native, 'versionCode': -1}),
        throwsA(
          isA<CoreFailure>().having(
            (e) => e.code,
            'code',
            'application_release',
          ),
        ),
      );
      expect(calls, 0);
      await expectLater(
        AndroidLocalRuntime.open(native),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'test_install_boundary',
          ),
        ),
      );
      expect(calls, 1);
      await expectLater(
        BundledPresentation.open('wrong'),
        throwsA(isA<CoreFailure>()),
      );
    },
  );

  for (final language in ['ku', 'ckb']) {
    testWidgets(
      'Android UI can build in $language with RTL and both delegates',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            localizationsDelegates: navKurdDelegates,
            supportedLocales: navKurdLocales,
            home: Builder(
              builder: (context) {
                expect(Directionality.of(context), TextDirection.rtl);
                expect(
                  CupertinoLocalizations.of(context).modalBarrierDismissLabel,
                  'داخستن',
                );
                return Scaffold(
                  body: Text(MaterialLocalizations.of(context).okButtonLabel),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('باشە'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

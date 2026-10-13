import 'package:dawn_mesh/core/audio/audio_io.dart';
import 'package:dawn_mesh/core/platform/ios_capabilities.dart';
import 'package:dawn_mesh/ui/pages/home_page.dart';
import 'package:dawn_mesh/ui/widgets/local_address_dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('iOS capability follows the target and leaves Android separate', () {
    expect(usesIosUi, isTrue);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(usesIosUi, isFalse);
  });

  testWidgets(
    'iOS shows LAN address entry and disables incompatible BLE hosting',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      for (final name in ['ble_l2cap', 'ble_l2cap_scan', 'ble_l2cap_data']) {
        final channel = MethodChannel('dev.dawnmesh.intercom/$name');
        messenger.setMockMethodCallHandler(channel, (_) async => true);
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeContent(
              isNight: false,
              stage: const AlwaysStoppedAnimation(0),
              audioIo: MockAudioIo(),
              onEnterRoom: (_, _) {},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('manual-lan-join')), findsOneWidget);
      await tester.tap(find.text('Bluetooth room'));
      await tester.pump();
      final create = find.widgetWithText(
        ElevatedButton,
        'Create Bluetooth room',
      );
      expect(tester.widget<ElevatedButton>(create).onPressed, isNull);
      expect(
        find.text(
          'Join an Android Bluetooth room. iOS Bluetooth hosting is planned.',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 4));
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('manual local entry rejects invalid and IPv6 addresses', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => requestLocalAddress(context),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final continueButton = find.widgetWithText(FilledButton, 'Continue');
    expect(tester.widget<FilledButton>(continueButton).onPressed, isNull);
    await tester.enterText(find.byType(TextField), '::1');
    await tester.pump();
    expect(tester.widget<FilledButton>(continueButton).onPressed, isNull);
    await tester.enterText(find.byType(TextField), '192.168.1.20');
    await tester.pump();
    expect(tester.widget<FilledButton>(continueButton).onPressed, isNotNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
  });
}

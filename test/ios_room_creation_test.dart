import 'package:dawn_mesh/core/session/room_session.dart';
import 'package:dawn_mesh/ui/pages/home_page.dart';
import 'package:dawn_mesh/ui/pages/session_stage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const bleChannel = MethodChannel('dev.dawnmesh.intercom/ble_l2cap');
  const eventChannels = [
    MethodChannel('dev.dawnmesh.intercom/audio'),
    MethodChannel('dev.dawnmesh.intercom/audio_events'),
    MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
    MethodChannel('dev.dawnmesh.intercom/ble_l2cap_scan'),
    MethodChannel('dev.dawnmesh.intercom/ble_l2cap_data'),
  ];
  var advertisingCalls = 0;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    FlutterSecureStorage.setMockInitialValues({});
    advertisingCalls = 0;
    messenger.setMockMethodCallHandler(bleChannel, (call) async {
      if (call.method == 'startAdvertising') advertisingCalls++;
      return true;
    });
    for (final channel in eventChannels) {
      messenger.setMockMethodCallHandler(channel, (_) async => null);
    }
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(bleChannel, null);
    for (final channel in eventChannels) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  for (final mode in RoomMode.values) {
    testWidgets('iOS $mode creation survives the invite keyboard opening', (
      tester,
    ) async {
      try {
        tester.view.physicalSize = const Size(430, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(home: SessionStage(isNight: false)),
        );
        await tester.pump(const Duration(seconds: 3));
        final home = find.byType(HomeContent, skipOffstage: false);
        final homeState = tester.state(home);
        if (mode == RoomMode.fusion) {
          await tester.tap(find.text('融合房'));
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
          await tester.tap(find.byKey(const ValueKey('create-fusion-room')));
        } else {
          if (mode == RoomMode.bluetoothPtt) {
            await tester.tap(find.text('Bluetooth room'));
            await tester.pump();
          }
          await tester.tap(
            find.text(
              mode == RoomMode.wifiFullDuplex
                  ? 'Create Wi-Fi room'
                  : 'Create Bluetooth room',
            ),
          );
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.enterText(
          find.byKey(const ValueKey('room-invite-input')),
          '1234',
        );
        // Flutter widget tests do not open a real keyboard automatically.
        // Reproduce the iPhone's metrics change while the dialog is outstanding.
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        await tester.pump();
        expect(homeState.mounted, isTrue);
        expect(tester.state(home), same(homeState));
        await tester.tap(find.text('创建房间'));
        await tester.pump();
        tester.view.resetViewInsets();
        await tester.pump();
        RoomSession? session;
        for (var i = 0; i < 400; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 10));
          expect(tester.takeException(), isNull);
          session = tester.widget<HomeContent>(home).activeSession;
          if (session != null) break;
        }
        expect(
          session,
          isNotNull,
          reason: 'Confirming the invite must enter a room',
        );
        expect(session!.mode, mode);
        expect(session.state, RoomState.inRoom);
        expect(session.roomInvite?.code, '1234');
        expect(tester.state(home), same(homeState));
        if (mode == RoomMode.bluetoothPtt) expect(advertisingCalls, 1);
        await tester.pump(const Duration(seconds: 2));
        expect(find.byKey(const ValueKey('room-chat-input')), findsOneWidget);
        expect(tester.takeException(), isNull);
        final animation = tester.widget<HomeContent>(home).stage;
        // Fusion returns from a covering route; its stage ticker resumes only
        // after that route's reverse transition has completed.
        for (var i = 0; i < 12 && animation.value < 1; i++) {
          await tester.pump(const Duration(milliseconds: 250));
        }
        expect(animation.value, 1);
        final drag = await tester.startGesture(const Offset(2, 150));
        await drag.moveBy(const Offset(80, 0));
        await tester.pump();
        expect(animation.value, inExclusiveRange(0, 1));
        await drag.cancel();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(animation.value, 1);
        await tester.timedDragFrom(
          const Offset(2, 150),
          const Offset(250, 0),
          const Duration(milliseconds: 500),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        expect(find.byKey(const ValueKey('active-room-card')), findsOneWidget);
        expect(tester.widget<HomeContent>(home).activeSession, same(session));
        await tester.tap(find.byKey(const ValueKey('active-room-card')));
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        expect(find.byKey(const ValueKey('room-chat-input')), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        var disposed = false;
        session.dispose().then((_) => disposed = true);
        for (var i = 0; i < 200 && !disposed; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 10));
        }
        expect(disposed, isTrue);
        await tester.pump(const Duration(seconds: 4));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}

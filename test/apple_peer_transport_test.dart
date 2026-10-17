import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dawn_mesh/core/protocol/frame.dart';
import 'package:dawn_mesh/core/protocol/frame_type.dart';
import 'package:dawn_mesh/core/transport/lan_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.dawnmesh.intercom/apple_peer');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('Apple service path preserves frames and reopens its native endpoint on reconnect', () async {
    final host = LanTransport(controlOnly: true);
    final client = LanTransport(controlOnly: true);
    addTearDown(client.dispose);
    addTearDown(host.dispose);
    expect(await host.startHost(), isTrue);
    final closed = <String>[];
    var opened = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'open') {
        expect(call.arguments['service'], 'bonjour-interface-scoped-endpoint');
        opened++;
        return {
          'port': LanTransport.controlPort,
          'connectionId': 'pipe-$opened',
        };
      }
      closed.add(call.arguments['connectionId'] as String);
      return null;
    });
    expect(
      await client.startClient(
        hostAddress: InternetAddress.loopbackIPv4,
        applePeerService: 'bonjour-interface-scoped-endpoint',
      ),
      isTrue,
    );
    final request = Frame(
      type: FrameType.handshakeHello,
      senderId: 0,
      seq: 1,
      payload: Uint8List.fromList([2, 1, 5]),
    );
    final arrived = host.incoming.first;
    client.send(request);
    expect(
      (await arrived.timeout(const Duration(seconds: 2))).encode(),
      request.encode(),
    );
    final response = Frame(
      type: FrameType.sealed,
      senderId: 1,
      seq: 4,
      payload: Uint8List.fromList([42, 7]),
    );
    final reply = client.incoming.first;
    host.send(response);
    expect(
      (await reply.timeout(const Duration(seconds: 2))).encode(),
      response.encode(),
    );
    expect(await client.reconnectClient(), isTrue);
    expect(opened, 2);
    expect(closed, ['pipe-1']);
    await client.stop();
    expect(closed, ['pipe-1', 'pipe-2']);
  });

  test(
    'Stopping while native discovery opens cannot revive a stale connection',
    () async {
      final client = LanTransport(controlOnly: true);
      addTearDown(client.dispose);
      final opened = Completer<void>();
      final result = Completer<Map<String, Object>>();
      final closed = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'open') {
          opened.complete();
          return result.future;
        }
        closed.add(call.arguments['connectionId'] as String);
        return null;
      });
      final connecting = client.startClient(
        hostAddress: InternetAddress.loopbackIPv4,
        applePeerService: 'pending',
      );
      await opened.future;
      await client.stop();
      result.complete({'port': 9, 'connectionId': 'cancelled-pipe'});
      expect(await connecting, isFalse);
      expect(client.peerCount, 0);
      expect(closed, ['cancelled-pipe']);
    },
  );

  test(
    'A vanished native endpoint fails without using its advertised LAN port',
    () async {
      final client = LanTransport(controlOnly: true);
      addTearDown(client.dispose);
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      expect(
        await client.startClient(
          hostAddress: InternetAddress.loopbackIPv4,
          applePeerService: 'gone',
          silent: true,
        ),
        isFalse,
      );
      expect(client.peerCount, 0);
    },
  );
}

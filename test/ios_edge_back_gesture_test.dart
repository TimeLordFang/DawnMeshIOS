import 'package:dawn_mesh/ui/theme/app_theme.dart';
import 'package:dawn_mesh/ui/widgets/ios_edge_back_gesture.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  void iosTest(String name, WidgetTesterCallback body) {
    testWidgets(name, (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await body(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  iosTest('enabling edge back preserves an awaiting child state', (
    tester,
  ) async {
    final enabled = ValueNotifier(false);
    addTearDown(enabled.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: enabled,
          builder: (_, active, _) => IosEdgeBackGesture(
            enabled: active,
            child: const _PendingDialogPage(),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open invite'));
    await tester.pumpAndSettle();
    enabled.value = true;
    await tester.pump();
    await tester.tap(find.text('Confirm invite'));
    await tester.pumpAndSettle();
    expect(find.text('Room entered'), findsOneWidget);
    enabled.value = false;
    await tester.pump();
    expect(find.text('Room entered'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  iosTest(
    'guarded back accepts edge swipes but rejects short, reversed and central drags',
    (tester) async {
      var backs = 0;
      var ready = true;
      await tester.pumpWidget(
        MaterialApp(
          home: IosEdgeBackGesture(
            canStart: () => ready,
            child: PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) backs++;
              },
              child: const Scaffold(body: SizedBox.expand()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.timedDragFrom(
        const Offset(4, 300),
        const Offset(40, 0),
        const Duration(seconds: 1),
      );
      await tester.pumpAndSettle();
      await tester.dragFrom(const Offset(200, 300), const Offset(300, 0));
      await tester.dragFrom(const Offset(4, 300), const Offset(-180, 0));
      await tester.dragFrom(const Offset(4, 300), const Offset(0, 180));
      await tester.pumpAndSettle();
      expect(backs, 0);
      await tester.timedDragFrom(
        const Offset(4, 300),
        const Offset(220, 0),
        const Duration(seconds: 1),
      );
      await tester.pumpAndSettle();
      expect(backs, 1);
      ready = false;
      await tester.dragFrom(const Offset(4, 300), const Offset(220, 0));
      expect(backs, 1, reason: 'busy stages must ignore the gesture');
      ready = true;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await tester.pumpWidget(
        MaterialApp(
          home: IosEdgeBackGesture(
            child: PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, _) {
                backs++;
              },
              child: const Scaffold(body: SizedBox.expand()),
            ),
          ),
        ),
      );
      await tester.dragFrom(const Offset(4, 300), const Offset(220, 0));
      expect(backs, 1, reason: 'Android keeps its existing back handling');
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    },
  );

  iosTest(
    'modal edge back follows the finger and a cancelled swipe rolls back',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (_) => IosEdgeBackGesture(
                    child: SizedBox(
                      key: const ValueKey('animated-sheet'),
                      height: 300,
                      width: double.infinity,
                      child: const Text('Sheet content'),
                    ),
                  ),
                ),
                child: const Text('Open sheet'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open sheet'));
      await tester.pumpAndSettle();
      final sheet = find.byKey(const ValueKey('animated-sheet'));
      final initial = tester.getTopLeft(sheet);
      final drag = await tester.startGesture(
        Offset(initial.dx + 2, initial.dy + 80),
      );
      await drag.moveBy(const Offset(90, 0));
      await tester.pump();
      expect(tester.getTopLeft(sheet).dx, greaterThan(initial.dx + 50));
      await drag.moveBy(
        const Offset(-80, 0),
        timeStamp: const Duration(milliseconds: 600),
      );
      await drag.up(timeStamp: const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(sheet, findsOneWidget);
      expect(tester.getTopLeft(sheet).dx, closeTo(initial.dx, .1));
      await tester.timedDragFrom(
        Offset(initial.dx + 2, initial.dy + 80),
        const Offset(350, 0),
        const Duration(milliseconds: 500),
      );
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);
    },
  );

  iosTest(
    'custom stage receives progress without translating its whole canvas',
    (tester) async {
      var progress = 0.0;
      await tester.pumpWidget(
        MaterialApp(
          home: IosEdgeBackGesture(
            onProgress: (value) => progress = value,
            child: const Scaffold(
              key: ValueKey('custom-stage'),
              body: SizedBox.expand(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final drag = await tester.startGesture(const Offset(2, 300));
      await drag.moveBy(const Offset(80, 0));
      await tester.pump();
      expect(progress, greaterThan(0));
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('custom-stage'))).dx,
        0,
      );
      await drag.cancel();
      await tester.pumpAndSettle();
      expect(progress, 0);
    },
  );

  iosTest('keyboard-only back does not translate the page', (tester) async {
    var backs = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: IosEdgeBackGesture(
          animateContent: false,
          child: PopScope(
            canPop: false,
            onPopInvokedWithResult: (_, _) => backs++,
            child: const Scaffold(
              key: ValueKey('keyboard-page'),
              body: SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final drag = await tester.startGesture(const Offset(2, 300));
    await drag.moveBy(const Offset(250, 0));
    await tester.pump();
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('keyboard-page'))).dx,
      0,
    );
    await drag.up();
    await tester.pumpAndSettle();
    expect(backs, 1);
    expect(find.byKey(const ValueKey('keyboard-page')), findsOneWidget);
  });

  testWidgets('edge recognition leaves vertical scrolling and taps available', (
    tester,
  ) async {
    var tapped = false;
    var backs = 0;
    final scroll = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: IosEdgeBackGesture(
          child: PopScope(
            canPop: false,
            onPopInvokedWithResult: (_, _) => backs++,
            child: Scaffold(
              body: ListView(
                controller: scroll,
                children: [
                  TextButton(
                    onPressed: () => tapped = true,
                    child: const Text('Tap'),
                  ),
                  const SizedBox(height: 1500),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Tap'));
    expect(tapped, isTrue);
    await tester.dragFrom(const Offset(8, 450), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));
    expect(backs, 0);
    await tester.pumpWidget(const SizedBox());
    scroll.dispose();
  });

  for (final dark in [false, true]) {
    iosTest(
      'ordinary ${dark ? 'dark' : 'light'} pages retain interactive Cupertino back and cancellation',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.dark() : AppTheme.light(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          const Scaffold(body: Center(child: Text('Details'))),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final gesture = await tester.startGesture(const Offset(2, 300));
        await gesture.moveTo(const Offset(170, 300));
        await tester.pump();
        expect(tester.getTopLeft(find.text('Details')).dx, greaterThan(400));
        await gesture.moveTo(
          const Offset(10, 300),
          timeStamp: const Duration(milliseconds: 800),
        );
        await gesture.up(timeStamp: const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(find.text('Details'), findsOneWidget);
        await tester.timedDragFrom(
          const Offset(2, 300),
          const Offset(650, 0),
          const Duration(milliseconds: 600),
        );
        await tester.pumpAndSettle();
        expect(find.text('Details'), findsNothing);
        expect(find.text('Open'), findsOneWidget);
      },
    );
  }
}

class _PendingDialogPage extends StatefulWidget {
  const _PendingDialogPage();

  @override
  State<_PendingDialogPage> createState() => _PendingDialogPageState();
}

class _PendingDialogPageState extends State<_PendingDialogPage> {
  bool entered = false;

  Future<void> _open() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm invite'),
          ),
        ],
      ),
    );
    if (!mounted || accepted != true) return;
    setState(() => entered = true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: entered
        ? const Text('Room entered')
        : TextButton(onPressed: _open, child: const Text('Open invite')),
  );
}

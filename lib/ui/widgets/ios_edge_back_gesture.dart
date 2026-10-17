import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/platform/ios_capabilities.dart';

/// Animated edge-back for custom stages and modal sheets. Ordinary page routes
/// keep Cupertino's interactive transition. Back policy still belongs to PopScope.
class IosEdgeBackGesture extends StatefulWidget {
  const IosEdgeBackGesture({
    super.key,
    required this.child,
    this.enabled = true,
    this.canStart,
    this.animateContent = true,
    this.onProgress,
  });

  final Widget child;
  final bool enabled;
  final bool Function()? canStart;
  // Keyboard dismissal must not move or dismiss the underlying page.
  final bool animateContent;
  // A custom stage can animate its existing foreground/background together.
  final ValueChanged<double>? onProgress;

  @override
  State<IosEdgeBackGesture> createState() => _IosEdgeBackGestureState();
}

class _IosEdgeBackGestureState extends State<IosEdgeBackGesture>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress;
  double _distance = 0;
  bool _settling = false;

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(vsync: this)
      ..addListener(() {
        if (widget.animateContent) widget.onProgress?.call(_progress.value);
      });
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  bool _canStart() {
    if (!mounted ||
        _settling ||
        !widget.enabled ||
        widget.canStart?.call() == false) {
      return false;
    }
    final route = ModalRoute.of(context);
    return route?.isCurrent != false &&
        (route?.animation == null || route!.animation!.isCompleted);
  }

  void _finish(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final threshold = (MediaQuery.sizeOf(context).width * .25).clamp(72, 128);
    final commit =
        _canStart() &&
        velocity >= -300 &&
        (_distance >= threshold || (_distance >= 24 && velocity >= 700));
    unawaited(_settle(commit));
  }

  Future<void> _animate(double target) async {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    await _progress
        .animateTo(target, duration: duration, curve: Curves.easeOutCubic)
        .orCancel;
  }

  Future<void> _settle(bool commit) async {
    if (_settling) return;
    _settling = true;
    try {
      if (!commit) {
        await _animate(0);
        return;
      }
      if (widget.animateContent && widget.onProgress == null) {
        await _animate(1);
      }
      if (!mounted) return;
      final route = ModalRoute.of(context);
      await Navigator.of(context).maybePop();
      if (!mounted) return;
      if (widget.onProgress != null || !widget.animateContent) {
        _progress.value = 0;
      } else if (route?.isCurrent != false) {
        // The back policy may consume the gesture without removing this page.
        await _animate(0);
      }
    } on TickerCanceled {
      // Navigation or lifecycle disposal can finish a gesture before settling.
    } finally {
      _distance = 0;
      _settling = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!usesIosUi) return widget.child;
    // Keep this structure even while disabled: keyboard visibility must never
    // dispose the page waiting for an invite dialog or navigation result.
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {
        _LeftEdgeDragRecognizer:
            GestureRecognizerFactoryWithHandlers<_LeftEdgeDragRecognizer>(
              () => _LeftEdgeDragRecognizer(),
              (recognizer) {
                recognizer
                  ..edgeWidth = 24 + MediaQuery.paddingOf(context).left
                  ..canStart = _canStart
                  ..dragStartBehavior = DragStartBehavior.down
                  ..onStart = (_) {
                    _distance = 0;
                  }
                  ..onUpdate = (details) {
                    _distance = (_distance + (details.primaryDelta ?? 0)).clamp(
                      0,
                      MediaQuery.sizeOf(context).width,
                    );
                    _progress.value =
                        _distance / MediaQuery.sizeOf(context).width;
                  }
                  ..onCancel = () {
                    unawaited(_settle(false));
                  }
                  ..onEnd = _finish;
              },
            ),
      },
      child: AnimatedBuilder(
        animation: _progress,
        child: widget.child,
        builder: (context, child) => Transform.translate(
          offset: widget.animateContent && widget.onProgress == null
              ? Offset(_progress.value * MediaQuery.sizeOf(context).width, 0)
              : Offset.zero,
          child: child,
        ),
      ),
    );
  }
}

// Reject non-edge pointers before entering the arena so ordinary controls retain
// horizontal drags, taps and vertical scrolling.
class _LeftEdgeDragRecognizer extends HorizontalDragGestureRecognizer {
  double edgeWidth = 24;
  bool Function()? canStart;

  @override
  bool isPointerAllowed(PointerEvent event) =>
      event.localPosition.dx >= 0 &&
      event.localPosition.dx <= edgeWidth &&
      canStart?.call() == true &&
      super.isPointerAllowed(event);
}

extension IosEdgeBackNavigation on Widget {
  Widget withIosEdgeBackGesture({
    bool enabled = true,
    bool Function()? canStart,
    bool animateContent = true,
    ValueChanged<double>? onProgress,
  }) => IosEdgeBackGesture(
    enabled: enabled,
    canStart: canStart,
    animateContent: animateContent,
    onProgress: onProgress,
    child: this,
  );
}

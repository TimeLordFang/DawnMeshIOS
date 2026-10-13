import 'package:flutter/foundation.dart';

/// UI capabilities follow Flutter's platform, also allowing iOS widget tests.
/// Socket/Bluetooth implementations still use the actual host operating system.
bool get usesIosUi => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

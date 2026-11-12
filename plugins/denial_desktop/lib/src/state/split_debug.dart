import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// `DENIAL_SPLIT_DEBUG=1` turns on the split's numbers: the pane rectangles,
/// each window's geometry and minimum size, and the clamped ratio.
final bool _splitDebugEnabled =
    Platform.environment['DENIAL_SPLIT_DEBUG'] == '1';

void splitDebug(String message) {
  if (_splitDebugEnabled) debugPrint('split: $message');
}

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The rectangle the floating keyboard occupies, in shell coordinates, or
/// null while it is hidden.
///
/// The input layout publishes this as a software-keyboard region, which is what
/// makes the compositor route touches inside it to the shell instead of the
/// application underneath.
final floatingKeyboardRectProvider =
    NotifierProvider<FloatingKeyboardRectController, Rect?>(
      FloatingKeyboardRectController.new,
    );

class FloatingKeyboardRectController extends Notifier<Rect?> {
  @override
  Rect? build() => null;

  void set(Rect? rect) {
    if (state != rect) state = rect;
  }
}

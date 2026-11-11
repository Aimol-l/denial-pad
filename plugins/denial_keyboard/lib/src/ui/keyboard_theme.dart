import 'package:flutter/widgets.dart';

/// Palette of the floating keyboard. Light by design: the panel floats over
/// apps of any color, and a white key is easier to read than a translucent one.
class KeyboardColors {
  const KeyboardColors({
    this.panel = const Color(0xFFEEF0F3),
    this.panelBorder = const Color(0xFFD3D6DC),
    this.key = const Color(0xFFFFFFFF),
    this.keySpecial = const Color(0xFFDFE2E7),
    this.keyPressed = const Color(0xFFD2D6DD),
    this.ink = const Color(0xFF1C1C1F),
    this.inkMuted = const Color(0xFF5F6470),
    this.inkFaint = const Color(0xFF9AA0AA),
    this.accent = const Color(0xFF6D5BD0),
    this.accentSoft = const Color(0x246D5BD0),
    this.line = const Color(0xFFE3E5E9),
  });

  final Color panel;
  final Color panelBorder;
  final Color key;
  final Color keySpecial;
  final Color keyPressed;
  final Color ink;
  final Color inkMuted;
  final Color inkFaint;
  final Color accent;
  final Color accentSoft;
  final Color line;
}

const kKeyboardRadius = 20.0;
const kHeaderHeight = 64.0;
const kCandidateStripHeight = 34.0;
const kPanelPadding = 12.0;
const kRowGap = 6.0;

BoxShadow get kKeyShadow =>
    const BoxShadow(color: Color(0x29000000), blurRadius: 0, offset: Offset(0, 1));

import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:denial_keyboard_core/denial_keyboard_core.dart';
import 'keyboard_theme.dart';

/// One key. The visual is a white rounded cap with an optional corner label
/// (the digits that ride on the QWERTY row) and a pressed state.
class KeyCap extends StatefulWidget {
  const KeyCap({
    super.key,
    required this.spec,
    required this.label,
    required this.colors,
    required this.height,
    required this.fontSize,
    required this.radius,
    required this.onTap,
    this.highlight = false,
    this.onLongPress,
    this.onLongPressUp,
    this.flexOverride,
  });

  final KeySpec spec;
  final String label;
  final KeyboardColors colors;
  final double height;
  final double fontSize;
  final double radius;
  final VoidCallback onTap;

  /// Shown in the accent colour, for a toggle that is on.
  final bool highlight;
  final VoidCallback? onLongPress;
  final VoidCallback? onLongPressUp;
  final double? flexOverride;

  @override
  State<KeyCap> createState() => _KeyCapState();
}

class _KeyCapState extends State<KeyCap> {
  /// A quick tap can begin and end within one frame; hold the darkened state
  /// long enough to see it.
  static const _pressFeedback = Duration(milliseconds: 50);

  bool _pressed = false;
  DateTime? _pressedAt;
  Timer? _releaseTimer;

  void _press() {
    _releaseTimer?.cancel();
    _pressedAt = DateTime.now();
    if (!_pressed) setState(() => _pressed = true);
  }

  void _release() {
    _releaseTimer?.cancel();
    final held = DateTime.now().difference(_pressedAt ?? DateTime.now());
    final rest = _pressFeedback - held;
    if (rest <= Duration.zero) {
      if (_pressed) setState(() => _pressed = false);
      return;
    }
    _releaseTimer = Timer(rest, () {
      if (mounted && _pressed) setState(() => _pressed = false);
    });
  }

  @override
  void dispose() {
    _releaseTimer?.cancel();
    super.dispose();
  }

  bool get _isSpecial => switch (widget.spec.kind) {
    KeyKind.shift ||
    KeyKind.backspace ||
    KeyKind.enter ||
    KeyKind.language ||
    KeyKind.layer ||
    KeyKind.emoji => true,
    _ => false,
  };

  bool get _isAccent => widget.spec.kind == KeyKind.enter;

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final base = _isAccent
        ? colors.accent
        : _isSpecial
            ? colors.keySpecial
            : colors.key;
    // Darken whatever the key is, so the accent and special keys read pressed
    // too; a single pressed colour looked wrong on the purple Enter key.
    final background = _pressed
        ? Color.alphaBlend(const Color(0x38000000), base)
        : widget.highlight
            ? colors.accentSoft
            : base;
    final foreground = _isAccent
        ? const Color(0xFFFFFFFF)
        : widget.highlight
            ? colors.accent
            : _isSpecial
                ? colors.inkMuted
                : colors.ink;
    return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _press(),
        onTapUp: (_) => _release(),
        onTapCancel: _release,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onLongPressUp: () {
          _release();
          widget.onLongPressUp?.call();
        },
        child: Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(widget.radius),
            boxShadow: _pressed || _isSpecial || _isAccent ? null : [kKeyShadow],
          ),
          child: Stack(
            children: [
              if (widget.spec.corner case final corner?)
                Positioned(
                  left: 5,
                  top: 3,
                  child: Text(
                    corner,
                    style: TextStyle(
                      color: colors.inkFaint,
                      fontSize: widget.fontSize * 0.45,
                      height: 1,
                    ),
                  ),
                ),
              Center(
                child: widget.spec.kind == KeyKind.space
                    // A space bar reads best as a bar, not as a glyph.
                    ? Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: foreground,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      )
                    : Text(
                  widget.label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: widget.spec.kind == KeyKind.backspace
                        ? widget.fontSize * 1.05
                        : _isSpecial
                        ? widget.fontSize * 0.72
                        : widget.fontSize,
                    fontWeight: _isSpecial
                        ? FontWeight.w500
                        : FontWeight.w500,
                    height: 1,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }
}

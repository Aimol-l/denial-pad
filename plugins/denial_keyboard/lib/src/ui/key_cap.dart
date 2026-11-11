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
  final VoidCallback? onLongPress;
  final VoidCallback? onLongPressUp;
  final double? flexOverride;

  @override
  State<KeyCap> createState() => _KeyCapState();
}

class _KeyCapState extends State<KeyCap> {
  bool _pressed = false;

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
    final background = _pressed
        ? colors.keyPressed
        : _isAccent
            ? colors.accent
            : _isSpecial
                ? colors.keySpecial
                : colors.key;
    final foreground = _isAccent
        ? const Color(0xFFFFFFFF)
        : _isSpecial
            ? colors.inkMuted
            : colors.ink;
    return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onLongPressUp: widget.onLongPressUp,
        child: Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(widget.radius),
            boxShadow: _isSpecial || _isAccent ? null : [kKeyShadow],
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
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: _isSpecial
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

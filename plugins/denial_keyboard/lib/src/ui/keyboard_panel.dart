import 'dart:async';

import 'package:flutter/material.dart';

import '../bridge/keyboard_backend.dart';
import 'package:denial_keyboard_core/denial_keyboard_core.dart';
import 'key_cap.dart';
import 'keyboard_theme.dart';

/// The keyboard surface: a two-state header (toolbar while idle, preedit and
/// candidates while typing) over four rows of keys.
///
/// The panel paints itself but is positioned by [FloatingKeyboard]; candidates
/// are supplied by the host, which is what the fcitx5 bridge will feed later.
class KeyboardPanel extends StatefulWidget {
  const KeyboardPanel({
    super.key,
    required this.backend,
    required this.width,
    required this.height,
    this.colors = const KeyboardColors(),
    this.preedit,
    this.candidates = const [],
    this.onSelectCandidate,
    this.onHaptic,
    this.onClose,
    this.onLayoutChanged,
  });

  final KeyboardBackend backend;
  final double width;
  final double height;
  final KeyboardColors colors;

  /// Pinyin buffer shown in the header while typing.
  final String? preedit;
  final List<String> candidates;
  final ValueChanged<int>? onSelectCandidate;

  /// Called on every accepted key press; the host turns this into a pulse.
  final VoidCallback? onHaptic;

  final VoidCallback? onClose;
  final VoidCallback? onLayoutChanged;

  @override
  State<KeyboardPanel> createState() => _KeyboardPanelState();
}

class _KeyboardPanelState extends State<KeyboardPanel> {
  ShiftState _shift = ShiftState.off;
  int _layer = 0;
  DateTime? _lastSpace;
  Timer? _repeat;

  bool get _typing =>
      (widget.preedit != null && widget.preedit!.isNotEmpty) ||
      widget.candidates.isNotEmpty;

  List<KeyRow> get _rows => switch (_layer) {
    1 => digitsLayout(),
    2 => symbolsLayout(),
    _ => lettersLayout(),
  };

  @override
  void dispose() {
    _repeat?.cancel();
    super.dispose();
  }

  void _pulse() => widget.onHaptic?.call();

  void _type(String text) {
    if (text.isEmpty) return;
    widget.backend.typeText(text);
    setState(() => _shift = afterCharacter(_shift, text));
  }

  void _onKey(KeySpec spec) {
    _pulse();
    switch (spec.kind) {
      case KeyKind.shift:
        setState(() => _shift = nextOnTap(_shift));
      case KeyKind.backspace:
        widget.backend.pressKey('BackSpace');
      case KeyKind.enter:
        widget.backend.pressKey('Return');
      case KeyKind.space:
        final now = DateTime.now();
        final last = _lastSpace;
        _lastSpace = now;
        if (last != null && now.difference(last) < const Duration(milliseconds: 400)) {
          _type('. ');
        } else {
          _type(' ');
        }
      case KeyKind.layer:
        setState(() {
          _layer = switch (spec.label) {
            '123' => 1,
            '符' => 2,
            _ => 0,
          };
        });
        widget.onLayoutChanged?.call();
      case KeyKind.emoji:
      case KeyKind.language:
        break;
      case KeyKind.letter:
      case KeyKind.digit:
      case KeyKind.symbol:
        _type(spec.labelFor(shift: _shift != ShiftState.off));
    }
  }

  void _startRepeat(KeySpec spec) {
    if (spec.kind != KeyKind.backspace) return;
    _repeat?.cancel();
    _repeat = Timer(const Duration(milliseconds: 400), () {
      _repeat = Timer.periodic(const Duration(milliseconds: 55), (_) {
        widget.backend.pressKey('BackSpace');
      });
    });
  }

  void _stopRepeat() {
    _repeat?.cancel();
    _repeat = null;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final metrics = keyboardMetrics(
      panelWidth: widget.width,
      panelHeight: widget.height,
      rows: rows.length,
    );
    final colors = widget.colors;
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: colors.panel,
        borderRadius: BorderRadius.circular(kKeyboardRadius),
        border: Border.all(color: colors.panelBorder),
        boxShadow: const [
          BoxShadow(color: Color(0x2E14161C), blurRadius: 40, offset: Offset(0, 18)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(
        kPanelPadding,
        8,
        kPanelPadding,
        kPanelPadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: kHeaderHeight, child: _buildHeader(colors)),
          const SizedBox(height: kRowGap),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: kRowGap),
            _buildRow(rows[i], metrics, colors),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(KeyboardColors colors) {
    if (!_typing) return _buildToolbar(colors);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: kHeaderHeight - kCandidateStripHeight,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.preedit ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.ink,
                    fontSize: 18,
                    height: 1.2,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
              Icon(Icons.cloud_outlined, size: 16, color: colors.inkFaint),
              const SizedBox(width: 14),
              Icon(Icons.keyboard_alt_outlined, size: 16, color: colors.accent),
            ],
          ),
        ),
        SizedBox(
          height: kCandidateStripHeight,
          child: Row(
            children: [
              for (var i = 0; i < widget.candidates.length; i++)
                Flexible(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => widget.onSelectCandidate?.call(i),
                    child: Container(
                      margin: const EdgeInsets.only(right: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: i == 0 ? colors.accentSoft : null,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        widget.candidates[i],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: i == 0 ? colors.accent : colors.ink,
                          fontSize: 15,
                          height: 1.1,
                          fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w400,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              Icon(Icons.chevron_right, size: 18, color: colors.inkFaint),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar(KeyboardColors colors) {
    return Row(
      children: [
        Icon(Icons.grid_view_rounded, size: 17, color: colors.inkFaint),
        const SizedBox(width: 26),
        Icon(Icons.emoji_emotions_outlined, size: 17, color: colors.inkFaint),
        const SizedBox(width: 26),
        Icon(Icons.keyboard_voice_outlined, size: 17, color: colors.inkFaint),
        const Spacer(),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onClose,
          child: Icon(Icons.keyboard_arrow_down_rounded, size: 22, color: colors.inkMuted),
        ),
      ],
    );
  }

  Widget _buildRow(KeyRow row, KeyboardMetrics metrics, KeyboardColors colors) {
    return Expanded(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: row.inset),
        child: Row(
          children: [
            for (var i = 0; i < row.keys.length; i++) ...[
              if (i > 0) const SizedBox(width: kRowGap),
              Expanded(
                flex: (row.keys[i].flex * 1000).round(),
                child: KeyCap(
                  spec: row.keys[i],
                  label: row.keys[i].labelFor(shift: _shift != ShiftState.off),
                  colors: colors,
                  height: metrics.rowHeight,
                  fontSize: metrics.fontSize,
                  radius: metrics.keyRadius,
                  onTap: () => _onKey(row.keys[i]),
                  onLongPress: row.keys[i].kind == KeyKind.backspace
                      ? () => _startRepeat(row.keys[i])
                      : null,
                  onLongPressUp: _stopRepeat,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../bridge/keyboard_backend.dart';
import 'package:denial_keyboard_core/denial_keyboard_core.dart';
import 'key_cap.dart';
import 'keyboard_theme.dart';
import 'numpad_page.dart';
import 'scrollable_page.dart';
import 'symbols_page.dart';

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
    this.highlighted = 0,
    this.hasPrev = false,
    this.hasNext = false,
    this.onSelectCandidate,
    this.onPageTurn,
    this.onHaptic,
    this.onClose,
    this.onLayoutChanged,
    this.onLockChanged,
  });

  final KeyboardBackend backend;
  final double width;
  final double height;
  final KeyboardColors colors;

  /// Pinyin buffer shown in the header while typing.
  final String? preedit;
  final List<String> candidates;

  /// The candidate Space would commit.
  final int highlighted;
  final bool hasPrev;
  final bool hasNext;
  final ValueChanged<int>? onSelectCandidate;

  /// Asks the input method for the next or previous page of candidates.
  final ValueChanged<bool>? onPageTurn;

  /// Called on every accepted key press; the host turns this into a pulse.
  final VoidCallback? onHaptic;

  final VoidCallback? onClose;
  final VoidCallback? onLayoutChanged;

  /// The symbol page's lock: while on, the host keeps the keyboard open.
  final ValueChanged<bool>? onLockChanged;

  @override
  State<KeyboardPanel> createState() => _KeyboardPanelState();
}

class _KeyboardPanelState extends State<KeyboardPanel> {
  final ScrollController _preeditScroll = ScrollController();
  String? _lastPreedit;
  ShiftState _shift = ShiftState.off;
  InputMode _mode = InputMode.latin;
  int _layer = 0;
  String _category = symbolCategories.keys.first;
  bool _locked = false;
  Timer? _repeat;
  final ScrollController _numpadRail = ScrollController();
  final ScrollController _categoryRail = ScrollController();

  bool get _typing =>
      (widget.preedit != null && widget.preedit!.isNotEmpty) ||
      widget.candidates.isNotEmpty;


  @override
  void dispose() {
    _repeat?.cancel();
    _preeditScroll.dispose();
    _numpadRail.dispose();
    _categoryRail.dispose();
    super.dispose();
  }

  void _toggleLock() {
    setState(() => _locked = !_locked);
    widget.onLockChanged?.call(_locked);
  }

  /// A long pinyin keeps growing past the strip: show the newest syllables
  /// rather than the oldest ones.
  void _followPreedit() {
    final text = widget.preedit ?? '';
    if (text == _lastPreedit) return;
    _lastPreedit = text;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_preeditScroll.hasClients) return;
      _preeditScroll.jumpTo(_preeditScroll.position.maxScrollExtent);
    });
  }

  void _pulse() => widget.onHaptic?.call();

  void _type(String text) {
    if (text.isEmpty) return;
    widget.backend.typeText(text);
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
        // Always a space: the keyboard never rewrites a key the user pressed
        // into punctuation.
        _type(' ');
      case KeyKind.layer:
        setState(() {
          _layer = switch (spec.label) {
            '123' => 1,
            '符' => 2,
            _ => 0,
          };
        });
        widget.onLayoutChanged?.call();
      case KeyKind.language:
        // The compositor's input method owns the text; this tap only asks it
        // to switch, and the label shows the mode a tap switches to.
        setState(() => _mode = _mode.toggled);
        widget.backend.pressKey('LangSwitch');
      case KeyKind.emoji:
        break;
      case KeyKind.period:
        _type(_mode.period);
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
    final metrics = keyboardMetrics(
      panelWidth: widget.width,
      panelHeight: widget.height,
    );
    final colors = widget.colors;
    Widget key(
      KeySpec spec,
      double height, {
      double? fontSize,
      VoidCallback? onTap,
      bool highlight = false,
    }) => KeyCap(
      spec: spec,
      label: spec.label,
      colors: colors,
      height: height,
      fontSize: fontSize ?? metrics.fontSize,
      radius: metrics.keyRadius,
      highlight: highlight,
      onTap: onTap ?? () => _onKey(spec),
      onLongPress: spec.kind == KeyKind.backspace
          ? () => _startRepeat(spec)
          : null,
      onLongPressUp: _stopRepeat,
    );
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
          Expanded(
            child: switch (_layer) {
              1 => NumpadPage(
                colors: colors,
                fontSize: metrics.fontSize,
                buildKey: key,
                scrollController: _numpadRail,
              ),
              2 => SymbolsPage(
                colors: colors,
                fontSize: metrics.fontSize,
                rowHeight: metrics.rowHeight,
                category: _category,
                buildKey: key,
                onCategory: (name) => setState(() => _category = name),
                locked: _locked,
                onToggleLock: _toggleLock,
                categoryController: _categoryRail,
              ),
              _ => _buildLetterRows(metrics, colors),
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLetterRows(KeyboardMetrics metrics, KeyboardColors colors) {
    final rows = lettersLayout();
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: kRowGap),
          _buildRow(rows[i], metrics, colors),
        ],
      ],
    );
  }

  Widget _buildHeader(KeyboardColors colors) {
    if (!_typing) return _buildToolbar(colors);
    _followPreedit();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: kHeaderHeight - kCandidateStripHeight,
          child: Row(
            children: [
              Expanded(
                child: QuietScroll(
                  child: SingleChildScrollView(
                  controller: _preeditScroll,
                  scrollDirection: Axis.horizontal,
                  child: Text(
                    widget.preedit ?? '',
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      color: colors.ink,
                      fontSize: 20,
                      height: 1.2,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  ),
                ),
              ),
              Icon(Icons.cloud_outlined, size: 18, color: colors.inkFaint),
              const SizedBox(width: 14),
              Icon(Icons.keyboard_alt_outlined, size: 18, color: colors.accent),
            ],
          ),
        ),
        SizedBox(
          height: kCandidateStripHeight,
          child: Row(
            children: [
              if (widget.hasPrev)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => widget.onPageTurn?.call(false),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      Icons.chevron_left,
                      size: 18,
                      color: colors.inkMuted,
                    ),
                  ),
                ),
              // Candidates size to their own text and scroll sideways; the
              // page arrow stays on the right edge, so a tap on it never lands
              // on a candidate.
              Expanded(
                child: QuietScroll(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < widget.candidates.length; i++)
                          _candidateChip(colors, i),
                      ],
                    ),
                  ),
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.hasNext
                    ? () => widget.onPageTurn?.call(true)
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: widget.hasNext ? colors.inkMuted : colors.inkFaint,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _candidateChip(KeyboardColors colors, int index) {
    final highlighted = index == widget.highlighted;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onSelectCandidate?.call(index),
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: highlighted ? colors.accentSoft : null,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          widget.candidates[index],
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            color: highlighted ? colors.accent : colors.ink,
            fontSize: 19,
            height: 1.1,
            fontWeight: highlighted ? FontWeight.w600 : FontWeight.w400,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar(KeyboardColors colors) {
    return Row(
      children: [
        Icon(Icons.grid_view_rounded, size: 21, color: colors.inkFaint),
        const SizedBox(width: 26),
        Icon(Icons.emoji_emotions_outlined, size: 21, color: colors.inkFaint),
        const SizedBox(width: 26),
        Icon(Icons.keyboard_voice_outlined, size: 21, color: colors.inkFaint),
        const Spacer(),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onClose,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 2, 4),
            child: Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 30,
              color: colors.inkMuted,
            ),
          ),
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
                  label: switch (row.keys[i].kind) {
                    KeyKind.language => _mode.keyLabel,
                    KeyKind.period => _mode.period,
                    KeyKind.shift => '⇧',
                    _ => row.keys[i].labelFor(shift: _shift != ShiftState.off),
                  },
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

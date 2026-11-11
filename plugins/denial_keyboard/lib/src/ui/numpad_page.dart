import 'package:flutter/widgets.dart';

import 'package:denial_keyboard_core/denial_keyboard_core.dart';
import 'keyboard_theme.dart';
import 'scrollable_page.dart';

/// Builds one key cap for a page. The panel owns the shared styling and the
/// long-press repeat, so pages only describe which keys they need.
typedef KeyCapFactory =
    Widget Function(
      KeySpec spec,
      double height, {
      double? fontSize,
      VoidCallback? onTap,
      bool highlight,
    });

/// The phone keypad behind the `123` key: scrollable symbols on the left, the
/// digit grid in the middle, delete/point/@ on the right, and one bottom row
/// whose keys share the same five columns, so everything lines up.
class NumpadPage extends StatelessWidget {
  const NumpadPage({
    super.key,
    required this.colors,
    required this.fontSize,
    required this.buildKey,
    this.scrollController,
  });

  final KeyboardColors colors;
  final double fontSize;
  final KeyCapFactory buildKey;

  /// Kept by the panel so the rail remembers its position across page turns.
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = kRowGap;
        final rowHeight = (constraints.maxHeight - gap * 3) / 4;
        final railHeight = rowHeight * 3 + gap * 2;

        Widget key(KeySpec spec) => buildKey(spec, rowHeight);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 55,
              child: Column(
                children: [
                  SizedBox(
                    height: railHeight,
                    child: QuietScroll(
                      child: ListView.separated(
                        controller: scrollController,
                        padding: EdgeInsets.zero,
                        itemCount: numpadSymbols.length,
                        separatorBuilder: (_, _) => const SizedBox(height: gap),
                        itemBuilder: (context, index) => buildKey(
                          KeySpec(numpadSymbols[index], kind: KeyKind.symbol),
                          rowHeight,
                          fontSize: fontSize * 0.9,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: gap),
                  SizedBox(
                    height: rowHeight,
                    child: key(const KeySpec('符', kind: KeyKind.layer)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: gap),
            Expanded(
              flex: 100,
              child: _column(rowHeight, [
                const KeySpec('1', kind: KeyKind.digit),
                const KeySpec('4', kind: KeyKind.digit),
                const KeySpec('7', kind: KeyKind.digit),
                const KeySpec('返回', kind: KeyKind.layer),
              ], key),
            ),
            const SizedBox(width: gap),
            Expanded(
              flex: 100,
              child: _column(rowHeight, [
                const KeySpec('2', kind: KeyKind.digit),
                const KeySpec('5', kind: KeyKind.digit),
                const KeySpec('8', kind: KeyKind.digit),
                const KeySpec('0', kind: KeyKind.digit),
              ], key),
            ),
            const SizedBox(width: gap),
            Expanded(
              flex: 100,
              child: _column(rowHeight, [
                const KeySpec('3', kind: KeyKind.digit),
                const KeySpec('6', kind: KeyKind.digit),
                const KeySpec('9', kind: KeyKind.digit),
                const KeySpec(' ', kind: KeyKind.space),
              ], key),
            ),
            const SizedBox(width: gap),
            Expanded(
              flex: 55,
              child: _column(rowHeight, [
                const KeySpec('⌫', kind: KeyKind.backspace),
                const KeySpec('.', kind: KeyKind.symbol),
                const KeySpec('@', kind: KeyKind.symbol),
                const KeySpec('↵', kind: KeyKind.enter),
              ], key),
            ),
          ],
        );
      },
    );
  }

  Widget _column(
    double rowHeight,
    List<KeySpec> specs,
    Widget Function(KeySpec spec) key,
  ) {
    return Column(
      children: [
        for (var index = 0; index < specs.length; index += 1) ...[
          if (index > 0) const SizedBox(height: kRowGap),
          SizedBox(height: rowHeight, child: key(specs[index])),
        ],
      ],
    );
  }
}

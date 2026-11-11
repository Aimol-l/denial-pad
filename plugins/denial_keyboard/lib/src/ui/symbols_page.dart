import 'package:flutter/widgets.dart';

import 'package:denial_keyboard_core/denial_keyboard_core.dart';
import 'keyboard_theme.dart';
import 'numpad_page.dart' show KeyCapFactory;
import 'scrollable_page.dart';

/// The symbol page: a scrollable category rail on the left with the lock and
/// back keys pinned below it, and the selected category's symbols as a
/// scrollable four-column grid on the right.
class SymbolsPage extends StatelessWidget {
  const SymbolsPage({
    super.key,
    required this.colors,
    required this.fontSize,
    required this.rowHeight,
    required this.category,
    required this.buildKey,
    required this.onCategory,
    required this.locked,
    required this.onToggleLock,
    this.categoryController,
  });

  final KeyboardColors colors;
  final double fontSize;
  final double rowHeight;
  final String category;
  final KeyCapFactory buildKey;
  final ValueChanged<String> onCategory;
  final bool locked;
  final VoidCallback onToggleLock;

  /// Kept by the panel so the rail remembers its position.
  final ScrollController? categoryController;

  @override
  Widget build(BuildContext context) {
    final symbols = symbolCategories[category] ?? const <String>[];
    // The two pinned keys are shorter than a grid row, so the category rail
    // keeps three tiles in view.
    final lockHeight = rowHeight * 0.8;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 55,
          child: Column(
            children: [
              Expanded(
                child: QuietScroll(
                  child: ListView.builder(
                  controller: categoryController,
                  padding: EdgeInsets.zero,
                  itemCount: symbolCategories.length,
                  itemBuilder: (context, index) {
                    final name = symbolCategories.keys.elementAt(index);
                    return _categoryTile(name, name == category);
                  },
                ),
                ),
              ),
              const SizedBox(height: kRowGap),
              SizedBox(
                height: rowHeight,
                child: buildKey(
                  const KeySpec('锁', kind: KeyKind.language),
                  lockHeight,
                  fontSize: fontSize * 0.8,
                  onTap: onToggleLock,
                  highlight: locked,
                ),
              ),
              const SizedBox(height: kRowGap),
              SizedBox(
                height: lockHeight,
                child: buildKey(
                  const KeySpec('返回', kind: KeyKind.layer),
                  lockHeight,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: kRowGap),
        Expanded(
          flex: 400,
          child: QuietScroll(
            child: GridView.builder(
            padding: EdgeInsets.zero,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisExtent: rowHeight,
              mainAxisSpacing: kRowGap,
              crossAxisSpacing: kRowGap,
            ),
            itemCount: symbols.length,
            itemBuilder: (context, index) {
              final symbol = symbols[index];
              return buildKey(
                KeySpec(symbol, kind: KeyKind.symbol),
                rowHeight,
                fontSize: symbol.runes.length > 2 ? fontSize * 0.6 : fontSize,
              );
            },
          ),
          ),
        ),
      ],
    );
  }

  Widget _categoryTile(String name, bool selected) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onCategory(name),
      child: Container(
        height: 44,
        margin: const EdgeInsets.only(bottom: kRowGap),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? colors.keySpecial : colors.key,
          borderRadius: BorderRadius.circular(12),
          boxShadow: selected ? null : [kKeyShadow],
        ),
        child: Text(
          name,
          style: TextStyle(
            color: selected ? colors.ink : colors.inkMuted,
            fontSize: 15,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}

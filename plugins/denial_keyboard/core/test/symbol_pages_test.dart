import 'package:denial_keyboard_core/denial_keyboard_core.dart';
import 'package:test/test.dart';

void main() {
  test('every category carries enough symbols for a full grid', () {
    expect(symbolCategories.keys, contains('常用'));
    expect(symbolCategories.keys, contains('希腊'));
    for (final entry in symbolCategories.entries) {
      expect(
        entry.value.length,
        greaterThanOrEqualTo(24),
        reason: '${entry.key} should fill at least six grid rows',
      );
    }
  });

  test('categories are ordered as the rail shows them', () {
    expect(symbolCategories.keys.take(4), ['常用', '中文', '英文', '网络']);
    expect(symbolCategories.length, 14);
  });

  test('no category repeats a symbol', () {
    for (final entry in symbolCategories.entries) {
      expect(
        entry.value.toSet().length,
        entry.value.length,
        reason: '${entry.key} repeats a symbol',
      );
    }
  });

  test('the number page rail starts with the arithmetic symbols', () {
    expect(numpadSymbols.take(4), ['%', '/', '-', '+']);
    expect(numpadSymbols.length, greaterThan(12));
  });
}

import 'package:denial_keyboard_core/denial_keyboard_core.dart';
import 'package:test/test.dart';

void main() {
  test('letters layout has four rows and a full qwerty top row', () {
    final rows = lettersLayout();
    expect(rows.length, 4);
    expect(rows.first.keys.length, 10);
    expect(rows.first.keys.map((k) => k.label).join(), 'qwertyuiop');
  });

  test('digits ride in the corner of the top row', () {
    final top = lettersLayout().first.keys;
    expect(top.first.corner, '1');
    expect(top.last.corner, '0');
  });

  test('function keys keep their flex so the space bar is widest', () {
    final bottom = lettersLayout().last;
    final space = bottom.keys.firstWhere((k) => k.kind == KeyKind.space);
    expect(space.flex, greaterThan(3));
  });

  test('digits and symbols layers stay at four rows', () {
    expect(digitsLayout().length, 4);
    expect(symbolsLayout().length, 4);
  });

  test('every layer has a backspace and an enter', () {
    for (final rows in [lettersLayout(), digitsLayout(), symbolsLayout()]) {
      final kinds = rows.expand((r) => r.keys).map((k) => k.kind).toSet();
      expect(kinds, containsAll([KeyKind.backspace, KeyKind.enter]));
    }
  });
}

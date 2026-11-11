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

  test('the letters layer has a backspace, enter and both layer keys', () {
    final kinds = lettersLayout().expand((r) => r.keys).map((k) => k.kind);
    expect(kinds, contains(KeyKind.backspace));
    expect(kinds, contains(KeyKind.enter));
    final layers = lettersLayout()
        .expand((r) => r.keys)
        .where((k) => k.kind == KeyKind.layer)
        .map((k) => k.label);
    expect(layers, containsAll(['符', '123']));
  });
}

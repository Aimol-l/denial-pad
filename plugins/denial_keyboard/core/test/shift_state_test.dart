import 'package:denial_keyboard_core/denial_keyboard_core.dart';
import 'package:test/test.dart';

void main() {
  test('the shift key toggles capitals on and off', () {
    expect(nextOnTap(ShiftState.off), ShiftState.locked);
    expect(nextOnTap(ShiftState.locked), ShiftState.off);
  });

  test('applyCase only touches letters', () {
    expect(applyCase('q', ShiftState.locked), 'Q');
    expect(applyCase('1', ShiftState.locked), '1');
    expect(applyCase('!', ShiftState.locked), '!');
  });
}

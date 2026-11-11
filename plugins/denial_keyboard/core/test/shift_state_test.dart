import 'package:denial_keyboard_core/denial_keyboard_core.dart';
import 'package:test/test.dart';

void main() {
  test('tap cycles off -> once -> locked -> off', () {
    expect(nextOnTap(ShiftState.off), ShiftState.once);
    expect(nextOnTap(ShiftState.once), ShiftState.locked);
    expect(nextOnTap(ShiftState.locked), ShiftState.off);
  });

  test('once resets after a letter but locked does not', () {
    expect(afterCharacter(ShiftState.once, 'a'), ShiftState.off);
    expect(afterCharacter(ShiftState.locked, 'a'), ShiftState.locked);
  });

  test('sentence end re-arms auto capitals', () {
    expect(afterCharacter(ShiftState.off, '.'), ShiftState.once);
    expect(afterCharacter(ShiftState.off, '。'), ShiftState.once);
    expect(afterCharacter(ShiftState.off, 'a'), ShiftState.off);
  });

  test('applyCase only touches letters', () {
    expect(applyCase('q', ShiftState.once), 'Q');
    expect(applyCase('1', ShiftState.locked), '1');
    expect(applyCase('!', ShiftState.once), '!');
  });
}

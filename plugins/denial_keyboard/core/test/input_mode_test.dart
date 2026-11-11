import 'package:test/test.dart';

import 'package:denial_keyboard_core/denial_keyboard_core.dart';

void main() {
  test('the language key alternates between Chinese and Latin', () {
    expect(InputMode.latin.toggled, InputMode.chinese);
    expect(InputMode.chinese.toggled, InputMode.latin);
  });

  test('the language key shows the mode a tap switches to', () {
    expect(InputMode.latin.keyLabel, '中');
    expect(InputMode.chinese.keyLabel, '英');
  });
}

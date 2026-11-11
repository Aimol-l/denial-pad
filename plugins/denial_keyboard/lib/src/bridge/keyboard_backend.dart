import 'package:denial_keyboard_core/denial_keyboard_core.dart';

/// What the keyboard does with a press. The host implements this with the
/// compositor's text-input bridge; tests use [FakeKeyboardBackend].
abstract class KeyboardBackend {
  /// Types [text] at the cursor, replacing the selection if there is one.
  void typeText(String text);

  /// Presses a named key, in XKB keysym spelling (`BackSpace`, `Return`).
  void pressKey(String name);

  /// Replaces [replaced] with [text], used by autocorrect.
  void replaceText(String replaced, String text);
}

class FakeKeyboardBackend implements KeyboardBackend {
  final StringBuffer typed = StringBuffer();
  final List<String> keys = [];
  final List<(String, String)> replacements = [];
  int backspaces = 0;

  @override
  void typeText(String text) => typed.write(text);

  @override
  void pressKey(String name) {
    keys.add(name);
    if (name == 'BackSpace') backspaces++;
  }

  @override
  void replaceText(String replaced, String text) =>
      replacements.add((replaced, text));
}

/// Maps the keyboard's own key kinds to the names the compositor understands.
String? keyNameFor(KeyKind kind) {
  switch (kind) {
    case KeyKind.backspace:
      return 'BackSpace';
    case KeyKind.enter:
      return 'Return';
    case KeyKind.space:
      return 'space';
    case KeyKind.shift:
    case KeyKind.language:
    case KeyKind.period:
    case KeyKind.layer:
    case KeyKind.emoji:
    case KeyKind.letter:
    case KeyKind.digit:
    case KeyKind.symbol:
      return null;
  }
}

import 'package:denial_flutter_sdk/keyboard_policy.dart'
    show softwareKeyboardWanted;
import 'package:test/test.dart';

void main() {
  test('a tap outside a field does not open an application panel', () {
    // The app keeps a text editor open; the person taps its title bar. The
    // editor does not answer, so nothing asks to type.
    expect(
      softwareKeyboardWanted(
        shellEditor: false,
        dismissed: false,
        touched: true,
        activated: false,
        pendingTouch: false,
      ),
      isFalse,
    );
  });

  test('a tap the editor answers opens the panel', () {
    expect(
      softwareKeyboardWanted(
        shellEditor: false,
        dismissed: true,
        touched: true,
        activated: true,
        pendingTouch: false,
      ),
      isTrue,
    );
  });

  test('a tap just before an app enables its editor opens the panel', () {
    expect(
      softwareKeyboardWanted(
        shellEditor: false,
        dismissed: false,
        touched: false,
        activated: false,
        pendingTouch: true,
      ),
      isTrue,
    );
  });

  test('an app panel opens without a tap when the app answers no touch', () {
    expect(
      softwareKeyboardWanted(
        shellEditor: false,
        dismissed: false,
        touched: false,
        activated: false,
        pendingTouch: false,
      ),
      isFalse,
    );
  });

  test('a shell field opens with its focus and ignores stray touches', () {
    expect(
      softwareKeyboardWanted(
        shellEditor: true,
        dismissed: false,
        touched: false,
        activated: false,
        pendingTouch: false,
      ),
      isTrue,
    );
    expect(
      softwareKeyboardWanted(
        shellEditor: true,
        dismissed: true,
        touched: true,
        activated: false,
        pendingTouch: false,
      ),
      isTrue,
    );
    expect(
      softwareKeyboardWanted(
        shellEditor: true,
        dismissed: true,
        touched: false,
        activated: false,
        pendingTouch: false,
      ),
      isFalse,
    );
  });
}

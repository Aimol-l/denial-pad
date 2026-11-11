import 'package:meta/meta.dart';

/// What pressing a key does before any text is produced.
enum KeyKind {
  letter,
  digit,
  symbol,
  shift,
  backspace,
  enter,
  space,
  language,
  layer,
  emoji,
}

@immutable
class KeySpec {
  const KeySpec(
    this.label, {
    this.kind = KeyKind.letter,
    this.flex = 1,
    this.corner,
    this.shifted,
  });

  final String label;
  final KeyKind kind;

  /// Weight inside its row; 1 is a normal key, larger values are the space bar.
  final double flex;

  /// Small label in the top-left corner, used for the digits that ride on the
  /// QWERTY row instead of taking a row of their own.
  final String? corner;

  /// Label used while shift is active; defaults to the uppercased label.
  final String? shifted;

  String labelFor({required bool shift}) {
    if (!shift) return label;
    return shifted ?? label.toUpperCase();
  }
}

@immutable
class KeyRow {
  const KeyRow(this.keys, {this.inset = 0});

  final List<KeySpec> keys;

  /// Horizontal padding that keeps the A row narrower than the Q row.
  final double inset;
}

const _digits = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'];
const _qwerty = ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'];
const _home = ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'];
const _bottom = ['z', 'x', 'c', 'v', 'b', 'n', 'm'];

/// The letter layer. Digits sit in the corner of the top row, which is what
/// keeps the panel at four rows.
List<KeyRow> lettersLayout({bool numberRow = false}) {
  return [
    if (numberRow)
      KeyRow([
        for (final digit in _digits)
          KeySpec(digit, kind: KeyKind.digit, shifted: '@'),
      ]),
    KeyRow([
      for (var i = 0; i < _qwerty.length; i++)
        KeySpec(_qwerty[i], corner: _digits[i]),
    ]),
    KeyRow([
      for (final letter in _home) KeySpec(letter),
    ], inset: 26),
    KeyRow([
      const KeySpec('⇧', kind: KeyKind.shift, flex: 1.5),
      for (final letter in _bottom) KeySpec(letter),
      const KeySpec('⌫', kind: KeyKind.backspace, flex: 1.5),
    ]),
    KeyRow([
      const KeySpec('符', kind: KeyKind.layer),
      const KeySpec('123', kind: KeyKind.layer),
      const KeySpec(',', kind: KeyKind.symbol),
      const KeySpec('🎙', kind: KeyKind.space, flex: 3.4),
      const KeySpec('。', kind: KeyKind.symbol),
      const KeySpec('中/英', kind: KeyKind.language, flex: 1.3),
      const KeySpec('↵', kind: KeyKind.enter, flex: 1.4),
    ]),
  ];
}

/// Digits and punctuation, reached with the `123` key.
List<KeyRow> digitsLayout() {
  return const [
    KeyRow([
      KeySpec('1', kind: KeyKind.digit),
      KeySpec('2', kind: KeyKind.digit),
      KeySpec('3', kind: KeyKind.digit),
      KeySpec('4', kind: KeyKind.digit),
      KeySpec('5', kind: KeyKind.digit),
      KeySpec('6', kind: KeyKind.digit),
      KeySpec('7', kind: KeyKind.digit),
      KeySpec('8', kind: KeyKind.digit),
      KeySpec('9', kind: KeyKind.digit),
      KeySpec('0', kind: KeyKind.digit),
    ]),
    KeyRow([
      KeySpec('@', kind: KeyKind.symbol),
      KeySpec('#', kind: KeyKind.symbol),
      KeySpec(r'$', kind: KeyKind.symbol),
      KeySpec('%', kind: KeyKind.symbol),
      KeySpec('&', kind: KeyKind.symbol),
      KeySpec('*', kind: KeyKind.symbol),
      KeySpec('(', kind: KeyKind.symbol),
      KeySpec(')', kind: KeyKind.symbol),
      KeySpec('·', kind: KeyKind.symbol),
    ], inset: 26),
    KeyRow([
      KeySpec('符', kind: KeyKind.layer),
      KeySpec('/', kind: KeyKind.symbol),
      KeySpec('"', kind: KeyKind.symbol),
      KeySpec("'", kind: KeyKind.symbol),
      KeySpec(':', kind: KeyKind.symbol),
      KeySpec(';', kind: KeyKind.symbol),
      KeySpec('!', kind: KeyKind.symbol),
      KeySpec('?', kind: KeyKind.symbol),
      KeySpec('⌫', kind: KeyKind.backspace, flex: 1.5),
    ]),
    KeyRow([
      KeySpec('ABC', kind: KeyKind.layer),
      KeySpec(',', kind: KeyKind.symbol),
      KeySpec('🎙', kind: KeyKind.space, flex: 3.4),
      KeySpec('。', kind: KeyKind.symbol),
      KeySpec('↵', kind: KeyKind.enter, flex: 1.4),
    ]),
  ];
}

/// The extra symbols layer, reached with the `符` key.
List<KeyRow> symbolsLayout() {
  return const [
    KeyRow([
      KeySpec('¥', kind: KeyKind.symbol),
      KeySpec('€', kind: KeyKind.symbol),
      KeySpec('£', kind: KeyKind.symbol),
      KeySpec('¢', kind: KeyKind.symbol),
      KeySpec('©', kind: KeyKind.symbol),
      KeySpec('®', kind: KeyKind.symbol),
      KeySpec('™', kind: KeyKind.symbol),
      KeySpec('°', kind: KeyKind.symbol),
      KeySpec('±', kind: KeyKind.symbol),
    ]),
    KeyRow([
      KeySpec('§', kind: KeyKind.symbol),
      KeySpec('∆', kind: KeyKind.symbol),
      KeySpec('∞', kind: KeyKind.symbol),
      KeySpec('≈', kind: KeyKind.symbol),
      KeySpec('≠', kind: KeyKind.symbol),
      KeySpec('≤', kind: KeyKind.symbol),
      KeySpec('≥', kind: KeyKind.symbol),
      KeySpec('√', kind: KeyKind.symbol),
      KeySpec('∑', kind: KeyKind.symbol),
    ], inset: 26),
    KeyRow([
      KeySpec('123', kind: KeyKind.layer),
      KeySpec('·', kind: KeyKind.symbol),
      KeySpec('—', kind: KeyKind.symbol),
      KeySpec('…', kind: KeyKind.symbol),
      KeySpec('“', kind: KeyKind.symbol),
      KeySpec('”', kind: KeyKind.symbol),
      KeySpec('‘', kind: KeyKind.symbol),
      KeySpec('’', kind: KeyKind.symbol),
      KeySpec('⌫', kind: KeyKind.backspace, flex: 1.5),
    ]),
    KeyRow([
      KeySpec('ABC', kind: KeyKind.layer),
      KeySpec(',', kind: KeyKind.symbol),
      KeySpec('🎙', kind: KeyKind.space, flex: 3.4),
      KeySpec('。', kind: KeyKind.symbol),
      KeySpec('↵', kind: KeyKind.enter, flex: 1.4),
    ]),
  ];
}

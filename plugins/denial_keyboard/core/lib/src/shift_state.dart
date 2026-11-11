/// Shift has three states: off, armed for one character, and locked.
enum ShiftState { off, once, locked }

ShiftState nextOnTap(ShiftState current) {
  switch (current) {
    case ShiftState.off:
      return ShiftState.once;
    case ShiftState.once:
      return ShiftState.locked;
    case ShiftState.locked:
      return ShiftState.off;
  }
}

/// What shift becomes after [text] was produced.
///
/// A one-shot shift is consumed by a single character; a locked shift survives
/// until the user taps it again. Sentence endings arm it again so the next
/// letter starts a new sentence with a capital.
ShiftState afterCharacter(ShiftState current, String text) {
  if (text.isEmpty) return current;
  if (current == ShiftState.locked) return ShiftState.locked;
  const sentenceEnd = {'.', '!', '?', '。', '！', '？', '\n'};
  if (text.runes.length == 1 && sentenceEnd.contains(text)) {
    return ShiftState.once;
  }
  return ShiftState.off;
}

/// Applies shift to a key label. Non-letters are returned unchanged.
String applyCase(String label, ShiftState state) {
  if (state == ShiftState.off || label.isEmpty) return label;
  final rune = label.runes.first;
  final isLetter = (rune >= 0x41 && rune <= 0x5A) || (rune >= 0x61 && rune <= 0x7A);
  if (!isLetter) return label;
  return label.toUpperCase();
}

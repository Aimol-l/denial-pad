/// Shift is a capitals switch: off, or locked until it is tapped again.
enum ShiftState { off, locked }

ShiftState nextOnTap(ShiftState current) =>
    current == ShiftState.locked ? ShiftState.off : ShiftState.locked;

/// Applies shift to a key label. Non-letters are returned unchanged.
String applyCase(String label, ShiftState state) {
  if (state == ShiftState.off || label.isEmpty) return label;
  final rune = label.runes.first;
  final isLetter = (rune >= 0x41 && rune <= 0x5A) || (rune >= 0x61 && rune <= 0x7A);
  if (!isLetter) return label;
  return label.toUpperCase();
}

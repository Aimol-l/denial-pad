/// When the shell's floating keyboard may open, shared with the shell host.
///
/// Kept out of `models.dart`, which pulls in rendering types, so plain Dart
/// tests can exercise the rule.
export 'src/models/software_keyboard_policy.dart' show softwareKeyboardWanted;

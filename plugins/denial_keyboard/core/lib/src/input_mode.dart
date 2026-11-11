/// Which language the keyboard is typing in.
///
/// The compositor's input method owns the actual text; this only decides what
/// the language key sends and how it looks. Both ends start in [latin], and a
/// tap sends one switch request, so they stay in step without the shell having
/// to echo the mode back.
enum InputMode {
  latin,
  chinese;

  InputMode get toggled => this == latin ? chinese : latin;

  /// The label on the language key: the mode a tap switches to.
  String get keyLabel => this == latin ? '中' : '英';
}

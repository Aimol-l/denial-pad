/// Whether the floating keyboard should open for the current text input state.
///
/// The panel belongs to the person, not to focus. An application that keeps a
/// text editor around — a document, a terminal, a browser page — must not pull
/// a keyboard up because they tapped its title bar, its toolbar or empty
/// space: only the tap that the editor answers (it moved the caret, it enabled
/// its editor, the compositor reports that as a new activation) is a tap into
/// a field. A touch that arrives just before an application enables its editor
/// counts too: that is the tap that is about to focus a field.
///
/// The shell's own fields are the shell's UI, so a tap anywhere in the shell
/// is a tap on that field by construction; there only a manual dismissal keeps
/// the panel quiet until the next touch.
bool softwareKeyboardWanted({
  required bool shellEditor,
  required bool dismissed,
  required bool touched,
  required bool activated,
  required bool pendingTouch,
}) {
  if (shellEditor) return !dismissed || touched || activated;
  return activated || pendingTouch;
}

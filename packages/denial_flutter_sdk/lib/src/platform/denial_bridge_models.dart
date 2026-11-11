import '../models/audio.dart';

enum DenialShellAction {
  applications,
  dashboard,
  overview,
  windowSwitcherNext,
  windowSwitcherPrevious,
  windowSwitcherEnd,
  clipboard,
  screenshotPrepare,
  screenshotTextureReady,
  screenshotDone,
  clientPointerPressed,
  wallpaper,
  openSettings,
  workspaceChanged,
  focusLeft,
  focusRight,
  focusUp,
  focusDown,

  /// deniald captured a full-screen screenshot (Power plus Volume Down).
  screenshotCaptured,
}

class DenialShellActionEvent {
  const DenialShellActionEvent({
    required this.action,
    required this.monitorId,
    required this.requestId,
    required this.textureId,
    required this.workspaceId,
  });

  final DenialShellAction action;
  final int? monitorId;
  final int requestId;
  final int? textureId;
  final int? workspaceId;
}

// The bridge and services share these immutable snapshots without remapping.
typedef DenialAudioState = AudioLevelState;
typedef DenialAudioStream = AppAudioStream;
typedef DenialAudioDevice = AudioOutputDevice;

class DenialBrightnessState {
  const DenialBrightnessState({
    required this.monitorId,
    required this.level,
    this.completesRead = false,
  });

  final int monitorId;
  final double level;

  /// Whether this update satisfied an explicit state read from Dart.
  ///
  /// Reconciliation reads seed controls but must not present the transient
  /// brightness HUD as though the user changed the hardware level.
  final bool completesRead;
}

class DenialSoftwareDimmingState {
  const DenialSoftwareDimmingState({
    required this.monitorId,
    required this.level,
    required this.supported,
    this.completesRead = false,
  });

  final int monitorId;
  final double level;
  final bool supported;
  final bool completesRead;
}

class DenialTextInputState {
  const DenialTextInputState({
    required this.active,
    required this.inputPanelVisible,
    required this.legacy,
    required this.contentHint,
    required this.contentPurpose,
    this.activationSerial = 0,
    this.touchEpoch = 0,
    this.flutterEditor = false,
  });

  final bool active;
  final bool inputPanelVisible;
  final bool legacy;
  final int contentHint;
  final int contentPurpose;
  final int activationSerial;

  /// Counts touches inside application windows; the keyboard opens only when
  /// this changes.
  final int touchEpoch;

  /// The editor is one of the shell's own Flutter text fields.
  final bool flutterEditor;
}

/// The input method's composition, drawn by the shell keyboard.
class DenialKeyboardCandidates {
  const DenialKeyboardCandidates({
    this.preedit = '',
    this.items = const <String>[],
    this.highlighted = 0,
    this.hasPrev = false,
    this.hasNext = false,
  });

  /// The pinyin (or other) line being composed.
  final String preedit;

  /// Candidate text in the input method's order.
  final List<String> items;

  /// Index in [items] that Space commits.
  final int highlighted;

  /// More candidates exist before or after this page.
  final bool hasPrev;
  final bool hasNext;

  bool get isEmpty => preedit.isEmpty && items.isEmpty;

  @override
  bool operator ==(Object other) {
    if (other is! DenialKeyboardCandidates ||
        other.preedit != preedit ||
        other.highlighted != highlighted ||
        other.hasPrev != hasPrev ||
        other.hasNext != hasNext ||
        other.items.length != items.length) {
      return false;
    }
    for (var index = 0; index < items.length; index += 1) {
      if (items[index] != other.items[index]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    preedit,
    Object.hashAll(items),
    highlighted,
    hasPrev,
    hasNext,
  );
}

/// Suggestions for the word the software keyboard is typing.
class DenialTextPrediction {
  const DenialTextPrediction({
    required this.serial,
    required this.word,
    required this.correction,
    required this.suggestions,
    required this.languages,
  });

  /// The serial of the request this answers.
  final int serial;
  final String word;

  /// What a space commits instead of [word], when it looks mistyped.
  final String? correction;

  /// Other words, best first; never [word] or [correction].
  final List<String> suggestions;

  /// The languages the suggestions come from, such as `en` and `it`.
  final List<String> languages;
}

class DenialSettingsDocument {
  const DenialSettingsDocument({required this.revision, required this.json});

  final int revision;
  final String json;
}

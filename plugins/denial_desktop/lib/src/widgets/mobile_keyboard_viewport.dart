import 'package:denial_desktop/src/state/reference_shell_controller.dart';
import 'package:denial_desktop/src/state/reference_shell_metrics.dart';
import 'package:denial_desktop/src/state/reference_shell_state.dart';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:denial_flutter_sdk/rendering.dart';

/// Moves mobile content with the shell's keyboard viewport.
///
/// The software keyboard itself is gone (to be redesigned), so the viewport
/// stays at rest; the wrapper remains so surfaces keep their layout contract
/// when the replacement keyboard returns.
class MobileKeyboardViewport extends ConsumerStatefulWidget {
  const MobileKeyboardViewport({
    required this.child,
    this.appScene = false,
    super.key,
  });

  final Widget child;

  /// The application scene stays in place while its primary window lays
  /// itself out around the keyboard (denial-insets-v1 keyboard inset).
  final bool appScene;

  @override
  ConsumerState<MobileKeyboardViewport> createState() =>
      _MobileKeyboardViewportState();
}

class _MobileKeyboardViewportState
    extends ConsumerState<MobileKeyboardViewport> {
  final _translation = ValueNotifier(Offset.zero);
  double _panelHeight = 0;

  void _updateTranslation(({double progress, double scroll}) position) {
    final keyboardOffset = _panelHeight * position.progress;
    final scroll = position.scroll.clamp(0.0, keyboardOffset);
    _translation.value = Offset(0, -(keyboardOffset - scroll));
  }

  ({double progress, double scroll}) _position(ReferenceShellState state) => (
    progress: widget.appScene && state.primaryWindowHandlesKeyboard
        ? 0.0
        : state.edgePanelDragProgress,
    scroll: state.edgePanelViewportScroll,
  );

  @override
  void dispose() {
    _translation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      referenceShellProvider.select(_position),
      (_, next) => _updateTranslation(next),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        _panelHeight = ReferenceShellMetrics.edgePanelHeight(
          constraints.biggest,
        );
        _updateTranslation(_position(ref.read(referenceShellProvider)));
        return CompositedTranslation(
          translation: _translation,
          devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
          child: widget.child,
        );
      },
    );
  }
}

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/rendering.dart' show WindowContentRect;
import 'package:denial_flutter_sdk/shell_theme.dart';

import '../../state/reference_shell_controller.dart';
import '../../state/reference_shell_metrics.dart';
import '../../state/split_debug.dart';
import '../../widgets/overview/split_divider.dart';
import '../../widgets/overview/split_picker.dart';

/// Two apps sharing the phone screen, each taking half of it.
///
/// The compositor configures each window to its pane, so this stage only has
/// to place the windows where `splitPaneRects` says and dim the inactive side.
/// It never computes a window rectangle itself. While one side is still
/// unchosen, its pane shows the picker over the app that was dropped first.
class MobileSplitStage extends ConsumerWidget {
  const MobileSplitStage({super.key, required this.pair});

  final SplitPair pair;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final windows = ref.watch(
      referenceShellProvider.select(
        (state) => (
          first: state.windowByObjectId(pair.first),
          second: state.windowByObjectId(pair.second),
          // `DenialWindow` equality is about presentation, so a new buffer
          // would not rebuild the panes; the snapshot sequence does. Without
          // it the pane that just took focus keeps showing the old texture.
          sequence: state.windowSnapshotSequence,
        ),
      ),
    );
    final first = windows.first;
    final second = windows.second;
    if (first == null && second == null) return const SizedBox.shrink();
    final size = MediaQuery.sizeOf(context);
    // Rotating swaps the axis after this frame, so the pair follows the
    // screen without reconfiguring the clients twice mid-rotation.
    final vertical = size.height > size.width;
    if (pair.vertical != vertical) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        ref
            .read(referenceShellProvider.notifier)
            .syncSplitAxis(vertical: vertical);
      });
    }
    final panes = splitPaneRects(
      size.width,
      size.height,
      pair,
      topInset: ReferenceShellMetrics.appStatusInset(size),
    );
    final controller = ref.read(referenceShellProvider.notifier);
    Rect rectAt(int index) {
      final pane = panes[index];
      return Rect.fromLTWH(pane.left, pane.top, pane.width, pane.height);
    }

    Widget pane(DenialWindow window, int index) {
      final active = (pair.active == SplitSide.first) == (index == 0);
      final accent = ShellTheme.of(context).accent;
      splitDebug(
        'pane $index "${window.appId}" ${rectAt(index)} '
        'geometry=${window.geometryWidth.round()}x'
        '${window.geometryHeight.round()} '
        'min=${window.minWidth.round()}x${window.minHeight.round()}',
      );
      return Positioned.fromRect(
        rect: rectAt(index),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => controller.setSplitActive(
            index == 0 ? SplitSide.first : SplitSide.second,
          ),
          child: Opacity(
            opacity: active ? 1 : 0.96,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // A pane shows the whole client: an app that sized itself
                // a few pixels taller than the pane keeps its bottom row
                // when the window is fitted rather than covered.
                WindowContentRect(
                  window: window,
                  active: active,
                  fit: BoxFit.contain,
                ),
                // An outline around each pane makes the two apps read as two
                // windows; it is drawn over the content, so it costs the
                // clients no geometry.
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: accent.withValues(alpha: 0.45),
                          width: 1,
                        ),
                      ),
                    ),
                  ),
                ),
                // The active side owns the keyboard and Back; a stronger line
                // on the seam says so without taking any geometry.
                if (active)
                  Align(
                    alignment: index == 0
                        ? (pair.vertical
                              ? Alignment.bottomCenter
                              : Alignment.centerRight)
                        : (pair.vertical
                              ? Alignment.topCenter
                              : Alignment.centerLeft),
                    child: SizedBox(
                      width: pair.vertical ? null : 2,
                      height: pair.vertical ? 2 : null,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    if (!pair.isComplete) {
      // The picker takes the side the app was not dropped on.
      final pickerOnFirst = first == null;
      return Stack(
        fit: StackFit.expand,
        children: [
          if (first != null) pane(first, 0),
          if (second != null) pane(second, 1),
          Positioned.fromRect(
            rect: rectAt(pickerOnFirst ? 0 : 1),
            child: SplitPicker(
              pair: pair,
              onAllApps: () {
                // The launcher is a fullscreen shell surface today: leave
                // the split and show it rather than faking a third pane.
                controller.endSplit();
                controller.goHome();
              },
            ),
          ),
        ],
      );
    }

    if (first == null || second == null) return const SizedBox.shrink();
    final bounds = controller.splitBoundsFor(pair);
    final area = controller.splitAreaFor(pair);
    return Stack(
      fit: StackFit.expand,
      children: [
        pane(first, 0),
        pane(second, 1),
        if (bounds != null && area != null)
          Positioned.fromRect(
            rect: area,
            child: SplitDivider(
              vertical: pair.vertical,
              ratio: pair.ratio,
              bounds: bounds,
              onRatio: controller.updateSplitRatio,
              onReset: () => controller.updateSplitRatio(0.5),
            ),
          ),
      ],
    );
  }
}

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/rendering.dart' show WindowContentRect;

import '../../state/reference_shell_controller.dart';
import '../../state/reference_shell_metrics.dart';
import '../../widgets/overview/split_divider.dart';
import '../../widgets/overview/split_picker.dart';

/// Two apps sharing the phone screen as two floating cards.
///
/// The compositor configures each window to its card, so this stage only has to
/// place the windows where `splitPaneRects` says and dim the inactive side. It
/// never computes a window rectangle itself. While one side is still unchosen,
/// its card shows the picker over the app that was dropped first.
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
    final cards = splitPaneRects(
      size.width,
      size.height,
      pair,
      topInset: ReferenceShellMetrics.appStatusInset(size),
    );
    final controller = ref.read(referenceShellProvider.notifier);
    Rect rectAt(int index) {
      final card = cards[index];
      return Rect.fromLTWH(card.left, card.top, card.width, card.height);
    }

    Widget card(DenialWindow window, int index) {
      final active = (pair.active == SplitSide.first) == (index == 0);
      return Positioned.fromRect(
        rect: rectAt(index),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => controller.setSplitActive(
            index == 0 ? SplitSide.first : SplitSide.second,
          ),
          child: Opacity(
            opacity: active ? 1 : 0.94,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(splitCardRadius),
                  child: WindowContentRect(
                    window: window,
                    active: active,
                    // A client that refused the pane size is shown whole
                    // instead of cropped: its own title bar and buttons stay
                    // reachable.
                    fit: BoxFit.contain,
                  ),
                ),
                if (active)
                  const IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.all(
                          Radius.circular(splitCardRadius),
                        ),
                        border: Border.fromBorderSide(
                          BorderSide(color: Color(0x8C6D5BD0), width: 1.5),
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
          if (first != null) card(first, 0),
          if (second != null) card(second, 1),
          Positioned.fromRect(
            rect: rectAt(pickerOnFirst ? 0 : 1),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(splitCardRadius),
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
          ),
        ],
      );
    }

    if (first == null || second == null) return const SizedBox.shrink();
    return Stack(
      fit: StackFit.expand,
      children: [
        card(first, 0),
        card(second, 1),
        Positioned.fill(
          child: SplitDivider(
            pair: pair,
            panes: [rectAt(0), rectAt(1)],
            onRatio: controller.updateSplitRatio,
            onReset: () => controller.updateSplitRatio(0.5),
            onClose: controller.endSplit,
          ),
        ),
      ],
    );
  }
}

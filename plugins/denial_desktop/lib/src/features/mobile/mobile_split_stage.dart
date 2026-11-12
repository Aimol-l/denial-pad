import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/rendering.dart' show WindowContentRect;

import '../../state/reference_shell_controller.dart';
import '../../state/reference_shell_metrics.dart';
import '../../widgets/overview/split_picker.dart';

/// Two apps sharing the phone screen.
///
/// The compositor configures each window to its pane, so this stage only has to
/// place the windows by the pair's ratio and dim the inactive side; it never
/// computes a window rectangle itself. While the second app is still unchosen,
/// the free side shows the picker over the first app.
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
    if (first == null) return const SizedBox.shrink();
    final size = MediaQuery.sizeOf(context);
    final fractions = splitFractions(pair.ratio);

    Rect paneRect(bool isFirst) {
      final share = isFirst ? fractions.first : fractions.second;
      if (pair.vertical) {
        return Rect.fromLTWH(
          0,
          size.height * (isFirst ? 0 : fractions.first),
          size.width,
          size.height * share,
        );
      }
      return Rect.fromLTWH(
        size.width * (isFirst ? 0 : fractions.first),
        0,
        size.width * share,
        size.height,
      );
    }

    Widget pane(DenialWindow window, bool isFirst) {
      final active = (pair.active == SplitSide.first) == isFirst;
      return Positioned.fromRect(
        rect: paneRect(isFirst),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => ref
              .read(referenceShellProvider.notifier)
              .setSplitActive(isFirst ? SplitSide.first : SplitSide.second),
          child: Opacity(
            opacity: active ? 1 : 0.96,
            child: WindowContentRect(window: window, active: active),
          ),
        ),
      );
    }

    if (!pair.isComplete) {
      return Stack(
        fit: StackFit.expand,
        children: [
          pane(first, true),
          Positioned.fromRect(
            rect: paneRect(false),
            child: Padding(
              // The windows are configured below the status bar by the
              // compositor; the shell-drawn picker has to do the same itself.
              padding: EdgeInsets.only(
                top: pair.vertical
                    ? 0
                    : ReferenceShellMetrics.appStatusInset(size),
              ),
              child: SplitPicker(
                pair: pair,
                onAllApps: () {
                  final controller = ref.read(
                    referenceShellProvider.notifier,
                  );
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

    final second = windows.second;
    if (second == null) return const SizedBox.shrink();
    return Stack(
      fit: StackFit.expand,
      children: [pane(first, true), pane(second, false)],
    );
  }
}

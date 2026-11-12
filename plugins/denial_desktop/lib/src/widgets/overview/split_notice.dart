import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/reference_shell_controller.dart';
import '../../state/reference_shell_metrics.dart';

/// A short, self-dismissing line near the top of the screen: the split's
/// reasons for refusing an app live here.
class SplitNotice extends ConsumerWidget {
  const SplitNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final message = ref.watch(
      referenceShellProvider.select((state) => state.splitNotice),
    );
    if (message == null) return const SizedBox.shrink();
    return Positioned(
      left: 0,
      right: 0,
      // Below the status bar the compositor draws over the scene.
      top: ReferenceShellMetrics.statusBarHeight + 14,
      child: IgnorePointer(
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xE614161C),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Text(
                message,
                style: const TextStyle(
                  color: Color(0xFFF2F3F7),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

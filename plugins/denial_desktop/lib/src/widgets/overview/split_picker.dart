import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:denial_flutter_sdk/models.dart';

import '../../state/reference_shell_controller.dart';

/// Lists the other open apps on the still-empty side of a split, so a tap
/// completes the pair. The fixed side keeps rendering underneath.
class SplitPicker extends ConsumerWidget {
  const SplitPicker({super.key, required this.pair});

  final SplitPair pair;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final candidates = ref.watch(
      referenceShellProvider.select(
        (state) => state.openAppWindows
            .where(
              (window) =>
                  window.isUserApp && window.objectId != pair.first,
            )
            .toList(growable: false),
      ),
    );
    final controller = ref.read(referenceShellProvider.notifier);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: DecoratedBox(
          decoration: const BoxDecoration(color: Color(0xC612121A)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                child: Text(
                  pair.vertical ? '选择下方应用' : '选择右侧应用',
                  style: const TextStyle(
                    color: Color(0xFFF3F4F7),
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
              Expanded(
                child: candidates.isEmpty
                    ? const Center(
                        child: Text(
                          '没有其他打开的应用',
                          style: TextStyle(
                            color: Color(0xB3F3F4F7),
                            fontSize: 15,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: candidates.length,
                        itemBuilder: (context, index) {
                          final window = candidates[index];
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => controller.pickSplitSecond(window),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0x2EFFFFFF),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      window.title.isEmpty
                                          ? window.appId
                                          : window.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFFF3F4F7),
                                        fontSize: 16,
                                        decoration: TextDecoration.none,
                                      ),
                                    ),
                                  ),
                                  const Text(
                                    '打开 →',
                                    style: TextStyle(
                                      color: Color(0xFFB9AEF5),
                                      fontSize: 14,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

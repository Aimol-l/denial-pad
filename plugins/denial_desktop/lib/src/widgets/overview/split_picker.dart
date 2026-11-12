import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/rendering.dart' show WindowContentRect;

import '../../state/reference_shell_controller.dart';

/// Picks the second pane's app from a grid of live thumbnails, on the side of
/// the screen that is still empty. The fixed side keeps rendering underneath.
class SplitPicker extends ConsumerWidget {
  const SplitPicker({super.key, required this.pair, required this.onAllApps});

  final SplitPair pair;

  /// Opens the launcher so an app that is not running can take this side.
  final VoidCallback onAllApps;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final candidates = ref.watch(
      referenceShellProvider.select(
        (state) => state.openAppWindows
            .where(
              (window) => window.isUserApp && window.objectId != pair.first,
            )
            .toList(growable: false),
      ),
    );
    final fixed = ref.watch(
      referenceShellProvider.select(
        (state) => state.windowByObjectId(pair.first),
      ),
    );
    final controller = ref.read(referenceShellProvider.notifier);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: DecoratedBox(
          decoration: const BoxDecoration(color: Color(0xC412121A)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                child: Text(
                  switch ((pair.vertical, pair.first > 0)) {
                    (true, true) => '选择下方应用',
                    (true, false) => '选择上方应用',
                    (false, true) => '选择右侧应用',
                    (false, false) => '选择左侧应用',
                  },
                  style: const TextStyle(
                    color: Color(0xFFF3F4F7),
                    fontSize: 16,
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
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final pane = constraints.biggest;
                          return GridView.builder(
                            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  mainAxisSpacing: 14,
                                  crossAxisSpacing: 14,
                                  childAspectRatio: 4 / 3.5,
                                ),
                            itemCount: candidates.length + 1,
                            itemBuilder: (context, index) {
                              if (index == candidates.length) {
                                return _Tile(
                                  label: '全部应用',
                                  onTap: onAllApps,
                                  child: const _AllAppsMark(),
                                );
                              }
                              final window = candidates[index];
                              final fits = fixed == null
                                  ? true
                                  : (splitRatioBounds(
                                          extent: pair.vertical
                                              ? pane.height
                                              : pane.width,
                                          firstMin: pair.vertical
                                              ? fixed.minHeight
                                              : fixed.minWidth,
                                          secondMin: pair.vertical
                                              ? window.minHeight
                                              : window.minWidth,
                                        ) !=
                                        null);
                              return _Tile(
                                label: window.title.isEmpty
                                    ? window.appId
                                    : window.title,
                                detail: fits
                                    ? null
                                    : '最小需要 '
                                          '${window.minWidth.round()}×'
                                          '${window.minHeight.round()}',
                                onTap: fits
                                    ? () => controller.pickSplitSecond(window)
                                    : null,
                                child: Opacity(
                                  opacity: fits ? 1 : 0.4,
                                  child: WindowContentRect(
                                    window: window,
                                    applyBackdrop: false,
                                  ),
                                ),
                              );
                            },
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

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.child,
    required this.onTap,
    this.detail,
  });

  final String label;
  final String? detail;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final detail = this.detail;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: DecoratedBox(
                decoration: const BoxDecoration(color: Color(0xFF1B1D24)),
                child: child,
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFE7E9F0),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
            ),
          ),
          if (detail != null)
            Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xB3F3F4F7),
                fontSize: 11,
                decoration: TextDecoration.none,
              ),
            ),
        ],
      ),
    );
  }
}

class _AllAppsMark extends StatelessWidget {
  const _AllAppsMark();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x40FFFFFF)),
      ),
      child: Center(
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < 9; i += 1)
              const SizedBox(
                width: 9,
                height: 9,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0x8CFFFFFF),
                    borderRadius: BorderRadius.all(Radius.circular(3)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

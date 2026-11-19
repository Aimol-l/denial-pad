import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart'
    show TextField, InputDecoration, InputBorder;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:denial_flutter_sdk/applications.dart';
import 'package:denial_flutter_sdk/input.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/rendering.dart' show WindowContentRect;

import '../../launcher/home_launch.dart';
import '../../launcher/widgets/launcher_icon.dart';
import '../../state/reference_shell_controller.dart';
import '../../state/reference_shell_metrics.dart';

/// Picks the other pane's app on the side of the screen that is still empty.
///
/// The grid holds every application, not only the ones already running: an
/// app that is not open starts and lands straight in the empty pane. Running
/// apps show their live thumbnail; the rest show their icon.
class SplitPicker extends ConsumerStatefulWidget {
  const SplitPicker({super.key, required this.pair});

  final SplitPair pair;

  @override
  ConsumerState<SplitPicker> createState() => _SplitPickerState();
}

class _SplitPickerState extends ConsumerState<SplitPicker> {
  final _search = TextEditingController();
  String _query = '';
  int? _surfaceId;

  @override
  void initState() {
    super.initState();
    // Typing in the picker's search belongs to the shell: without a capture
    // surface the keys went to the client that still held focus.
    final registry = ref.read(shellInteractionRegistryProvider.notifier);
    final id = registry.reserveSurfaceId();
    _surfaceId = id;
    registry.upsert(
      ShellInteractionSurface(
        id: id,
        debugLabel: 'Split picker',
        pointerPolicy: ShellPointerPolicy.fullScene,
        keyboardPolicy: ShellKeyboardPolicy.capture,
        compositorPolicy: ShellCompositorPolicy.normal,
      ),
    );
  }

  @override
  void deactivate() {
    // Released here rather than in dispose: by dispose time the ref counts as
    // unmounted, the removal was skipped, and the leftover capture kept the
    // shell swallowing the keyboard so no app could raise it again.
    final id = _surfaceId;
    _surfaceId = null;
    if (id != null) {
      ref.read(shellInteractionRegistryProvider.notifier).remove(id);
    }
    super.deactivate();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  DenialWindow? _windowFor(
    HomeGridItem item,
    List<DenialWindow> windows,
    AppLauncher launcher,
  ) {
    final app = item.app;
    if (app != null) return launcher.findOpenWindow(app, windows);
    final local = item.localApp;
    if (local == null) return null;
    for (final window in windows) {
      if (window.isLocalFlutter && window.appId == local.id) return window;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final pair = widget.pair;
    final controller = ref.read(referenceShellProvider.notifier);
    final launcher = ref.read(appLauncherProvider);
    final windows = ref.watch(
      referenceShellProvider.select((state) => state.openAppWindows),
    );
    final catalog =
        ref
            .watch(homeGridControllerProvider)
            .asData
            ?.value
            .catalog
            .where((item) => item.isApp)
            .toList(growable: false) ??
        const <HomeGridItem>[];
    final lower = _query.trim().toLowerCase();
    // The app already holding the other pane is not a candidate.
    final taken = <int>{pair.first, pair.second}..remove(0);
    final entries = <({HomeGridItem item, DenialWindow? window})>[
      for (final item in catalog)
        if ((lower.isEmpty ||
                (item.app?.name ?? item.localApp?.titleFor(context) ?? '')
                    .toLowerCase()
                    .contains(lower)) &&
            !taken.contains(_windowFor(item, windows, launcher)?.objectId))
          (item: item, window: _windowFor(item, windows, launcher)),
    ];
    // Running apps first: they are what a split usually wants.
    entries.sort((a, b) {
      final runningA = a.window != null ? 0 : 1;
      final runningB = b.window != null ? 0 : 1;
      if (runningA != runningB) return runningA - runningB;
      final nameA =
          a.item.app?.name ?? a.item.localApp?.titleFor(context) ?? '';
      final nameB =
          b.item.app?.name ?? b.item.localApp?.titleFor(context) ?? '';
      return nameA.toLowerCase().compareTo(nameB.toLowerCase());
    });
    final view = MediaQuery.sizeOf(context);
    final extent = pair.vertical
        ? view.height - ReferenceShellMetrics.appStatusInset(view)
        : view.width;

    // The picker arrives rather than switching: a hard cut on a big screen
    // reads as a dropped frame.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.scale(scale: 0.97 + 0.03 * value, child: child),
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: DecoratedBox(
            decoration: const BoxDecoration(color: Color(0xC412121A)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                  child: _SearchField(
                    controller: _search,
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
                Expanded(
                  child: entries.isEmpty
                      ? const Center(
                          child: Text(
                            '没有匹配的应用',
                            style: TextStyle(
                              color: Color(0xB3F3F4F7),
                              fontSize: 15,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: 14,
                                crossAxisSpacing: 14,
                                childAspectRatio: 4 / 3.5,
                              ),
                          itemCount: entries.length,
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            final window = entry.window;
                            final fits = window == null
                                ? true
                                : (splitRatioBounds(
                                        extent: extent,
                                        firstMin: pair.vertical
                                            ? _minHeight(entry.item)
                                            : _minWidth(entry.item),
                                        secondMin: pair.vertical
                                            ? window.minHeight
                                            : window.minWidth,
                                      ) !=
                                      null);
                            return _Tile(
                              label: _nameOf(context, entry.item),
                              detail: window == null ? '未运行' : null,
                              onTap: !fits
                                  ? null
                                  : () {
                                      if (window != null) {
                                        controller.pickSplitSecond(window);
                                      } else {
                                        controller.expectSplitWith(entry.item);
                                        launchHomeApp(
                                          context,
                                          ref,
                                          entry.item,
                                          Rect.zero,
                                        );
                                      }
                                    },
                              child: window != null
                                  ? Opacity(
                                      opacity: fits ? 1 : 0.4,
                                      child: WindowContentRect(
                                        window: window,
                                        applyBackdrop: false,
                                      ),
                                    )
                                  : Center(
                                      child: Opacity(
                                        opacity: fits ? 1 : 0.4,
                                        child: SizedBox.square(
                                          dimension: 46,
                                          child: LauncherIcon.of(entry.item),
                                        ),
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
      ),
    );
  }

  // In-bundle apps do not report a minimum size; a pane always fits them.
  static double _minWidth(HomeGridItem item) => 0;

  static double _minHeight(HomeGridItem item) => 0;

  String _nameOf(BuildContext context, HomeGridItem item) =>
      item.localApp?.titleFor(context) ?? item.app?.name ?? '';
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0x1AFFFFFF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x24FFFFFF)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Center(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              cursorColor: const Color(0xFF8B5CF6),
              style: const TextStyle(
                color: Color(0xFFF3F4F7),
                fontSize: 14,
                decoration: TextDecoration.none,
              ),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: '搜索应用',
                hintStyle: TextStyle(color: Color(0x80F3F4F7), fontSize: 14),
              ),
            ),
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

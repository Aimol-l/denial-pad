import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as p;

import 'package:denial_flutter_sdk/applications.dart';
import 'package:denial_flutter_sdk/effects.dart';
import 'package:denial_flutter_sdk/input.dart';
import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/popups.dart';
import 'package:denial_flutter_sdk/shell_theme.dart';
import 'package:denial_flutter_sdk/system_services.dart';

import '../../launcher/home_drag_controller.dart';
import '../../launcher/home_interactions.dart';
import '../../launcher/home_launch.dart';
import '../../launcher/widgets/launcher_icon.dart';
import '../../state/reference_shell_controller.dart';

/// The Arch mark behind the dock's all-apps button.
const _archMarkAsset =
    'packages/denial_flutter_sdk/assets/branding/arch-linux.svg';

/// The home dock's pinned applications. An empty or missing file falls back
/// to the defaults; a saved empty list means the user removed everything.
final dockPinnedProvider =
    AsyncNotifierProvider<DockPinnedController, List<String>>(
      DockPinnedController.new,
    );

class DockPinnedController extends AsyncNotifier<List<String>> {
  static const defaults = <String>[
    'app:firefox.desktop',
    'app:org.gnome.Nautilus.desktop',
    'app:qq.desktop',
    'app:droidloom-650f2ba5242c203a3a7c706d46c4602f.desktop',
    'app:dev.denial.Settings.desktop',
  ];

  File get _file {
    final paths = ref.read(runtimePathsProvider);
    return File('${paths.configHome}/denia-home/dock.json');
  }

  @override
  Future<List<String>> build() async {
    final file = _file;
    try {
      if (!await file.exists()) return defaults;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is List) {
        return [
          for (final id in decoded)
            if (id is String && id.isNotEmpty) id,
        ];
      }
    } on Object {
      // A damaged file falls back to the defaults; the next save repairs it.
    }
    return defaults;
  }

  Future<void> add(String id) async {
    final current = state.value ?? defaults;
    if (current.contains(id)) return;
    final next = [...current, id];
    state = AsyncData(next);
    await _save(next);
  }

  Future<void> remove(String id) async {
    final current = state.value ?? defaults;
    if (!current.contains(id)) return;
    final next = [...current]..remove(id);
    state = AsyncData(next);
    await _save(next);
  }

  /// Moves a pinned app onto the desktop: the dock entry goes away and a
  /// shortcut for the same entry appears in the desktop folder, unless the
  /// folder already points at it.
  Future<void> moveToDesktop(String id, String? desktopEntry) async {
    // Place the shortcut first: if the folder refuses it, the app must stay
    // reachable in the dock instead of vanishing from both.
    if (desktopEntry != null && desktopEntry.isNotEmpty) {
      final desktop = Directory(
        ref.read(runtimePathsProvider).desktopDirectory,
      );
      try {
        if (!await _desktopHasEntry(desktop, desktopEntry)) {
          await desktop.create(recursive: true);
          await Link(p.join(desktop.path, p.basename(desktopEntry)))
              .create(desktopEntry);
        }
      } on FileSystemException {
        return;
      }
    }
    await remove(id);
  }

  /// Adds an app at [index] instead of the end, for a drop between icons.
  Future<void> insertAt(String id, int index) async {
    final current = state.value ?? defaults;
    if (current.contains(id)) return;
    final next = [...current];
    next.insert(index.clamp(0, next.length), id);
    state = AsyncData(next);
    await _save(next);
  }

  /// Pins an app dragged out of the desktop folder. Its shortcut leaves the
  /// folder, so the icon moves into the dock instead of being copied.
  Future<void> pinFromDesktop(HomeGridItem item, {int? index}) async {
    await (index == null ? add(item.id) : insertAt(item.id, index));
    final entry = item.app?.desktopPath;
    if (entry == null || entry.isEmpty) return;
    final desktop = ref.read(runtimePathsProvider).desktopDirectory;
    if (p.dirname(entry) != desktop) return;
    try {
      await File(entry).delete();
    } on FileSystemException {
      // The pin already landed; removing the shortcut is best effort.
    }
  }

  Future<bool> _desktopHasEntry(Directory desktop, String entry) async {
    if (!await desktop.exists()) return false;
    await for (final entity in desktop.list(followLinks: false)) {
      if (!entity.path.toLowerCase().endsWith('.desktop')) continue;
      if (entity is Link) {
        try {
          if (await entity.resolveSymbolicLinks() == entry) return true;
        } on FileSystemException {
          continue;
        }
      } else if (p.equals(entity.path, entry)) {
        return true;
      }
    }
    return false;
  }

  /// Saves a new order for the pinned apps. The set must be the same, so a
  /// stale drag can never drop or invent an app.
  Future<void> reorder(List<String> ids) async {
    final current = state.value ?? defaults;
    if (ids.length != current.length) return;
    final wanted = ids.toSet();
    if (wanted.length != ids.length || !wanted.containsAll(current)) return;
    if (listEquals(current, ids)) return;
    final next = List<String>.unmodifiable(ids);
    state = AsyncData(next);
    await _save(next);
  }

  Future<void> _save(List<String> ids) async {
    try {
      final file = _file;
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(ids));
    } on Object {
      // Persistence is best effort; the live list remains applied.
    }
  }
}

/// The home screen's bottom dock: pinned apps, running apps, and an all-apps
/// drawer. It lives inside the launcher so app windows cover it and dragging
/// a home icon onto it pins that app.
class MobileDockLayer extends ConsumerStatefulWidget {
  const MobileDockLayer({super.key});

  @override
  ConsumerState<MobileDockLayer> createState() => _MobileDockLayerState();
}

class _MobileDockLayerState extends ConsumerState<MobileDockLayer> {
  final _dockKey = GlobalKey();
  final _laneKey = GlobalKey();
  HomeDragController? _drag;
  HomeDrag? _lastDrag;
  bool _drawerOpen = false;

  /// The pinned order a long-press drag is showing. Null while no dock icon
  /// is being moved.
  List<String>? _reorder;
  HomeGridItem? _dragItem;
  int _dragIndex = 0;

  /// Where the finger was the last time the dragged icon slotted in, so the
  /// icon keeps following it after the order moves under the finger.
  double _dragAnchorX = 0;

  /// The lifted icon's position, so it can be painted above the dock and
  /// outside the glass clip. Only the floating tile listens to it.
  final ValueNotifier<Offset> _dragPosition = ValueNotifier<Offset>(
    Offset.zero,
  );
  bool _reorderMoved = false;
  bool _pointerOverDock = false;
  bool _removeArmed = false;

  /// Where an icon dragged in from the desktop would land, and whether the
  /// finger is over the dock at all. Kept apart from a lifted icon's own
  /// reorder so the two previews never fight.
  bool _draggingOverDock = false;
  int? _dropPreviewIndex;
  Timer? _removeArmTimer;

  /// How long the finger must stay outside the dock before a drop removes
  /// the app instead of cancelling.
  static const Duration _removeArmDelay = Duration(milliseconds: 300);

  /// One dock cell, the width of [_DockButton].
  static const double _dockCell = 66;

  /// How long an icon takes to slide into a new slot.
  static const Duration _dockSlide = Duration(milliseconds: 180);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final drag = HomeInteractionScope.of(context).drag;
    if (identical(drag, _drag)) return;
    _detachDrag();
    _drag = drag;
    _drag!.drag.addListener(_dragChanged);
    _drag!.pointer.addListener(_pointerChanged);
  }

  @override
  void dispose() {
    _detachDrag();
    _removeArmTimer?.cancel();
    _dragPosition.dispose();
    super.dispose();
  }

  void _detachDrag() {
    _drag?.drag.removeListener(_dragChanged);
    _drag?.pointer.removeListener(_pointerChanged);
    _drag = null;
  }

  void _pointerChanged() {
    if (!mounted) return;
    final drag = _drag?.drag.value;
    final over =
        drag != null &&
        drag.landing == null &&
        drag.item.isApp &&
        _overDock(_drag!.pointer.value);
    final index = over ? _dockInsertIndex(_drag!.pointer.value) : null;
    if (over == _draggingOverDock && index == _dropPreviewIndex) return;
    setState(() {
      _draggingOverDock = over;
      _dropPreviewIndex = index;
    });
  }

  void _dragChanged() {
    final current = _drag?.drag.value;
    final wasLanding = _lastDrag?.landing != null;
    if (current != null &&
        current.landing != null &&
        !wasLanding &&
        current.item.isApp &&
        _dropPreviewIndex != null) {
      final index = _dropPreviewIndex!;
      // Close the gap before the entry is written: otherwise the preview
      // slot and the new icon sit in the dock together for a moment.
      setState(() {
        _draggingOverDock = false;
        _dropPreviewIndex = null;
      });
      unawaited(_takeFromDesktop(current.item, index));
      ref.read(hapticsServiceProvider).pulse();
    }
    _lastDrag = current;
    if (current != null) {
      // The preview follows the pointer notifier; this callback runs for
      // every drag update and must not rebuild the dock each frame.
      return;
    }
    // The drag is over. The pointer notifier may never report again, so the
    // slot preview is cleared here rather than waiting for it.
    if (!_draggingOverDock && _dropPreviewIndex == null) return;
    if (!mounted) return;
    setState(() {
      _draggingOverDock = false;
      _dropPreviewIndex = null;
    });
  }

  bool _overDock(Offset pointer) {
    final box = _dockKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return false;
    return (box.localToGlobal(Offset.zero) & box.size)
        .inflate(18)
        .contains(pointer);
  }

  void _startDockDrag(HomeGridItem item, Offset global) {
    final saved =
        ref.read(dockPinnedProvider).value ?? DockPinnedController.defaults;
    final index = saved.indexOf(item.id);
    if (index < 0) return;
    setState(() {
      _reorder = [...saved];
      _dragItem = item;
      _dragIndex = index;
      _dragAnchorX = global.dx;
      _reorderMoved = false;
      _pointerOverDock = true;
      _removeArmed = false;
    });
    _dragPosition.value = global;
    ref.read(hapticsServiceProvider).pulse();
  }

  void _moveDockDrag(Offset global) {
    final order = _reorder;
    if (order == null) return;
    _dragPosition.value = global;
    final overDock = _dockContains(global);
    if (overDock != _pointerOverDock) {
      setState(() => _pointerOverDock = overDock);
      // Leaving the dock arms removal after a short hold; coming back
      // disarms it, so a slip through the edge removes nothing.
      if (overDock) {
        _cancelRemoveArm();
      } else {
        _armRemoveLater();
      }
    }
    if (!overDock) return;
    final steps = ((global.dx - _dragAnchorX) / _dockCell).round();
    if (steps != 0) {
      final target = (_dragIndex + steps).clamp(0, order.length - 1);
      if (target != _dragIndex) {
        setState(() {
          final id = order.removeAt(_dragIndex);
          order.insert(target, id);
          _dragIndex = target;
          _dragAnchorX += steps * _dockCell;
          _reorderMoved = true;
        });
        ref.read(hapticsServiceProvider).pulse();
      }
    }
  }

  void _armRemoveLater() {
    _removeArmTimer?.cancel();
    _removeArmTimer = Timer(_removeArmDelay, () {
      if (!mounted || _reorder == null || _pointerOverDock) return;
      setState(() => _removeArmed = true);
      ref.read(hapticsServiceProvider).pulse();
    });
  }

  void _cancelRemoveArm() {
    _removeArmTimer?.cancel();
    _removeArmTimer = null;
    if (_removeArmed) setState(() => _removeArmed = false);
  }

  /// Where a drop at [global] slots into the pinned row.
  int _dockInsertIndex(Offset global) {
    final saved =
        ref.read(dockPinnedProvider).value ?? DockPinnedController.defaults;
    final box = _laneKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return saved.length;
    final localX = box.globalToLocal(global).dx;
    return (localX / _dockCell).round().clamp(0, saved.length);
  }

  /// A move touches two folders at once; the watchers debounce, so ask the
  /// launcher to rescan now instead of letting an icon linger for seconds.
  Future<void> _refreshDesktop() async {
    await ref
        .read(homeGridControllerProvider.notifier)
        .refreshDesktopApps(reason: 'shortcuts');
  }

  Future<void> _returnToDesktop(HomeGridItem item) async {
    await ref
        .read(dockPinnedProvider.notifier)
        .moveToDesktop(item.id, item.app?.desktopPath);
    await _refreshDesktop();
  }

  Future<void> _takeFromDesktop(HomeGridItem item, int index) async {
    await ref
        .read(dockPinnedProvider.notifier)
        .pinFromDesktop(item, index: index);
    await _refreshDesktop();
  }

  bool _dockContains(Offset global) {
    final box = _dockKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return false;
    return (box.localToGlobal(Offset.zero) & box.size).contains(global);
  }

  void _endDockDrag() {
    final order = _reorder;
    if (order == null) return;
    final item = _dragItem;
    final moved = _reorderMoved;
    final armed = _removeArmed;
    final overDock = _pointerOverDock;
    _removeArmTimer?.cancel();
    _removeArmTimer = null;
    setState(() {
      _reorder = null;
      _dragItem = null;
      _dragIndex = 0;
      _dragAnchorX = 0;
      _reorderMoved = false;
      _pointerOverDock = false;
      _removeArmed = false;
    });
    if (item == null) return;
    if (armed) {
      unawaited(_returnToDesktop(item));
      return;
    }
    // Released outside without the hold: the drag is cancelled, as if the
    // icon had never left its slot.
    if (!overDock) return;
    if (moved) {
      unawaited(ref.read(dockPinnedProvider.notifier).reorder(order));
      return;
    }
    // A long press that never travelled still opens the menu. Wait for the
    // frame that handles this pointer up: the new menu would otherwise be
    // dismissed by the very release that opened it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showDockMenu(item);
    });
  }

  void _showDockMenu(HomeGridItem item) {
    ref
        .read(shellPopupControllerProvider.notifier)
        .show(
          keyName: 'dock-item-${item.id}',
          debugLabel: 'Dock item',
          pointerPolicy: ShellPointerPolicy.fullScene,
          keyboardPolicy: ShellKeyboardPolicy.capture,
          dismissPolicy: ShellDismissPolicy.outsideTapAndEscape,
          builder: (context, handle) => _DockItemMenu(
            title: _nameOf(context, item),
            onRemove: () {
              handle.close();
              unawaited(ref.read(dockPinnedProvider.notifier).remove(item.id));
            },
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(referenceShellProvider);
    final visible =
        !state.appOnScreen &&
        !state.launchTransitionActive &&
        !state.overviewVisible &&
        !state.quickSettingsEngaged &&
        !state.lockLayerVisible &&
        !state.locked;
    if (!visible && _drawerOpen) {
      // Mutating during build is not allowed; defer the close.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _drawerOpen) setState(() => _drawerOpen = false);
      });
    }

    final catalog =
        ref
            .watch(homeGridControllerProvider)
            .asData
            ?.value
            .catalog
            .where((item) => item.isApp)
            .toList(growable: false) ??
        const <HomeGridItem>[];
    final savedIds =
        ref.watch(dockPinnedProvider).value ?? DockPinnedController.defaults;
    // A long-press drag previews the order before it is saved.
    final pinnedIds = _reorder ?? savedIds;
    final launcher = ref.read(appLauncherProvider);
    final byId = {for (final item in catalog) item.id: item};
    final windows = state.openAppWindows;
    final foreground = state.foregroundWindow?.objectId;

    final pinned = <HomeGridItem>[
      for (final id in pinnedIds)
        if (byId[id] != null) byId[id]!,
    ];

    // Map window identities back to launcher items so an app opened from a
    // shell command still gets its dock icon.
    final windowIndex = <String, HomeGridItem>{};
    for (final item in catalog) {
      final app = item.app;
      if (app == null) continue;
      for (final id in launcher.expectedWindowAppIds(app)) {
        windowIndex[id.toLowerCase()] = item;
      }
    }

    final runningExtras = <HomeGridItem>[];
    final seen = <String>{for (final item in pinned) item.id};
    for (final window in windows) {
      if (!window.isUserApp) continue;
      HomeGridItem? item = windowIndex[window.appId.toLowerCase()];
      if (item == null && window.isLocalFlutter) {
        for (final candidate in catalog) {
          if (candidate.localApp?.id == window.appId) {
            item = candidate;
            break;
          }
        }
      }
      if (item != null && seen.add(item.id)) runningExtras.add(item);
    }

    final theme = ShellTheme.of(context);
    final radius = theme.scaledRadius(24);
    final accent = theme.accentPalette.primary;
    // A lifted icon is painted above the dock, so its slot is left empty and
    // the row itself never takes the red outline meant for a removal drop.
    // A drag in from the desktop previews its slot the same way.
    final preview = _dragItem == null ? _dropPreviewIndex : null;
    final insertSlot = _dragItem != null ? _dragIndex : preview;
    final lifting = insertSlot != null;
    final outline = _removeArmed
        ? const Color(0xFFB0443F)
        : (lifting || _draggingOverDock
              ? accent
              : context.shellColors.hairlineSoft);

    Widget entry(HomeGridItem item, {required bool pinned}) {
      final running = _windowFor(item, windows, launcher);
      final lifted = pinned && _dragItem?.id == item.id;
      return Opacity(
        // The floating tile already shows this app; the slot stays for the
        // row's layout and for the insertion preview.
        opacity: lifted ? 0 : 1,
        child: _DockButton(
          // Keeps each icon's press state with the app when the row reorders.
          key: ValueKey<String>(item.id),
          item: item,
          running: running != null,
          active: running != null && running.objectId == foreground,
          pinned: pinned,
          onDragStart: pinned ? (global) => _startDockDrag(item, global) : null,
          onDragMove: pinned ? _moveDockDrag : null,
          onDragEnd: pinned ? _endDockDrag : null,
          onTap: (rect) => launchHomeApp(context, ref, item, rect),
        ),
      );
    }

    final dock = ShellBackdropBlur(
      key: _dockKey,
      blur: theme.effectivePanelOpacity < 1,
      grouped: true,
      strength: 1,
      separateChild: true,
      borderRadius: BorderRadius.circular(radius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.cardColor(context.shellColors.panelBackground),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: outline, width: lifting ? 2 : 1),
          boxShadow: [
            const BoxShadow(
              color: Color(0x66000000),
              blurRadius: 34,
              offset: Offset(0, 14),
            ),
            if (lifting || _draggingOverDock)
              BoxShadow(
                color: outline.withValues(alpha: 0.30),
                blurRadius: 26,
                spreadRadius: 2,
              ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AllAppsButton(
                onPressed: () => setState(() => _drawerOpen = true),
              ),
              const _DockDivider(),
              // Fixed slots: each icon animates to its index, so the row
              // slides and never jumps, and a lifted icon leaves a real gap
              // that can show where it will land.
              SizedBox(
                key: _laneKey,
                width: (pinned.length + (preview != null ? 1 : 0)) * _dockCell,
                height: 74,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (insertSlot != null)
                      AnimatedPositioned(
                        left: insertSlot * _dockCell,
                        top: 7,
                        width: _dockCell,
                        height: 60,
                        duration: _dockSlide,
                        curve: Curves.easeOutCubic,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: outline.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: outline.withValues(alpha: 0.55),
                                width: 1.6,
                              ),
                            ),
                          ),
                        ),
                      ),
                    for (final (index, item) in pinned.indexed)
                      AnimatedPositioned(
                        key: ValueKey<String>('dock-slot-${item.id}'),
                        // An incoming icon opens a gap at its slot.
                        left:
                            (preview != null && index >= preview
                                ? index + 1
                                : index) *
                            _dockCell,
                        top: 0,
                        width: _dockCell,
                        height: 74,
                        duration: _dockSlide,
                        curve: Curves.easeOutCubic,
                        child: entry(item, pinned: true),
                      ),
                  ],
                ),
              ),
              if (runningExtras.isNotEmpty) ...[
                const _DockDivider(),
                for (final item in runningExtras)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: entry(item, pinned: false),
                  ),
              ],
            ],
          ),
        ),
      ),
    );

    // The long-press recognizer can lose its end event to the tooltip's own
    // long press. A pointer listener sees every up and cancel, so a drag
    // always lands instead of leaving the icon floating.
    return Listener(
      onPointerUp: (_) => _endDockDrag(),
      onPointerCancel: (_) => _endDockDrag(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: AnimatedSlide(
                offset: visible ? Offset.zero : const Offset(0, 1.3),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: visible ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: IgnorePointer(ignoring: !visible, child: dock),
                ),
              ),
            ),
          ),
          // The lifted icon floats above the dock: inside it, the glass clip
          // would cut it off the moment the finger leaves the bar.
          if (_dragItem != null)
            Positioned.fill(
              child: IgnorePointer(
                child: ValueListenableBuilder<Offset>(
                  valueListenable: _dragPosition,
                  builder: (context, position, child) => Stack(
                    children: [
                      Positioned(
                        left: position.dx - 33,
                        top: position.dy - 33,
                        child: child!,
                      ),
                    ],
                  ),
                  child: SizedBox(
                    width: 66,
                    height: 66,
                    child: Center(
                      child: Transform.scale(
                        scale: 1.12,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    (_removeArmed
                                            ? const Color(0xFFB0443F)
                                            : accent)
                                        .withValues(alpha: 0.42),
                                blurRadius: 24,
                                spreadRadius: 3,
                              ),
                            ],
                          ),
                          child: SizedBox.square(
                            dimension: 54,
                            child: LauncherIcon.of(_dragItem!),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (_removeArmed && visible)
            Positioned(
              left: 0,
              right: 0,
              bottom: 138,
              child: IgnorePointer(
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFFB0443F),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 9,
                      ),
                      child: Text(
                        context.l10n.dockMoveToDesktop,
                        style: const TextStyle(
                          color: Color(0xFFF2F1EF),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (_drawerOpen && visible)
            Positioned.fill(
              child: _AllAppsDrawer(
                onClose: () => setState(() => _drawerOpen = false),
                onLaunch: (item, rect) {
                  setState(() => _drawerOpen = false);
                  launchHomeApp(context, ref, item, rect);
                },
              ),
            ),
        ],
      ),
    );
  }
}

String _nameOf(BuildContext context, HomeGridItem item) =>
    item.localApp?.titleFor(context) ?? item.app?.name ?? '';

DenialWindow? _windowFor(
  HomeGridItem item,
  List<DenialWindow> windows,
  AppLauncher launcher,
) {
  final app = item.app;
  if (app != null) return launcher.findOpenWindow(app, windows);
  final local = item.localApp;
  if (local != null) {
    for (final window in windows) {
      if (window.isLocalFlutter && window.appId == local.id) {
        return window;
      }
    }
  }
  return null;
}

class _DockDivider extends StatelessWidget {
  const _DockDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 34,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: context.shellColors.hairlineSoft,
    );
  }
}

class _AllAppsButton extends StatefulWidget {
  const _AllAppsButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_AllAppsButton> createState() => _AllAppsButtonState();
}

class _AllAppsButtonState extends State<_AllAppsButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: context.l10n.dockAllApps,
      child: Semantics(
        button: true,
        label: context.l10n.dockAllApps,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: SizedBox(
              width: 62,
              height: 62,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: _hover
                        ? context.shellColors.hairlineSoft
                        : const Color(0x00000000),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: SvgPicture.asset(
                    _archMarkAsset,
                    width: 30,
                    height: 30,
                    colorFilter: ColorFilter.mode(
                      context.shellColors.panelText,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DockButton extends StatefulWidget {
  const _DockButton({
    super.key,
    required this.item,
    required this.running,
    required this.active,
    required this.pinned,
    required this.onTap,
    this.onDragStart,
    this.onDragMove,
    this.onDragEnd,
  });

  final HomeGridItem item;
  final bool running;
  final bool active;
  final bool pinned;
  final void Function(Rect iconRect) onTap;

  final void Function(Offset global)? onDragStart;
  final void Function(Offset global)? onDragMove;
  final VoidCallback? onDragEnd;

  @override
  State<_DockButton> createState() => _DockButtonState();
}

class _DockButtonState extends State<_DockButton> {
  bool _hover = false;
  bool _pressed = false;

  String get _name => _nameOf(context, widget.item);

  Rect? _iconRect() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    final accent = theme.accentPalette.primary;
    final scale = _pressed ? 0.93 : (_hover ? 1.05 : 1.0);
    return Tooltip(
      // The dock owns the long press (it lifts the icon); a tooltip trigger
      // on the same gesture competes for it. Hover still shows the name.
      message: _name,
      triggerMode: TooltipTriggerMode.manual,
      child: Semantics(
        button: true,
        label: _name,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            // A long press picks the icon up; a press that never travels
            // still ends in the item menu.
            onLongPressStart: widget.onDragStart == null
                ? null
                : (details) => widget.onDragStart!(details.globalPosition),
            onLongPressMoveUpdate: widget.onDragMove == null
                ? null
                : (details) => widget.onDragMove!(details.globalPosition),
            onLongPressEnd: widget.onDragEnd == null
                ? null
                : (_) => widget.onDragEnd!(),
            onTap: () {
              final rect = _iconRect();
              if (rect != null) widget.onTap(rect);
            },
            child: SizedBox(
              width: 66,
              height: 74,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedScale(
                    scale: scale,
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOutCubic,
                    child: AnimatedSlide(
                      offset: _hover ? const Offset(0, -0.06) : Offset.zero,
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeOutCubic,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: widget.active
                              ? [
                                  BoxShadow(
                                    color: accent.withValues(alpha: 0.30),
                                    blurRadius: 18,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : null,
                        ),
                        child: SizedBox.square(
                          dimension: 54,
                          child: LauncherIcon.of(widget.item),
                        ),
                      ),
                    ),
                  ),
                  if (widget.active)
                    Positioned(
                      bottom: 1,
                      child: Container(
                        width: 18,
                        height: 4,
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    )
                  else if (widget.running)
                    Positioned(
                      bottom: 1,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DockItemMenu extends StatelessWidget {
  const _DockItemMenu({required this.title, required this.onRemove});

  final String title;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    final l10n = context.l10n;
    return Center(
      child: SizedBox(
        width: 320,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.panelColor(context.shellColors.panelBackground),
            borderRadius: BorderRadius.circular(theme.scaledRadius(18)),
            border: Border.all(color: context.shellColors.hairlineSoft),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 36,
                offset: Offset(0, 16),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.shellColors.panelText,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onRemove,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: context.shellColors.tileOff,
                      borderRadius: BorderRadius.circular(
                        theme.scaledRadius(12),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline_rounded,
                            size: 20,
                            color: context.shellColors.textSecondary,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            l10n.dockRemove,
                            style: TextStyle(
                              color: context.shellColors.panelText,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AllAppsDrawer extends ConsumerStatefulWidget {
  const _AllAppsDrawer({required this.onClose, required this.onLaunch});

  final VoidCallback onClose;
  final void Function(HomeGridItem item, Rect rect) onLaunch;

  @override
  ConsumerState<_AllAppsDrawer> createState() => _AllAppsDrawerState();
}

class _AllAppsDrawerState extends ConsumerState<_AllAppsDrawer> {
  static const List<String> _groupOrder = <String>[
    'android',
    'development',
    'graphics',
    'network',
    'multimedia',
    'office',
    'game',
    'system',
    'other',
  ];

  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _pageController = PageController();
  String _query = '';
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(_focusedChanged);
  }

  @override
  void dispose() {
    _searchFocus.removeListener(_focusedChanged);
    _search.dispose();
    _searchFocus.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _focusedChanged() => setState(() {});

  String _searchText(HomeGridItem item) {
    final app = item.app;
    if (app != null) {
      return app.searchableText;
    }
    final local = item.localApp;
    if (local == null) {
      return '';
    }
    return <String>[
      local.id,
      local.title,
      ...local.categories,
    ].join(' ').toLowerCase();
  }

  String _groupOf(HomeGridItem item) {
    // Android packages run through droidloom, whatever categories their
    // generated entry carries.
    if (item.app?.exec.contains('droidloomctl') ?? false) {
      return 'android';
    }
    final categories =
        item.app?.categories ?? item.localApp?.categories ?? const <String>[];
    for (final raw in categories) {
      final category = raw.toLowerCase();
      if (category.contains('development') || category == 'ide') {
        return 'development';
      }
      if (category.contains('graphics')) {
        return 'graphics';
      }
      if (category.contains('network') ||
          category.contains('internet') ||
          category == 'webbrowser') {
        return 'network';
      }
      if (category.contains('audio') ||
          category.contains('video') ||
          category.contains('multimedia')) {
        return 'multimedia';
      }
      if (category.contains('office')) {
        return 'office';
      }
      if (category.contains('game')) {
        return 'game';
      }
      if (category.contains('system') ||
          category.contains('settings') ||
          category.contains('utility')) {
        return 'system';
      }
    }
    return 'other';
  }

  String _groupLabel(BuildContext context, String key) {
    final l10n = context.l10n;
    return switch (key) {
      'all' => l10n.dockAllApps,
      'android' => l10n.appGroupAndroid,
      'development' => l10n.appGroupDevelopment,
      'graphics' => l10n.appGroupGraphics,
      'network' => l10n.appGroupNetwork,
      'multimedia' => l10n.appGroupMultimedia,
      'office' => l10n.appGroupOffice,
      'game' => l10n.appGroupGame,
      'system' => l10n.appGroupSystem,
      _ => l10n.appGroupOther,
    };
  }

  String? _desktopPathOf(HomeGridItem item) {
    final app = item.app;
    if (app != null) {
      return app.desktopPath;
    }
    final local = item.localApp;
    if (local == null) {
      return null;
    }
    final paths = ref.read(runtimePathsProvider);
    return p.join(paths.dataHome, 'applications', 'denial-${local.id}.desktop');
  }

  Future<void> _addToDesktop(HomeGridItem item) async {
    final target = _desktopPathOf(item);
    if (target == null) {
      return;
    }
    final directory = Directory(
      ref.read(runtimePathsProvider).desktopDirectory,
    );
    try {
      await directory.create(recursive: true);
      final link = Link(p.join(directory.path, p.basename(target)));
      if (await link.exists() || await File(link.path).exists()) {
        return;
      }
      await link.create(target);
    } on FileSystemException {
      return;
    }
  }

  String? _linkPathOf(HomeGridItem item) {
    final target = _desktopPathOf(item);
    if (target == null) {
      return null;
    }
    final directory = ref.read(runtimePathsProvider).desktopDirectory;
    return p.join(directory, p.basename(target));
  }

  bool _isOnDesktop(HomeGridItem item) {
    final path = _linkPathOf(item);
    return path != null && (Link(path).existsSync() || File(path).existsSync());
  }

  Future<void> _removeFromDesktop(HomeGridItem item) async {
    final path = _linkPathOf(item);
    if (path == null) {
      return;
    }
    try {
      final link = Link(path);
      if (link.existsSync()) {
        await link.delete();
        return;
      }
      final file = File(path);
      if (file.existsSync()) {
        await file.delete();
      }
    } on FileSystemException {
      return;
    }
  }

  void _showMenu(HomeGridItem item) {
    final onDesktop = _isOnDesktop(item);
    ref
        .read(shellPopupControllerProvider.notifier)
        .show(
          keyName: 'app-menu-${item.id}',
          debugLabel: 'Application menu',
          builder: (context, handle) => _AppMenu(
            title: _nameOf(context, item),
            onAddToDesktop: onDesktop
                ? null
                : () {
                    handle.close();
                    unawaited(_addToDesktop(item));
                  },
            onRemoveFromDesktop: onDesktop
                ? () {
                    handle.close();
                    unawaited(_removeFromDesktop(item));
                  }
                : null,
          ),
        );
  }

  void _setQuery(String value) {
    setState(() {
      _query = value;
      _page = 0;
    });
    if (_pageController.hasClients) {
      _pageController.jumpToPage(0);
    }
  }

  void _clearQuery() {
    _search.clear();
    _setQuery('');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = ShellTheme.of(context);
    final catalog = ref.watch(allApplicationsProvider);
    final query = _query.trim().toLowerCase();
    final items = (catalog.asData?.value ?? const <HomeGridItem>[])
        .where((item) => query.isEmpty || _searchText(item).contains(query))
        .toList(growable: false);
    final groups = <String, List<HomeGridItem>>{};
    for (final item in items) {
      groups.putIfAbsent(_groupOf(item), () => <HomeGridItem>[]).add(item);
    }
    // The first page is everything; the rest are the categories.
    final visibleGroups = <String>[
      if (items.isNotEmpty) 'all',
      for (final key in _groupOrder)
        if (groups[key]?.isNotEmpty ?? false) key,
    ];
    final pageCount = visibleGroups.isEmpty ? 1 : visibleGroups.length;
    final page = _page.clamp(0, pageCount - 1);
    final searching = query.isNotEmpty;

    return ColoredBox(
      color: const Color(0x73000000),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onClose,
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: FractionallySizedBox(
              widthFactor: 0.84,
              heightFactor: 0.76,
              child: ShellBackdropBlur(
                separateChild: true,
                blur: theme.effectivePanelOpacity < 1.0,
                borderRadius: BorderRadius.circular(theme.scaledRadius(18)),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.cardColor(context.shellColors.panelBackground),
                    borderRadius: BorderRadius.circular(theme.scaledRadius(18)),
                    border: Border.all(color: context.shellColors.hairlineSoft),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x66000000),
                        blurRadius: 40,
                        offset: Offset(0, 18),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 16, 22, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(child: _searchField(context)),
                            const SizedBox(width: 18),
                            Text(
                              searching
                                  ? l10n.dockSearchApps
                                  : l10n.dockAllApps,
                              style: TextStyle(
                                color: context.shellColors.panelText,
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                height: 1.1,
                              ),
                            ),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: widget.onClose,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 22,
                                  color: context.shellColors.textTertiary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (!searching && visibleGroups.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          _groupTabs(context, visibleGroups, page),
                        ],
                        const SizedBox(height: 12),
                        Expanded(
                          child: PageView.builder(
                            controller: _pageController,
                            onPageChanged: (index) =>
                                setState(() => _page = index),
                            itemCount: pageCount,
                            itemBuilder: (context, index) {
                              if (visibleGroups.isEmpty) {
                                return _emptyState(context);
                              }
                              return _AppsGrid(
                                items: visibleGroups[index] == 'all'
                                    ? items
                                    : groups[visibleGroups[index]]!,
                                onLaunch: widget.onLaunch,
                                onLongPress: _showMenu,
                              );
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(
                            children: [
                              if (!searching && visibleGroups.length > 1)
                                Text(
                                  '←  滑动切换分组  →',
                                  style: TextStyle(
                                    color: context.shellColors.textTertiary,
                                    fontSize: 11.5,
                                  ),
                                ),
                              const Spacer(),
                              if (!searching && visibleGroups.length > 1)
                                Row(
                                  children: [
                                    for (
                                      var index = 0;
                                      index < visibleGroups.length;
                                      index += 1
                                    )
                                      AnimatedContainer(
                                        duration:
                                            MediaQuery.disableAnimationsOf(
                                              context,
                                            )
                                            ? Duration.zero
                                            : const Duration(milliseconds: 180),
                                        margin: const EdgeInsets.only(left: 6),
                                        width: index == page ? 18 : 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          color: index == page
                                              ? theme.accent
                                              : context.shellColors.textTertiary
                                                    .withAlpha(70),
                                          borderRadius: BorderRadius.circular(
                                            3,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _searchField(BuildContext context) {
    final theme = ShellTheme.of(context);
    final background = context.shellColors.tileOff;
    return Semantics(
      textField: true,
      label: context.l10n.dockSearchApps,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: _searchFocus.hasFocus
                ? theme.accent
                : context.shellColors.hairlineSoft,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.search_rounded,
              size: 18,
              color: context.shellColors.textSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  if (_query.isEmpty)
                    Text(
                      context.l10n.dockSearchApps,
                      style: TextStyle(
                        color: context.shellColors.textTertiary,
                        fontSize: 13,
                      ),
                    ),
                  EditableText(
                    controller: _search,
                    focusNode: _searchFocus,
                    maxLines: 1,
                    style: TextStyle(
                      color: context.shellColors.panelText,
                      fontSize: 13,
                    ),
                    cursorColor: theme.accent,
                    backgroundCursorColor: context.shellColors.textSecondary,
                    selectionColor: theme.accentPalette.container,
                    onChanged: _setQuery,
                  ),
                ],
              ),
            ),
            if (_query.isNotEmpty)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _clearQuery,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(
                    Icons.close_rounded,
                    size: 15,
                    color: context.shellColors.textTertiary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _groupTabs(BuildContext context, List<String> groups, int page) {
    final theme = ShellTheme.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < groups.length; index += 1)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _pageController.animateToPage(
                  index,
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                );
              },
              child: AnimatedContainer(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 160),
                margin: const EdgeInsets.only(right: 8),
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 13),
                decoration: BoxDecoration(
                  color: index == page
                      ? theme.accent.withAlpha(30)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: index == page
                        ? theme.accent.withAlpha(80)
                        : Colors.transparent,
                  ),
                ),
                child: Center(
                  child: Text(
                    _groupLabel(context, groups[index]),
                    style: TextStyle(
                      color: index == page
                          ? theme.accent
                          : context.shellColors.textSecondary,
                      fontSize: 12.5,
                      fontWeight: index == page
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Text(
        _query.isEmpty
            ? context.l10n.dockNoApplications
            : context.l10n.dockNoMatches,
        style: TextStyle(color: context.shellColors.textTertiary, fontSize: 13),
      ),
    );
  }
}

class _AppsGrid extends StatelessWidget {
  const _AppsGrid({
    required this.items,
    required this.onLaunch,
    required this.onLongPress,
  });

  final List<HomeGridItem> items;
  final void Function(HomeGridItem item, Rect rect) onLaunch;
  final void Function(HomeGridItem item) onLongPress;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 8,
        mainAxisSpacing: 6,
        crossAxisSpacing: 14,
        mainAxisExtent: 104,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return Builder(
          builder: (tileContext) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              final box = tileContext.findRenderObject();
              final rect = box is RenderBox && box.hasSize
                  ? box.localToGlobal(Offset.zero) & box.size
                  : Rect.zero;
              onLaunch(item, rect);
            },
            onLongPress: () => onLongPress(item),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(dimension: 54, child: LauncherIcon.of(item)),
                const SizedBox(height: 7),
                Text(
                  _nameOf(context, item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.shellColors.panelText,
                    fontSize: 11.5,
                    height: 1.1,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AppMenuAction extends StatelessWidget {
  const _AppMenuAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.shellColors.tileOff,
            borderRadius: BorderRadius.circular(theme.scaledRadius(12)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
            child: Row(
              children: [
                Icon(icon, size: 20, color: context.shellColors.textSecondary),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: TextStyle(
                    color: context.shellColors.panelText,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AppMenu extends StatelessWidget {
  const _AppMenu({
    required this.title,
    required this.onAddToDesktop,
    required this.onRemoveFromDesktop,
  });

  final String title;
  final VoidCallback? onAddToDesktop;
  final VoidCallback? onRemoveFromDesktop;

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    return Center(
      child: SizedBox(
        width: 320,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.panelColor(context.shellColors.panelBackground),
            borderRadius: BorderRadius.circular(theme.scaledRadius(18)),
            border: Border.all(color: context.shellColors.hairlineSoft),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 36,
                offset: Offset(0, 16),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.shellColors.panelText,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (onAddToDesktop case final add?)
                  _AppMenuAction(
                    icon: Icons.add_to_home_screen_rounded,
                    label: context.l10n.dockAddToDesktop,
                    onPressed: add,
                  ),
                if (onRemoveFromDesktop case final remove?)
                  _AppMenuAction(
                    icon: Icons.remove_circle_outline_rounded,
                    label: context.l10n.dockRemoveFromDesktop,
                    onPressed: remove,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

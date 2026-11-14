import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  HomeDragController? _drag;
  HomeDrag? _lastDrag;
  bool _drawerOpen = false;

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
    super.dispose();
  }

  void _detachDrag() {
    _drag?.drag.removeListener(_dragChanged);
    _drag?.pointer.removeListener(_pointerChanged);
    _drag = null;
  }

  void _pointerChanged() {
    if (mounted) setState(() {});
  }

  void _dragChanged() {
    final current = _drag?.drag.value;
    final wasLanding = _lastDrag?.landing != null;
    if (current != null &&
        current.landing != null &&
        !wasLanding &&
        current.item.isApp &&
        _overDock(_drag!.pointer.value)) {
      unawaited(ref.read(dockPinnedProvider.notifier).add(current.item.id));
      ref.read(hapticsServiceProvider).pulse();
    }
    _lastDrag = current;
    if (mounted) setState(() {});
  }

  bool _overDock(Offset pointer) {
    final box = _dockKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return false;
    return (box.localToGlobal(Offset.zero) & box.size)
        .inflate(18)
        .contains(pointer);
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
              unawaited(
                ref.read(dockPinnedProvider.notifier).remove(item.id),
              );
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
    final pinnedIds =
        ref.watch(dockPinnedProvider).value ?? DockPinnedController.defaults;
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
    final draggingOver =
        _drag?.drag.value != null &&
        _drag!.drag.value!.landing == null &&
        _drag!.drag.value!.item.isApp &&
        _overDock(_drag!.pointer.value);

    Widget entry(HomeGridItem item, {required bool pinned}) {
      final running = _windowFor(item, windows, launcher);
      return _DockButton(
        item: item,
        running: running != null,
        active: running != null && running.objectId == foreground,
        pinned: pinned,
        onLongPress: pinned ? () => _showDockMenu(item) : null,
        onTap: (rect) => launchHomeApp(context, ref, item, rect),
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
          border: Border.all(
            color: draggingOver
                ? accent
                : context.shellColors.hairlineSoft,
            width: draggingOver ? 2 : 1,
          ),
          boxShadow: [
            const BoxShadow(
              color: Color(0x66000000),
              blurRadius: 34,
              offset: Offset(0, 14),
            ),
            if (draggingOver)
              BoxShadow(
                color: accent.withValues(alpha: 0.30),
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
              for (final item in pinned)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: entry(item, pinned: true),
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

    return Stack(
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
    required this.item,
    required this.running,
    required this.active,
    required this.pinned,
    required this.onTap,
    this.onLongPress,
  });

  final HomeGridItem item;
  final bool running;
  final bool active;
  final bool pinned;
  final void Function(Rect iconRect) onTap;
  final VoidCallback? onLongPress;

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
      message: _name,
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
            onLongPress: widget.onLongPress,
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
    return <String>[local.id, local.title, ...local.categories]
        .join(' ')
        .toLowerCase();
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
    final directory = Directory(ref.read(runtimePathsProvider).desktopDirectory);
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
    return path != null &&
        (Link(path).existsSync() || File(path).existsSync());
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
                                  for (var index = 0;
                                      index < visibleGroups.length;
                                      index += 1)
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
                                            : context
                                                  .shellColors
                                                  .textTertiary
                                                  .withAlpha(70),
                                        borderRadius: BorderRadius.circular(3),
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
        style: TextStyle(
          color: context.shellColors.textTertiary,
          fontSize: 13,
        ),
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
                SizedBox.square(
                  dimension: 54,
                  child: LauncherIcon.of(item),
                ),
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

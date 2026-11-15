import 'dart:async';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../local_apps/local_flutter_application.dart';
import '../../platform/denial_bridge_provider.dart';
import '../../state/icon_theme.dart';
import '../../state/system_status.dart';
import '../launcher_providers.dart';
import '../models/desktop_app.dart';
import '../models/home_clock_info.dart';
import '../models/home_grid_item.dart';
import '../repositories/desktop_apps_repository.dart';
import '../repositories/home_layout_repository.dart';
import '../services/app_launcher.dart';
import 'home_grid_layout.dart';

final desktopAppsRepositoryProvider = Provider<DesktopAppsRepository>((ref) {
  return DesktopAppsRepository(
    paths: ref.watch(runtimePathsProvider),
    preferredIconTheme: ref.watch(resolvedShellIconThemeProvider),
  );
});

final homeLayoutRepositoryProvider = Provider<HomeLayoutRepository>((ref) {
  return HomeLayoutRepository(paths: ref.watch(runtimePathsProvider));
});

final appLauncherProvider = Provider<AppLauncher>((ref) {
  return AppLauncher(bridge: ref.watch(denialBridgeProvider));
});

final homeGridControllerProvider =
    AsyncNotifierProvider<HomeGridController, HomeGridState>(
      HomeGridController.new,
    );

final homeClockProvider = Provider<HomeClockInfo>((ref) {
  final locale = HomeClockInfo.localeFromEnvironment(
    ref.watch(runtimePathsProvider).environment,
  );
  return HomeClockInfo.fromShell(
    now: ref.watch(clockProvider).value ?? DateTime.now(),
    locale: locale,
    power: ref.watch(effectivePowerStatusProvider),
  );
}, isAutoDispose: true);

class HomeGridState {
  HomeGridState({
    required List<HomeGridItem?> slots,
    this.page = 0,
    this.catalog = const <HomeGridItem>[],
  }) : slots = List.unmodifiable(slots);

  HomeGridState._({
    required this.slots,
    required this.page,
    required this.catalog,
  });

  final List<HomeGridItem?> slots;
  final int page;

  /// Every launchable application: the dock, the desktop menu and the launch
  /// animations read this. The home grid draws [slots], the shortcuts in the
  /// user's desktop folder.
  final List<HomeGridItem> catalog;

  /// Every application on the grid, folder contents included.
  Iterable<HomeGridItem> get apps => HomeGridLayout.appsIn(slots);

  HomeGridState copyWith({
    List<HomeGridItem?>? slots,
    int? page,
    List<HomeGridItem>? catalog,
  }) {
    return HomeGridState._(
      slots: slots == null ? this.slots : List.unmodifiable(slots),
      page: page ?? this.page,
      catalog: catalog ?? this.catalog,
    );
  }
}

class HomeGridController extends AsyncNotifier<HomeGridState> {
  static const Duration _periodicRefreshInterval = Duration(minutes: 5);
  static const Duration _visibleRefreshMinInterval = Duration(seconds: 45);
  static const Duration _filesystemRefreshDebounce = Duration(
    milliseconds: 200,
  );

  Timer? _desktopRefreshTimer;
  Timer? _activationRefreshTimer;
  Timer? _filesystemRefreshTimer;
  DesktopAppsWatcher? _desktopAppsWatcher;
  DateTime? _lastDesktopRefresh;
  bool _desktopRefreshInFlight = false;
  bool _desktopRefreshTriggersStarted = false;
  bool _desktopAppsDirty = false;
  bool _launcherActive = true;
  int _buildGeneration = 0;

  /// The orientation the slots are laid out for; null while they belong to
  /// whichever orientation the grid shows first.
  HomeOrientation? _orientation;

  /// Every orientation's saved layout, the shown one as of its last save.
  Map<HomeOrientation, List<HomeLayoutSlot?>> _layouts = {};

  @override
  Future<HomeGridState> build() async {
    final generation = ++_buildGeneration;
    _desktopRefreshTimer = null;
    _activationRefreshTimer = null;
    _filesystemRefreshTimer = null;
    _desktopAppsWatcher = null;
    _lastDesktopRefresh = null;
    _desktopRefreshInFlight = false;
    _desktopRefreshTriggersStarted = false;
    _desktopAppsDirty = false;
    _launcherActive = true;
    ref.onDispose(() {
      if (_buildGeneration == generation) {
        _buildGeneration++;
      }
      _activationRefreshTimer?.cancel();
      _activationRefreshTimer = null;
      _desktopRefreshTimer?.cancel();
      _desktopRefreshTimer = null;
      _filesystemRefreshTimer?.cancel();
      _filesystemRefreshTimer = null;
      unawaited(_desktopAppsWatcher?.dispose());
      _desktopAppsWatcher = null;
      _desktopRefreshTriggersStarted = false;
    });
    // Icons come from the theme directories, and the catalog also unpacks
    // Denial's bundled pack on first run: let it finish before the first
    // lookup rather than resolve every icon against the fallback order.
    try {
      await ref.watch(iconThemeCatalogProvider.future);
    } on Object {
      // A catalog failure leaves the default icon order in place.
    }
    final appsRepository = ref.watch(desktopAppsRepositoryProvider);
    final layoutRepository = ref.watch(homeLayoutRepositoryProvider);
    final localApps = ref
        .watch(localFlutterApplicationRegistryProvider)
        .applications
        .toList(growable: false);
    try {
      final apps = await _loadApplications(appsRepository, reason: 'initial');
      final shortcuts = await _loadShortcuts(appsRepository);
      final saved = await layoutRepository.readSavedLayouts();
      // Portrait first, which is where a phone starts.
      final orientation = HomeOrientation.values
          .where(saved.layouts.containsKey)
          .firstOrNull;
      final savedLayout = orientation == null
          ? saved.unassigned
          : saved.layouts[orientation];
      final slots = HomeGridLayout.initialSlotsForApps(
        shortcuts,
        localApps,
        savedLayout,
      );
      final catalog = HomeGridLayout.catalogItems(apps, localApps);
      if (!_isBuildActive(generation)) {
        return HomeGridState(slots: slots, catalog: catalog);
      }
      _orientation = orientation;
      _layouts = {...saved.layouts};
      _lastDesktopRefresh = DateTime.now();
      if (_savedLayoutNeedsRefresh(shortcuts, localApps, savedLayout, slots)) {
        _save(slots);
      }
      unawaited(_startDesktopRefreshTriggers(generation, appsRepository));
      return HomeGridState(slots: slots, catalog: catalog);
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> refreshDesktopApps({String reason = 'manual'}) async {
    if (state.asData?.value == null) {
      return;
    }

    // An icon theme change re-resolves every icon, not just the ones the
    // visible launcher would have refreshed on its own.
    if (!_launcherActive &&
        reason != 'manual' &&
        reason != 'icon-theme' &&
        reason != 'icons' &&
        reason != 'shortcuts') {
      return;
    }

    final lastRefresh = _lastDesktopRefresh;
    if (reason == 'launcher-visible' &&
        lastRefresh != null &&
        // A complete watcher already reports every top-level change, so
        // returning home spends no isolate rescanning unchanged entries.
        ((_desktopAppsWatcher?.complete ?? false) ||
            DateTime.now().difference(lastRefresh) <
                _visibleRefreshMinInterval)) {
      return;
    }

    if (_desktopRefreshInFlight) {
      return;
    }

    final generation = _buildGeneration;
    _desktopAppsDirty = false;
    _desktopRefreshInFlight = true;
    try {
      final repository = ref.read(desktopAppsRepositoryProvider);
      final current = state.asData?.value;
      if (current == null) {
        return;
      }
      final localApps = ref
          .read(localFlutterApplicationRegistryProvider)
          .applications;
      // An icon entering or leaving the desktop folder changes the grid, not
      // the catalog of installed apps. Rescanning every .desktop entry for
      // that cost seconds, so a moved icon lingered on screen.
      final shortcutsOnly = reason == 'shortcuts';
      final apps = shortcutsOnly
          ? null
          : await _loadApplications(repository, reason: reason);
      final shortcuts = await _loadShortcuts(repository);
      if (!_isBuildActive(generation)) {
        return;
      }
      _lastDesktopRefresh = DateTime.now();
      final catalog = apps == null
          ? current.catalog
          : HomeGridLayout.catalogItems(apps, localApps);
      final slots = HomeGridLayout.refreshSlotsForApps(
        current.slots,
        shortcuts,
        localApps,
      );
      final catalogChanged = !_sameCatalog(current.catalog, catalog);
      final slotsChanged = !_sameSlots(current.slots, slots);
      if (!catalogChanged && !slotsChanged) {
        return;
      }
      state = AsyncData(
        HomeGridState(
          slots: slots,
          page: current.page,
          catalog: catalogChanged ? catalog : current.catalog,
        ),
      );
      if (slotsChanged) {
        _save(slots);
      }
    } finally {
      if (_isBuildActive(generation)) {
        _desktopRefreshInFlight = false;
        if (_desktopAppsDirty && _launcherActive) {
          _scheduleFilesystemRefresh();
        }
      }
    }
  }

  void setLauncherActive(bool active) {
    if (_launcherActive == active) {
      return;
    }

    _launcherActive = active;
    _activationRefreshTimer?.cancel();
    _activationRefreshTimer = null;
    if (active) {
      if (_desktopAppsDirty) {
        _scheduleFilesystemRefresh();
        return;
      }
      final generation = _buildGeneration;
      _activationRefreshTimer = Timer(const Duration(milliseconds: 750), () {
        if (!_isBuildActive(generation)) {
          return;
        }
        _activationRefreshTimer = null;
        unawaited(refreshDesktopApps(reason: 'launcher-visible'));
      });
    }
  }

  Future<void> _startDesktopRefreshTriggers(
    int generation,
    DesktopAppsRepository repository,
  ) async {
    try {
      if (_desktopRefreshTriggersStarted) {
        return;
      }
      _desktopRefreshTriggersStarted = true;
      _desktopRefreshTimer = Timer.periodic(_periodicRefreshInterval, (_) {
        if (!_isBuildActive(generation) || !_launcherActive) {
          return;
        }
        unawaited(refreshDesktopApps(reason: 'timer'));
      });
      final watcher = await repository.watchApplications(
        onChanged: () {
          if (!_isBuildActive(generation)) {
            return;
          }
          _desktopAppsDirty = true;
          if (_launcherActive) {
            _scheduleFilesystemRefresh();
          }
        },
        onIconsChanged: () {
          if (!_isBuildActive(generation)) {
            return;
          }
          // Icons are drawn on the home grid and the dock even when the app
          // drawer is closed, so this refresh cannot wait for it.
          _scheduleFilesystemRefresh(reason: 'icons');
        },
        onShortcutsChanged: () {
          if (!_isBuildActive(generation)) {
            return;
          }
          _scheduleFilesystemRefresh(reason: 'shortcuts');
        },
      );
      if (!_isBuildActive(generation) || !_desktopRefreshTriggersStarted) {
        await watcher.dispose();
        return;
      }
      _desktopAppsWatcher = watcher;
    } on Object {
      // Filesystem notifications are best effort. Keep the periodic timer as
      // the fallback when the platform cannot establish a watcher.
    }
  }

  void _scheduleFilesystemRefresh({String reason = 'filesystem'}) {
    _filesystemRefreshTimer?.cancel();
    _filesystemRefreshTimer = Timer(_filesystemRefreshDebounce, () {
      _filesystemRefreshTimer = null;
      unawaited(refreshDesktopApps(reason: reason));
    });
  }

  bool _isBuildActive(int generation) =>
      ref.mounted && generation == _buildGeneration;

  /// Runs on this isolate: the repository keeps its icon index and resolved
  /// icons, so re-reading a folder after an icon enters or leaves it costs a
  /// few file reads instead of rescanning every icon theme. An isolate copy
  /// would throw that cache away each time and make the grid lag seconds.
  Future<List<DesktopApp>> _loadShortcuts(DesktopAppsRepository repository) {
    return repository.loadDesktopShortcuts();
  }

  Future<List<DesktopApp>> _loadApplications(
    DesktopAppsRepository repository, {
    required String reason,
  }) {
    return Isolate.run(
      repository.loadApplications,
      debugName: 'denia-launcher-desktop-$reason',
    );
  }

  /// The orientation the grid shows, null before it first lays out.
  HomeOrientation? get orientation => _orientation;

  /// Lays the grid out for [orientation], in pages of [pageSize]: its saved
  /// layout, or the shown one reflowed into the new pages when it has none.
  void arrange(HomeOrientation orientation, int pageSize) {
    final current = state.asData?.value;
    final shown = _orientation;
    if (current == null || orientation == shown) {
      return;
    }
    _orientation = orientation;
    if (shown == null) {
      // The slots are this orientation's layout from now on.
      _save(current.slots);
      return;
    }

    _layouts[shown] = _layoutOf(current.slots);
    final saved = _layouts[orientation];
    final slots = saved == null
        ? HomeGridLayout.reflowSlots(current.slots, pageSize)
        : HomeGridLayout.initialSlotsForApps(
            [for (final item in current.apps) ?item.app],
            ref.read(localFlutterApplicationRegistryProvider).applications,
            saved,
          );
    state = AsyncData(current.copyWith(slots: slots));
    _save(slots);
  }

  void setPage(int page) {
    final current = state.asData?.value;
    if (current == null || current.page == page) {
      return;
    }

    state = AsyncData(current.copyWith(page: page));
  }

  bool canMoveSlot(int fromIndex, int toIndex, int pageSize) {
    final slots = state.asData?.value.slots;
    return slots != null &&
        HomeGridLayout.canMoveSlot(slots, fromIndex, toIndex, pageSize);
  }

  void moveSlot(int fromIndex, int toIndex, int pageSize) {
    _update(
      (slots) => HomeGridLayout.moveSlot(slots, fromIndex, toIndex, pageSize),
    );
  }

  bool canResizeSlot(
    int index,
    int anchor,
    int colSpan,
    int rowSpan,
    int pageSize,
  ) {
    final slots = state.asData?.value.slots;
    return slots != null &&
        HomeGridLayout.canResizeSlot(
          slots,
          index,
          anchor,
          colSpan,
          rowSpan,
          pageSize,
        );
  }

  void resizeSlot(
    int index,
    int anchor,
    int colSpan,
    int rowSpan,
    int pageSize,
  ) {
    _update(
      (slots) => HomeGridLayout.resizeSlot(
        slots,
        index,
        anchor,
        colSpan,
        rowSpan,
        pageSize,
      ),
    );
  }

  bool canMerge(int fromIndex, int targetIndex) {
    final slots = state.asData?.value.slots;
    return slots != null &&
        HomeGridLayout.canMerge(slots, fromIndex, targetIndex);
  }

  /// Drops the app at [fromIndex] on the app or folder at [targetIndex]. A
  /// new folder is named [folderName].
  void merge(int fromIndex, int targetIndex, {required String folderName}) {
    _update(
      (slots) => HomeGridLayout.merge(
        slots,
        fromIndex,
        targetIndex,
        folderId: HomeGridLayout.newFolderId(slots),
        folderName: folderName,
      ),
    );
  }

  void moveOutOfFolder(
    int folderIndex,
    String appId,
    int toIndex,
    int pageSize,
  ) {
    _update(
      (slots) => HomeGridLayout.moveOutOfFolder(
        slots,
        folderIndex,
        appId,
        toIndex,
        pageSize,
      ),
    );
  }

  void moveFromFolderInto(
    int folderIndex,
    String appId,
    int targetIndex, {
    required String folderName,
  }) {
    _update(
      (slots) => HomeGridLayout.moveFromFolderInto(
        slots,
        folderIndex,
        appId,
        targetIndex,
        folderId: HomeGridLayout.newFolderId(slots),
        folderName: folderName,
      ),
    );
  }

  void reorderFolder(int folderIndex, String appId, int position) {
    _update(
      (slots) =>
          HomeGridLayout.reorderFolder(slots, folderIndex, appId, position),
    );
  }

  void renameFolder(int folderIndex, String name) {
    _update((slots) => HomeGridLayout.renameFolder(slots, folderIndex, name));
  }

  /// Applies one layout operation and saves its result; a null result is a
  /// change that was not possible.
  void _update(List<HomeGridItem?>? Function(List<HomeGridItem?> slots) edit) {
    final current = state.asData?.value;
    if (current == null) {
      return;
    }
    final slots = edit(current.slots);
    if (slots == null) {
      return;
    }
    state = AsyncData(current.copyWith(slots: slots));
    _save(slots);
  }

  /// Saves [slots] as the shown orientation's layout, beside the others.
  void _save(List<HomeGridItem?> slots) {
    final layout = _layoutOf(slots);
    final orientation = _orientation;
    if (orientation != null) {
      _layouts[orientation] = layout;
    }
    unawaited(
      ref
          .read(homeLayoutRepositoryProvider)
          .saveLayouts(
            orientation == null
                ? HomeSavedLayouts(unassigned: layout)
                : HomeSavedLayouts(layouts: {..._layouts}),
          ),
    );
  }
}

List<HomeLayoutSlot?> _layoutOf(List<HomeGridItem?> slots) => [
  for (final slot in slots) slot == null ? null : HomeLayoutSlot.of(slot),
];

bool _sameCatalog(List<HomeGridItem> first, List<HomeGridItem> second) {
  if (first.length != second.length) {
    return false;
  }
  for (var index = 0; index < first.length; index += 1) {
    final a = first[index];
    final b = second[index];
    if (a.id != b.id) {
      return false;
    }
    if (a.app?.iconPath != b.app?.iconPath ||
        a.app?.name != b.app?.name ||
        a.localApp?.title != b.localApp?.title) {
      return false;
    }
  }
  return true;
}

bool _sameSlots(List<HomeGridItem?> first, List<HomeGridItem?> second) {
  if (first.length != second.length) {
    return false;
  }
  for (var index = 0; index < first.length; index += 1) {
    final a = first[index];
    final b = second[index];
    if (a?.id != b?.id) {
      return false;
    }
    if (a?.app?.iconPath != b?.app?.iconPath ||
        a?.app?.name != b?.app?.name) {
      return false;
    }
  }
  return true;
}


bool _savedLayoutNeedsRefresh(
  List<DesktopApp> apps,
  Iterable<LocalFlutterApplication> localApps,
  List<HomeLayoutSlot?>? savedLayout,
  List<HomeGridItem?> slots,
) {
  if (savedLayout == null || savedLayout.length != slots.length) {
    return true;
  }

  final savedIds = <String>{
    for (final slot in savedLayout) ...?slot?.children,
    for (final slot in savedLayout) ?slot?.id,
  };
  if (savedIds.contains('widget:frame-time') ||
      savedIds.contains('widget:battery-discharge')) {
    return true;
  }

  final currentAppIds = <String>{
    for (final app in apps) 'app:${app.id}',
    for (final app in localApps) 'local:${app.id}',
  };
  if (!savedIds.containsAll(currentAppIds)) {
    return true;
  }

  return savedIds
      .where((id) => id.startsWith('app:') || id.startsWith('local:'))
      .any((id) => !currentAppIds.contains(id));
}

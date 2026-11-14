import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../config/startup_environment.dart';
import '../launcher/runtime_paths.dart';
import '../settings/settings_controller.dart';
import '../theme/icon_theme_repository.dart';
import '../theme/icon_themes.dart';

/// The icon themes installed for this session.
final iconThemeRepositoryProvider = Provider<IconThemeRepository>((ref) {
  final environment = ref.watch(startupEnvironmentProvider).values;
  return IconThemeRepository(paths: RuntimePaths(environment: environment));
});

final iconThemeCatalogProvider =
    AsyncNotifierProvider<IconThemeCatalogController, List<ShellIconThemeData>>(
      IconThemeCatalogController.new,
    );

class IconThemeCatalogController
    extends AsyncNotifier<List<ShellIconThemeData>> {
  /// The icon pack Denial ships with, so a fresh install has real icons
  /// instead of the frozen-desktop default order.
  static const String bundledArchive =
      'packages/denial_flutter_sdk/assets/icon-themes/Colloid.tar.xz';

  @override
  Future<List<ShellIconThemeData>> build() async {
    final repository = ref.watch(iconThemeRepositoryProvider);
    await _installBundledTheme(repository);
    final themes = await repository.discover();
    // Denial's built-in theme and whatever the user imported; the system
    // themes in /usr/share/icons are not offered.
    return <ShellIconThemeData>[
      for (final theme in themes)
        if (theme.userInstalled || theme.id == defaultIconTheme) theme,
    ];
  }

  /// Unpacks [bundledArchive] when its theme is missing from disk.
  ///
  /// The built-in theme cannot be removed from the settings, but a fresh home
  /// directory still needs it; a lock keeps the shell and the settings app
  /// from unpacking it at the same time.
  Future<void> _installBundledTheme(IconThemeRepository repository) async {
    final directory = Directory(
      p.join(repository.paths.cacheHome, 'denial', 'icon-import'),
    );
    final installed = await repository.discover();
    if (installed.any((theme) => theme.id == defaultIconTheme)) {
      return;
    }
    await directory.create(recursive: true);
    final lock = File(p.join(directory.path, '.bundled-colloid.lock'));
    try {
      await lock.create(exclusive: true);
    } on FileSystemException {
      return;
    }
    try {
      final data = await rootBundle.load(bundledArchive);
      final archive = File(p.join(directory.path, 'Colloid.tar.xz'));
      await archive.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      try {
        await repository.install(archive.path);
      } finally {
        if (await archive.exists()) {
          await archive.delete();
        }
      }
    } on Object {
      // A failed unpack must not take the shell's icons with it; the next
      // launch tries again.
    } finally {
      if (await lock.exists()) {
        await lock.delete();
      }
    }
  }

  /// Reads the icon directories again, for a theme installed while the shell
  /// is running.
  Future<void> refresh() async {
    state = AsyncData(
      await ref.read(iconThemeRepositoryProvider).discover(),
    );
  }

  /// Installs every theme in [archivePath] and returns the new themes.
  Future<List<ShellIconThemeData>> importArchive(String archivePath) async {
    final repository = ref.read(iconThemeRepositoryProvider);
    final installed = await repository.install(archivePath);
    state = AsyncData(await repository.discover());
    return installed;
  }

  Future<void> remove(ShellIconThemeData theme) async {
    final repository = ref.read(iconThemeRepositoryProvider);
    await repository.remove(theme);
    state = AsyncData(await repository.discover());
  }
}

final availableShellIconThemesProvider = Provider<List<ShellIconThemeData>>(
  (ref) => ref.watch(iconThemeCatalogProvider).asData?.value ?? const [],
);

/// The icon theme the shell draws from.
///
/// The chosen theme wins; with no choice the shell keeps Denial's own default
/// theme when it is installed. A theme that is not installed simply resolves
/// to nothing, and the icon search falls back to the default order.
final resolvedShellIconThemeProvider = Provider<String>((ref) {
  final chosen = ref
      .watch(
        shellSettingsProvider.select(
          (settings) => settings.appearance.iconTheme,
        ),
      )
      .trim();
  return chosen.isNotEmpty ? chosen : defaultIconTheme;
});

/// The theme a fresh install shows; the user may replace it in Appearance.
const String defaultIconTheme = 'Colloid-Light';

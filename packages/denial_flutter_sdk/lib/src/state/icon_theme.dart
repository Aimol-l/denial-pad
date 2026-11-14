import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../config/startup_environment.dart';
import '../launcher/runtime_paths.dart';
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
  /// The icon pack Denial ships with and always uses.
  static const String bundledArchive =
      'packages/denial_flutter_sdk/assets/icon-themes/Colloid.tar.xz';

  @override
  Future<List<ShellIconThemeData>> build() async {
    final repository = ref.watch(iconThemeRepositoryProvider);
    await _ensureBundledTheme(repository);
    final themes = await repository.discover();
    // Denial has one icon set; system themes are not offered.
    return <ShellIconThemeData>[
      for (final theme in themes)
        if (theme.id == defaultIconTheme) theme,
    ];
  }

  /// Unpacks [bundledArchive] when its theme is missing from disk.
  ///
  /// The pack cannot be removed from the settings, but a half-finished copy
  /// (or a fresh home directory) still needs installing; a lock keeps the
  /// shell and the settings app from unpacking it at the same time.
  Future<void> _ensureBundledTheme(IconThemeRepository repository) async {
    final installed = await repository.discover();
    if (installed.any((theme) => theme.id == defaultIconTheme)) {
      return;
    }
    final directory = Directory(
      p.join(repository.paths.cacheHome, 'denial', 'icon-import'),
    );
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
      // A failed unpack leaves the fallback order in place; the next launch
      // tries again because nothing marks the pack as installed.
    } finally {
      if (await lock.exists()) {
        await lock.delete();
      }
    }
  }
}

final availableShellIconThemesProvider = Provider<List<ShellIconThemeData>>(
  (ref) => ref.watch(iconThemeCatalogProvider).asData?.value ?? const [],
);

/// The theme the shell draws from: Denial ships exactly one.
final resolvedShellIconThemeProvider = Provider<String>(
  (ref) => defaultIconTheme,
);

/// The theme Denial always uses; the settings page shows it and cannot
/// remove it.
const String defaultIconTheme = 'Colloid-Light';

import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  @override
  Future<List<ShellIconThemeData>> build() {
    return ref.watch(iconThemeRepositoryProvider).discover();
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

import 'package:flutter/foundation.dart' show Brightness;
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
}

final availableShellIconThemesProvider = Provider<List<ShellIconThemeData>>(
  (ref) => ref.watch(iconThemeCatalogProvider).asData?.value ?? const [],
);

/// The icon theme the shell draws from.
///
/// An explicit choice wins; otherwise the theme follows the scheme the shell
/// actually shows, so a light UI gets `Colloid-Light` and a dark one
/// `Colloid-Dark`. A theme that is not installed simply resolves to nothing,
/// and the icon search falls back to the default order.
final resolvedShellIconThemeProvider = Provider<String>((ref) {
  final appearance = ref.watch(
    shellSettingsProvider.select((settings) => settings.appearance),
  );
  final chosen = appearance.iconTheme.trim();
  if (chosen.isNotEmpty) {
    return chosen;
  }
  return appearance.effectiveBrightness == Brightness.light
      ? followSchemeLightIconTheme
      : followSchemeDarkIconTheme;
});

const String followSchemeLightIconTheme = 'Colloid-Light';
const String followSchemeDarkIconTheme = 'Colloid-Dark';

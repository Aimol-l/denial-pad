import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../local_apps/local_flutter_application.dart';
import '../launcher_providers.dart';
import '../local_app_desktop_entries.dart';
import '../models/home_grid_item.dart';
import 'home_grid_controller.dart';
import 'home_grid_layout.dart';

/// Built-in applications as regular desktop entries.
///
/// The entries are written once per launch (and only when their content
/// changed) so the all-apps list, `~/Desktop` shortcuts and external menus
/// can name a built-in app like any other.
final localAppDesktopEntriesProvider = FutureProvider<void>((ref) async {
  final paths = ref.watch(runtimePathsProvider);
  final apps = ref.watch(localFlutterApplicationRegistryProvider).applications;
  await ensureLocalAppDesktopEntries(paths, apps);
});

/// Every application Denial can launch: installed desktop entries plus the
/// built-in apps, once each and sorted by name.
final allApplicationsProvider = FutureProvider<List<HomeGridItem>>((ref) async {
  await ref.watch(localAppDesktopEntriesProvider.future);
  final repository = ref.watch(desktopAppsRepositoryProvider);
  final apps = await Isolate.run(
    repository.loadApplications,
    debugName: 'denial-all-applications',
  );
  final localApps = ref
      .watch(localFlutterApplicationRegistryProvider)
      .applications;
  return HomeGridLayout.catalogItems(apps, localApps);
});

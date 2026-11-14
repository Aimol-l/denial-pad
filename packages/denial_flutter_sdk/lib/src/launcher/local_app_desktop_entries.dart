import 'dart:io';

import 'package:path/path.dart' as p;

import '../local_apps/local_flutter_application.dart';
import 'runtime_paths.dart';

/// Writes a desktop entry for every built-in application.
///
/// Built-ins are widgets compiled into the shell, not executables, so the
/// entries exist to give them a stable id, name and category in the all-apps
/// catalog, in `~/Desktop` shortcuts and in external launchers. Denial maps
/// `X-Denial-Local-App` back to the in-process app instead of running [Exec].
Future<void> ensureLocalAppDesktopEntries(
  RuntimePaths paths,
  Iterable<LocalFlutterApplication> apps,
) async {
  final directory = Directory(p.join(paths.dataHome, 'applications'));
  try {
    await directory.create(recursive: true);
  } on FileSystemException {
    return;
  }
  for (final app in apps) {
    final file = File(p.join(directory.path, 'denial-${app.id}.desktop'));
    final categories = app.categories
        .map((category) => category.trim())
        .where((category) => category.isNotEmpty)
        .join(';');
    final content = StringBuffer()
      ..writeln('[Desktop Entry]')
      ..writeln('Type=Application')
      ..writeln('Name=${_singleLine(app.title)}')
      ..write(
        categories.isEmpty ? '' : 'Categories=$categories;\n',
      )
      ..writeln('Exec=denial-local-app ${app.id}')
      ..writeln('X-Denial-Local-App=${app.id}');
    try {
      if (await file.exists() && await file.readAsString() == '$content') {
        continue;
      }
      await file.writeAsString('$content');
    } on FileSystemException {
      continue;
    }
  }
}

String _singleLine(String value) =>
    value.replaceAll('\n', ' ').replaceAll('\r', ' ').trim();

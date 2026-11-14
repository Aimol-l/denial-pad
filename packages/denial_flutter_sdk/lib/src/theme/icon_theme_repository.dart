import 'dart:io';

import 'package:path/path.dart' as p;

import '../launcher/runtime_paths.dart';
import 'icon_themes.dart';

/// Finds the icon themes installed in the XDG data directories.
///
/// A theme is any `icons/<id>` directory with an `index.theme`; only the
/// label is read from it, because the shell resolves icon files by name in
/// precedence order rather than by the theme's size tables.
class IconThemeRepository {
  const IconThemeRepository({required this.paths});

  final RuntimePaths paths;

  Future<List<ShellIconThemeData>> discover() async {
    final seen = <String>{};
    final themes = <ShellIconThemeData>[];
    for (final root in paths.iconRoots()) {
      final directory = Directory(p.join(root, 'icons'));
      final List<FileSystemEntity> entries;
      try {
        if (!await directory.exists()) {
          continue;
        }
        entries = await directory.list(followLinks: false).toList();
      } on FileSystemException {
        continue;
      }
      for (final entity in entries) {
        if (entity is! Directory) {
          continue;
        }
        final id = p.basename(entity.path);
        if (id.startsWith('.') || !seen.add(id)) {
          continue;
        }
        final manifest = File(p.join(entity.path, 'index.theme'));
        final label = await _themeName(manifest);
        if (label == null) {
          continue;
        }
        themes.add(
          ShellIconThemeData(id: id, name: label, path: entity.path),
        );
      }
    }
    themes.sort((first, second) {
      final byName = first.name.toLowerCase().compareTo(
        second.name.toLowerCase(),
      );
      return byName != 0 ? byName : first.id.compareTo(second.id);
    });
    return List.unmodifiable(themes);
  }

  /// The `Name` of the `[Icon Theme]` section, or null when [manifest] is not
  /// an icon theme (or cannot be read).
  static Future<String?> _themeName(File manifest) async {
    final List<String> lines;
    try {
      if (!await manifest.exists()) {
        return null;
      }
      lines = await manifest.readAsLines();
    } on FileSystemException {
      return null;
    }
    var inIconTheme = false;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        continue;
      }
      if (trimmed.startsWith('[')) {
        inIconTheme = trimmed.toLowerCase() == '[icon theme]';
        continue;
      }
      if (!inIconTheme) {
        continue;
      }
      final separator = trimmed.indexOf('=');
      if (separator <= 0) {
        continue;
      }
      final key = trimmed.substring(0, separator).trim();
      if (key != 'Name') {
        continue;
      }
      final name = trimmed.substring(separator + 1).trim();
      if (name.isEmpty ||
          name.length > 128 ||
          name.runes.any((rune) => rune < 0x20 || rune == 0x7f)) {
        return null;
      }
      return name;
    }
    return null;
  }
}

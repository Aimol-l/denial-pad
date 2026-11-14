import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../launcher/runtime_paths.dart';
import 'icon_themes.dart';

/// Finds, installs and removes the icon themes in the XDG data directories.
///
/// A theme is any `icons/<id>` directory with an `index.theme`; the shell
/// resolves icon files by name in precedence order rather than by the theme's
/// size tables, so only the label and a handful of sample icons are read.
class IconThemeRepository {
  const IconThemeRepository({required this.paths});

  final RuntimePaths paths;

  /// Icons KDE shows in its own picker, in the same order.
  static const List<String> previewNames = <String>[
    'multimedia-player',
    'folder',
    'text-x-generic',
    'user-trash',
    'help-browser',
    'preferences-system',
  ];

  static const List<String> _previewContexts = <String>[
    'apps',
    'places',
    'devices',
    'mimetypes',
    'actions',
    'categories',
  ];

  static const List<String> _previewSizes = <String>[
    'scalable',
    '256',
    '128',
    '96',
    '64',
    '48',
    '32',
    '24',
    '22',
    '16',
  ];

  static const int _maximumArchiveBytes = 512 * 1024 * 1024;
  static const int _maximumThemeDepth = 3;

  Future<List<ShellIconThemeData>> discover() async {
    final seen = <String>{};
    final themes = <ShellIconThemeData>[];
    final userRoot = p.join(paths.dataHome, 'icons');
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
        if (id.startsWith('.') || id.endsWith('.bak') || !seen.add(id)) {
          continue;
        }
        final label = await _themeName(
          File(p.join(entity.path, 'index.theme')),
        );
        if (label == null) {
          continue;
        }
        themes.add(
          ShellIconThemeData(
            id: id,
            name: label,
            path: entity.path,
            previews: _previews(entity.path),
            userInstalled: p.equals(entity.path, p.join(userRoot, id)),
          ),
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

  /// Unpacks [archivePath] and installs every icon theme it contains.
  ///
  /// The archive is read in a private cache directory and validated before
  /// anything reaches the user's icons folder; a theme whose id already
  /// exists is moved aside as `<id>.bak` first.
  Future<List<ShellIconThemeData>> install(String archivePath) async {
    final archive = File(archivePath);
    final type = await FileSystemEntity.type(archivePath, followLinks: false);
    if (type != FileSystemEntityType.file) {
      throw const IconThemeException(
        'missing',
        'Choose a regular icon theme archive.',
      );
    }
    final length = await archive.length();
    if (length <= 0) {
      throw const IconThemeException('empty', 'The archive is empty.');
    }
    if (length > _maximumArchiveBytes) {
      throw const IconThemeException(
        'too-large',
        'The archive is larger than 512 MB.',
      );
    }

    final cache = Directory(p.join(paths.cacheHome, 'denial', 'icon-import'));
    await cache.create(recursive: true);
    final work = await cache.createTemp('import-');
    try {
      await _extract(archive, work);
      final candidates = await _themeDirectories(work);
      if (candidates.isEmpty) {
        throw const IconThemeException(
          'no-theme',
          'The archive contains no icon theme (no index.theme).',
        );
      }
      final iconsRoot = Directory(p.join(paths.dataHome, 'icons'));
      await iconsRoot.create(recursive: true);
      final installed = <ShellIconThemeData>[];
      for (final directory in candidates) {
        final id = p.basename(directory.path);
        if (id.isEmpty || id.startsWith('.')) {
          continue;
        }
        final label = await _themeName(
          File(p.join(directory.path, 'index.theme')),
        );
        if (label == null) {
          continue;
        }
        final target = Directory(p.join(iconsRoot.path, id));
        if (await target.exists()) {
          // Keep the replaced theme out of the picker: a hidden backup
          // directory, not a sibling that discovery would list.
          final backups = Directory(p.join(iconsRoot.path, '.backup'));
          await backups.create(recursive: true);
          final backup = p.join(
            backups.path,
            '$id-${DateTime.now().millisecondsSinceEpoch}',
          );
          await target.rename(backup);
        }
        Directory moved;
        try {
          moved = await directory.rename(target.path);
        } on FileSystemException {
          await _copyDirectory(directory, target);
          moved = target;
        }
        installed.add(
          ShellIconThemeData(
            id: id,
            name: label,
            path: moved.path,
            previews: _previews(moved.path),
            userInstalled: true,
          ),
        );
      }
      if (installed.isEmpty) {
        throw const IconThemeException(
          'no-theme',
          'The archive contains no icon theme (no index.theme).',
        );
      }
      return List.unmodifiable(installed);
    } finally {
      if (await work.exists()) {
        await work.delete(recursive: true);
      }
    }
  }

  /// Removes a theme this user installed; system themes are read-only.
  Future<void> remove(ShellIconThemeData theme) async {
    final root = p.join(paths.dataHome, 'icons');
    if (!p.isWithin(root, theme.path)) {
      throw const IconThemeException(
        'system',
        'Bundled icon themes cannot be removed.',
      );
    }
    final directory = Directory(theme.path);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  Future<void> _extract(File archive, Directory into) async {
    final lower = archive.path.toLowerCase();
    final bool zip;
    final ProcessResult listing;
    if (lower.endsWith('.zip')) {
      zip = true;
      listing = await Process.run('unzip', <String>['-Z1', archive.path]);
    } else if (lower.endsWith('.tar.xz') ||
        lower.endsWith('.tar.gz') ||
        lower.endsWith('.tgz') ||
        lower.endsWith('.tar')) {
      zip = false;
      listing = await Process.run('tar', <String>['-tf', archive.path]);
    } else {
      throw const IconThemeException(
        'unsupported',
        'Use a .tar.xz, .tar.gz or .zip archive.',
      );
    }
    if (listing.exitCode != 0) {
      throw IconThemeException(
        'extract',
        'Could not read the archive: ${_firstLine(listing.stderr)}',
      );
    }
    _rejectEscapingEntries('${listing.stdout}');
    final ProcessResult extraction = zip
        ? await Process.run('unzip', <String>[
            '-q',
            '-o',
            archive.path,
            '-d',
            into.path,
          ])
        : await Process.run('tar', <String>[
            '-xf',
            archive.path,
            '-C',
            into.path,
          ]);
    if (extraction.exitCode != 0) {
      throw IconThemeException(
        'extract',
        'Could not unpack the archive: ${_firstLine(extraction.stderr)}',
      );
    }
  }

  /// Refuses archives that would write outside the extraction directory.
  static void _rejectEscapingEntries(String listing) {
    for (final entry in const LineSplitter().convert(listing)) {
      if (entry.isEmpty) {
        continue;
      }
      if (entry.startsWith('/') || entry.split('/').contains('..')) {
        throw const IconThemeException(
          'unsafe',
          'The archive contains paths outside its own folder.',
        );
      }
    }
  }

  static Future<List<Directory>> _themeDirectories(Directory root) async {
    final found = <Directory>[];
    Future<void> walk(Directory directory, int depth) async {
      if (depth > _maximumThemeDepth) {
        return;
      }
      if (await File(p.join(directory.path, 'index.theme')).exists()) {
        found.add(directory);
        return;
      }
      final List<FileSystemEntity> entries;
      try {
        entries = await directory.list(followLinks: false).toList();
      } on FileSystemException {
        return;
      }
      for (final entity in entries) {
        if (entity is Directory) {
          await walk(entity, depth + 1);
        }
      }
    }

    await walk(root, 0);
    return found;
  }

  static Future<void> _copyDirectory(Directory source, Directory target) async {
    await target.create(recursive: true);
    await for (final entity in source.list(
      recursive: true,
      followLinks: false,
    )) {
      final relative = p.relative(entity.path, from: source.path);
      final destination = p.join(target.path, relative);
      if (entity is Directory) {
        await Directory(destination).create(recursive: true);
      } else if (entity is File) {
        await entity.copy(destination);
      }
    }
  }

  /// The sample icons for [themePath], by name, in [previewNames] order.
  ///
  /// The size axis is searched before the context axis so a scalable icon
  /// wins over a 16px one from another folder.
  static List<String> _previews(String themePath) {
    final found = <String, String>{};
    for (final size in _previewSizes) {
      for (final context in _previewContexts) {
        // Both layouts are in the wild: Colloid writes context/size, Adwaita
        // size/context.
        for (final directory in <String>[
          '$themePath/$context/$size',
          '$themePath/$size/$context',
        ]) {
          for (final name in previewNames) {
            if (found.containsKey(name)) {
              continue;
            }
            for (final extension in const <String>['svg', 'png']) {
              final file = File('$directory/$name.$extension');
              if (file.existsSync()) {
                found[name] = file.path;
                break;
              }
            }
          }
        }
        if (found.length == previewNames.length) {
          return <String>[for (final name in previewNames) found[name]!];
        }
      }
    }
    return <String>[for (final name in previewNames) ?found[name]];
  }

  static String _firstLine(Object? value) {
    final text = '${value ?? ''}'.trim();
    if (text.isEmpty) {
      return 'unknown error';
    }
    final newline = text.indexOf('\n');
    return newline < 0 ? text : text.substring(0, newline);
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

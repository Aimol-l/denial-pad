import 'package:flutter/foundation.dart';

/// An icon theme installed under one of the XDG data directories.
///
/// [id] is the theme's directory name, which is what freedesktop tools call
/// the theme; [name] is the human label from its `index.theme`.
@immutable
class ShellIconThemeData {
  const ShellIconThemeData({
    required this.id,
    required this.name,
    required this.path,
  });

  final String id;
  final String name;
  final String path;

  @override
  bool operator ==(Object other) {
    return other is ShellIconThemeData &&
        other.id == id &&
        other.name == name &&
        other.path == path;
  }

  @override
  int get hashCode => Object.hash(id, name, path);

  @override
  String toString() => 'ShellIconThemeData($id, $name, $path)';
}

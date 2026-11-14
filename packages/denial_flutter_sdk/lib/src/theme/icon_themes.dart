import 'package:flutter/foundation.dart';

/// An icon theme installed under one of the XDG data directories.
///
/// [id] is the theme's directory name, which is what freedesktop tools call
/// the theme; [name] is the human label from its `index.theme`. [previews]
/// are resolved sample icons for the picker, and [userInstalled] marks themes
/// this user added (and may remove) rather than ones the system ships.
@immutable
class ShellIconThemeData {
  const ShellIconThemeData({
    required this.id,
    required this.name,
    required this.path,
    this.previews = const <String>[],
    this.userInstalled = false,
  });

  final String id;
  final String name;
  final String path;
  final List<String> previews;
  final bool userInstalled;

  @override
  bool operator ==(Object other) {
    return other is ShellIconThemeData &&
        other.id == id &&
        other.name == name &&
        other.path == path &&
        other.userInstalled == userInstalled &&
        listEquals(other.previews, previews);
  }

  @override
  int get hashCode =>
      Object.hash(id, name, path, userInstalled, Object.hashAll(previews));

  @override
  String toString() => 'ShellIconThemeData($id, $name, $path)';
}

/// A failed theme install or removal, with a stable code the UI can translate.
class IconThemeException implements Exception {
  const IconThemeException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'IconThemeException($code, $message)';
}

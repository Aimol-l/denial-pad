import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Where a client's surface lands inside the rectangle the shell gives it.
///
/// Two things that cannot see each other must agree on this mapping: the
/// window texture the shell paints, and the native input route that tells the
/// compositor which client pixel a touch means. A lone app covers the screen;
/// a split pane shows the whole window with `contain`, so both sides resolve
/// their geometry here instead of each keeping its own copy of the maths.
@immutable
class WindowSurfaceFit {
  const WindowSurfaceFit({
    required this.scale,
    required this.frame,
    required this.content,
    required this.surfaceRect,
    required this.contentRect,
  });

  /// Fits the client surface, given in client coordinates, into [area].
  ///
  /// The surface sits at the top of the area, horizontally centred, exactly
  /// like the texture the shell paints. [topOffset] lifts the surface, for a
  /// scene the shell scrolls up behind the edge panel.
  factory WindowSurfaceFit.resolve({
    required Rect area,
    required Rect frame,
    required Rect content,
    required BoxFit fit,
    double topOffset = 0.0,
  }) {
    if (area.isEmpty || frame.isEmpty || content.isEmpty) {
      return WindowSurfaceFit(
        scale: 1,
        frame: frame,
        content: content,
        surfaceRect: Rect.zero,
        contentRect: Rect.zero,
      );
    }
    final widthScale = area.width / frame.width;
    final heightScale = area.height / frame.height;
    final scale = fit == BoxFit.contain
        ? math.min(widthScale, heightScale)
        : math.max(widthScale, heightScale);
    final left = area.left + (area.width - frame.width * scale) / 2.0;
    final top = area.top - topOffset;
    return WindowSurfaceFit(
      scale: scale,
      frame: frame,
      content: content,
      surfaceRect: Rect.fromLTWH(
        left,
        top,
        frame.width * scale,
        frame.height * scale,
      ),
      contentRect: Rect.fromLTWH(
        left + (content.left - frame.left) * scale,
        top + (content.top - frame.top) * scale,
        content.width * scale,
        content.height * scale,
      ),
    );
  }

  /// Screen pixels per client pixel.
  final double scale;

  /// The client surface as the compositor describes it, in client coordinates.
  final Rect frame;

  /// The client content inside [frame], in client coordinates.
  final Rect content;

  /// [frame] on screen.
  final Rect surfaceRect;

  /// [content] on screen.
  final Rect contentRect;

  bool get isEmpty => surfaceRect.isEmpty || contentRect.isEmpty;

  /// An on-screen rectangle in client coordinates, as the input route sends it
  /// to the compositor.
  Rect screenToSource(Rect onScreen) {
    if (isEmpty) return Rect.zero;
    return Rect.fromLTWH(
      content.left + (onScreen.left - contentRect.left) / scale,
      content.top + (onScreen.top - contentRect.top) / scale,
      onScreen.width / scale,
      onScreen.height / scale,
    );
  }
}

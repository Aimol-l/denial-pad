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
    required this.scaleX,
    required this.scaleY,
    required this.fit,
    required this.frame,
    required this.content,
    required this.surfaceRect,
    required this.contentRect,
  });

  /// Fits the client surface, given in client coordinates, into [area].
  ///
  /// The surface is horizontally centred, exactly like the texture the shell
  /// paints: a covering surface starts at the top, a contained one sits in the
  /// middle of its area with the spare space split around it. [topOffset]
  /// lifts the surface, for a scene the shell scrolls up behind the edge
  /// panel.
  factory WindowSurfaceFit.resolve({
    required Rect area,
    required Rect frame,
    required Rect content,
    required BoxFit fit,
    double topOffset = 0.0,
  }) {
    if (area.isEmpty || frame.isEmpty || content.isEmpty) {
      return WindowSurfaceFit(
        scaleX: 1,
        scaleY: 1,
        fit: fit,
        frame: frame,
        content: content,
        surfaceRect: Rect.zero,
        contentRect: Rect.zero,
      );
    }
    final widthScale = area.width / frame.width;
    final heightScale = area.height / frame.height;
    final contained = fit == BoxFit.contain;
    // A pane a few pixels shorter than its window would otherwise leave a
    // thin gap on both sides. That difference is under a tenth of the size,
    // so stretching it is invisible and the window still fills the pane.
    final stretches = contained && _closeScales(widthScale, heightScale);
    final scaleX = stretches
        ? widthScale
        : (contained
              ? math.min(widthScale, heightScale)
              : math.max(widthScale, heightScale));
    final scaleY = stretches ? heightScale : scaleX;
    final left = area.left + (area.width - frame.width * scaleX) / 2.0;
    // A contained window is a whole-window view: the spare space splits
    // evenly around it instead of hanging every pixel off the bottom.
    final spareHeight = area.height - frame.height * scaleY;
    final top =
        area.top +
        (contained && !stretches ? spareHeight / 2.0 : 0.0) -
        topOffset;
    return WindowSurfaceFit(
      scaleX: scaleX,
      scaleY: scaleY,
      fit: fit,
      frame: frame,
      content: content,
      surfaceRect: Rect.fromLTWH(
        left,
        top,
        frame.width * scaleX,
        frame.height * scaleY,
      ),
      contentRect: Rect.fromLTWH(
        left + (content.left - frame.left) * scaleX,
        top + (content.top - frame.top) * scaleY,
        content.width * scaleX,
        content.height * scaleY,
      ),
    );
  }

  /// Two scales are close enough that stretching beats cropping or a gap.
  static bool _closeScales(double first, double second) {
    final largest = math.max(first, second);
    if (largest <= 0) return false;
    return (first - second).abs() / largest < 0.08;
  }

  /// Screen pixels per client pixel, horizontally.
  final double scaleX;

  /// Screen pixels per client pixel, vertically.
  final double scaleY;

  /// How the surface fills the area it was given.
  final BoxFit fit;

  /// The client surface as the compositor describes it, in client coordinates.
  final Rect frame;

  /// The client content inside [frame], in client coordinates.
  final Rect content;

  /// [frame] on screen.
  final Rect surfaceRect;

  /// [content] on screen.
  final Rect contentRect;

  bool get isEmpty => surfaceRect.isEmpty || contentRect.isEmpty;

  /// How the surface sits in its area when the fit leaves spare space: a
  /// contained window is centred, a covering one starts at the top.
  Alignment get alignment => alignmentFor(fit);

  /// The alignment any widget that fits its own child must use, so the paint
  /// and the input route cannot pick different ones.
  static Alignment alignmentFor(BoxFit fit) =>
      fit == BoxFit.contain ? Alignment.center : Alignment.topCenter;

  /// An on-screen rectangle in client coordinates, as the input route sends it
  /// to the compositor.
  Rect screenToSource(Rect onScreen) {
    if (isEmpty) return Rect.zero;
    return Rect.fromLTWH(
      content.left + (onScreen.left - contentRect.left) / scaleX,
      content.top + (onScreen.top - contentRect.top) / scaleY,
      onScreen.width / scaleX,
      onScreen.height / scaleY,
    );
  }
}

import 'package:flutter/widgets.dart';

import '../models/denial_window.dart';
import '../theme/glass_configuration.dart';
import '../theme/shell_theme.dart';

import 'window_backdrop_cache.dart';
import 'window_plane.dart';
import 'window_surface_fit.dart';
import 'window_surface_tree.dart';

/// Fills its parent with a compositor window, covering it like the mobile
/// stage does, through the same [WindowPlane] primitive as desktop windows.
///
/// The primitive draws the client image and its glass as one window surface.
/// A blur widget over a raw texture relies on the engine fusing the two.
/// Scaled or moving windows (recents, launch, focus zoom) defeat that fusion
/// and the fallback floods glass over the scene.
class WindowTextureRect extends StatelessWidget {
  const WindowTextureRect({
    super.key,
    required this.window,
    this.borderRadius = BorderRadius.zero,
    this.applyBackdrop = true,
    this.fit = BoxFit.cover,
  });

  final DenialWindow window;
  final BorderRadius borderRadius;
  final bool applyBackdrop;

  /// How the window fills its parent. Recents and the app stage cover it;
  /// a split card shows the whole window when the client kept a size of its
  /// own, which keeps its icons and window buttons on screen.
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    assert(
      !window.isLocalFlutter,
      'Local Flutter windows must be rendered through WindowContentRect.',
    );
    final theme = ShellTheme.of(context);
    final glass =
        applyBackdrop &&
        !window.isOpaque &&
        theme.backdropBlurEnabled &&
        (theme.transparencyMode == ShellTransparencyMode.glass ||
            theme.backdropBlurSigma > 0);
    final cache = glass ? WindowBackdropCache.maybeOf(context) : null;
    // The rectangle the shell fits: the surface, or the content inside it
    // when the compositor reports a strip (an Android system bar) that is not
    // part of the app. Fitting the content is what keeps that strip from
    // turning into a gap under the window.
    final fitRect = window.contentFitRect;
    final windowSize = fitRect.isEmpty
        ? Size(window.width.toDouble(), window.height.toDouble())
        : fitRect.size;
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final texture = window.popupSurfaceLayers.isEmpty
        ? _cropToFitRect(window, singleWindowPlaneTexture(window))
        : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final parent = constraints.biggest;
        if (windowSize.isEmpty || parent.isEmpty || !parent.isFinite) {
          return const SizedBox.shrink();
        }
        // The window keeps its aspect and sits at the top of the parent, like
        // the mobile stage. As on the desktop, the plane is laid out at its
        // on-screen size and maps the buffer itself: its material is resolved
        // in the plane's own units and must not sit under a buffer-to-screen
        // scale.
        final mapping = WindowSurfaceFit.resolve(
          area: Offset.zero & parent,
          frame: Offset.zero & windowSize,
          content: Offset.zero & windowSize,
          fit: fit,
        );
        final size = mapping.surfaceRect.size;
        final radius = borderRadius.topLeft.x;
        final backdrop = glass && cache == null
            ? theme.backdropFilterConfigAt(
                1,
                borderRadius: BorderRadius.circular(radius),
                // The mobile stage frosts the whole window, including fully
                // transparent pixels, like the shell's own glass panels.
              )
            : null;
        final Widget plane = texture != null
            ? WindowPlane.texture(
                texture: texture,
                radius: radius,
                backdrop: backdrop,
                filterQuality: FilterQuality.low,
                presentationScale: devicePixelRatio,
              )
            : WindowPlane.child(
                radius: radius,
                backdrop: backdrop,
                child: WindowSurfaceTree(
                  window: window,
                  includePopups: true,
                  filterQuality: FilterQuality.low,
                ),
              );
        Widget covered = OverflowBox(
          alignment: mapping.alignment,
          minWidth: size.width,
          maxWidth: size.width,
          minHeight: size.height,
          maxHeight: size.height,
          child: plane,
        );
        if (cache != null) {
          // A precomputed backdrop replaces the live glass under the plane.
          covered = Stack(
            fit: StackFit.expand,
            children: [
              WindowBackdropSlice(
                cache: cache,
                borderRadius: BorderRadius.circular(radius),
                glass: theme.windowGlassShading,
              ),
              covered,
            ],
          );
        }
        // The plane rounds its own corners. Clip only a window whose aspect
        // differs from the parent's and therefore overflows it.
        if (size.width <= parent.width + 0.5 &&
            size.height <= parent.height + 0.5) {
          return covered;
        }
        return borderRadius == BorderRadius.zero
            ? ClipRect(child: covered)
            : ClipRRect(borderRadius: borderRadius, child: covered);
      },
    );
  }
}

/// Cuts a full-surface texture down to the rectangle the shell fits, so the
/// strip outside the client content is not painted as a gap.
WindowPlaneTexture? _cropToFitRect(
  DenialWindow window,
  WindowPlaneTexture? texture,
) {
  if (texture == null || !texture.isValid) return texture;
  final frame = window.presentationCoordinateRect;
  final fit = window.contentFitRect;
  if (frame.isEmpty || fit.isEmpty || fit == frame) return texture;
  // Only a texture that covers its plane can be cropped; a layer offset
  // would otherwise be applied twice.
  final destination = texture.destination;
  if (destination.left != 0 ||
      destination.top != 0 ||
      destination.width != 1 ||
      destination.height != 1) {
    return texture;
  }
  final source = texture.source;
  final scaleX = source.width / frame.width;
  final scaleY = source.height / frame.height;
  return WindowPlaneTexture(
    id: texture.id,
    bufferSize: texture.bufferSize,
    source: Rect.fromLTWH(
      source.left + (fit.left - frame.left) * scaleX,
      source.top + (fit.top - frame.top) * scaleY,
      fit.width * scaleX,
      fit.height * scaleY,
    ),
    transform: texture.transform,
    opacity: texture.opacity,
  );
}

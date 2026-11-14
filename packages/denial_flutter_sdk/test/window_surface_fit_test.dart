import 'package:denial_flutter_sdk/src/widgets/window_surface_fit.dart';
import 'package:flutter/widgets.dart';
import 'package:test/test.dart';

void main() {
  // A split pane on the tablet's 1600x1000 screen holding the status bar:
  // 800x955 per pane.
  const pane = Rect.fromLTWH(0, 0, 800, 955);
  // A landscape client that kept its own size instead of the pane's.
  const landscape = Rect.fromLTWH(0, 0, 1600, 1000);

  test('a pane shows the whole window, top-centred', () {
    final fit = WindowSurfaceFit.resolve(
      area: pane,
      frame: landscape,
      content: landscape,
      fit: BoxFit.contain,
    );
    expect(fit.scale, 0.5);
    expect(fit.surfaceRect, const Rect.fromLTWH(0, 0, 800, 500));
    expect(fit.contentRect, fit.surfaceRect);
  });

  test('covering the pane crops the same window at the same top edge', () {
    final fit = WindowSurfaceFit.resolve(
      area: pane,
      frame: landscape,
      content: landscape,
      fit: BoxFit.cover,
    );
    expect(fit.scale, closeTo(0.955, 1e-6));
    expect(fit.surfaceRect.top, 0);
    expect(fit.surfaceRect.width, closeTo(1528, 0.01));
    expect(fit.surfaceRect.left, closeTo(-364, 0.01));
  });

  test('a touch in a pane means the pixel the person sees', () {
    final fit = WindowSurfaceFit.resolve(
      area: pane,
      frame: landscape,
      content: landscape,
      fit: BoxFit.contain,
    );
    // The middle of the painted window maps to the middle of the client.
    expect(
      fit.screenToSource(const Rect.fromLTWH(400, 250, 10, 10)),
      const Rect.fromLTWH(800, 500, 20, 20),
    );
    // The bottom row of the pane is blank wallpaper now: input there must not
    // reach the client's bottom row.
    final belowWindow = fit.screenToSource(const Rect.fromLTWH(400, 700, 10, 10));
    expect(belowWindow.top, greaterThan(1000));
  });

  test('a portrait window in a wider pane is centred horizontally', () {
    const portrait = Rect.fromLTWH(0, 0, 800, 1600);
    final fit = WindowSurfaceFit.resolve(
      area: pane,
      frame: portrait,
      content: portrait,
      fit: BoxFit.contain,
    );
    expect(fit.scale, closeTo(0.596875, 1e-6));
    expect(fit.surfaceRect.height, closeTo(955, 0.01));
    expect(fit.surfaceRect.center.dx, closeTo(pane.center.dx, 0.01));
    expect(fit.surfaceRect.left, greaterThan(pane.left));
  });

  test('content offset inside the frame maps with the surface', () {
    // A toplevel with a 40px client-side strip above its content.
    const frame = Rect.fromLTWH(100, 40, 1600, 1000);
    const content = Rect.fromLTWH(100, 80, 1600, 960);
    final fit = WindowSurfaceFit.resolve(
      area: pane,
      frame: frame,
      content: content,
      fit: BoxFit.contain,
    );
    expect(fit.scale, 0.5);
    expect(fit.contentRect, const Rect.fromLTWH(0, 20, 800, 480));
    expect(
      fit.screenToSource(const Rect.fromLTWH(0, 20, 800, 480)),
      content,
    );
  });

  test('an empty frame maps nothing', () {
    final fit = WindowSurfaceFit.resolve(
      area: pane,
      frame: Rect.zero,
      content: Rect.zero,
      fit: BoxFit.contain,
    );
    expect(fit.isEmpty, isTrue);
    expect(fit.screenToSource(const Rect.fromLTWH(0, 0, 10, 10)), Rect.zero);
  });
}

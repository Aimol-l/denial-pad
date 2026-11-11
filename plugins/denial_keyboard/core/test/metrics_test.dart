import 'package:denial_keyboard_core/denial_keyboard_core.dart';
import 'package:test/test.dart';

const screen = (width: 1707.0, height: 1067.0);

void main() {
  test('panel size is clamped to 40-80% width and 25-45% height', () {
    final tooBig = clampPanelSize(screen, (width: 5000.0, height: 5000.0));
    final tooSmall = clampPanelSize(screen, (width: 10.0, height: 10.0));
    expect(tooBig.width, closeTo(1365.6, 0.01));
    expect(tooBig.height, closeTo(480.15, 0.01));
    expect(tooSmall.width, closeTo(682.8, 0.01));
    expect(tooSmall.height, closeTo(266.75, 0.01));
  });

  test('font stays within 11 and 22 at both extremes', () {
    final min = keyboardMetrics(panelWidth: 682.8, panelHeight: 266.75);
    final max = keyboardMetrics(panelWidth: 1365.6, panelHeight: 480.15);
    expect(min.fontSize, greaterThanOrEqualTo(11));
    expect(max.fontSize, lessThanOrEqualTo(22));
    expect(min.fontSize, lessThanOrEqualTo(max.fontSize));
  });

  test('four rows always fit the panel', () {
    for (final panel in [(682.8, 266.75), (990.0, 320.0), (1365.6, 480.15)]) {
      final m = keyboardMetrics(panelWidth: panel.$1, panelHeight: panel.$2);
      expect(m.rowHeight * 4 + headerHeight, lessThanOrEqualTo(panel.$2));
    }
  });

  test('position keeps 48 logical pixels on screen', () {
    const panel = (width: 990.0, height: 320.0);
    final p = clampPanelPosition(screen, panel, (x: -2000.0, y: 5000.0));
    expect(p.x, greaterThanOrEqualTo(-panel.width + 48));
    expect(p.y, lessThanOrEqualTo(screen.height - 48));
  });

  test('release near an edge snaps to it', () {
    const panel = (width: 990.0, height: 320.0);
    expect(snapPanelPosition(screen, panel, (x: 4.0, y: 900.0)),
        (x: 0.0, y: 747.0));
    expect(snapPanelPosition(screen, panel, (x: 700.0, y: 740.0)),
        (x: 717.0, y: 747.0));
    expect(snapPanelPosition(screen, panel, (x: 400.0, y: 400.0)),
        (x: 400.0, y: 400.0));
  });
}

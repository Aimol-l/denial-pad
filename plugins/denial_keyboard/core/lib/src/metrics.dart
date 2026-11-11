/// Fraction of the screen the panel may occupy.
const double minPanelWidthRatio = 0.40;
const double maxPanelWidthRatio = 0.80;
const double minPanelHeightRatio = 0.25;
const double maxPanelHeightRatio = 0.45;

/// Fixed height of the header block: the toolbar while idle, the preedit and
/// candidate lines while typing.
const double headerHeight = 64;

/// Height of the candidate line alone.
const double candidateStripHeight = 34;

const double panelPadding = 12;
const double rowGap = 6;
const int letterColumns = 10;

class KeyboardMetrics {
  const KeyboardMetrics({
    required this.panelWidth,
    required this.panelHeight,
    required this.keyWidth,
    required this.rowHeight,
    required this.fontSize,
    required this.keyRadius,
  });

  final double panelWidth;
  final double panelHeight;
  final double keyWidth;
  final double rowHeight;
  final double fontSize;
  final double keyRadius;
}

/// Derives key geometry from the panel size.
///
/// The row height is capped by the width so keys never become taller than they
/// are wide, and by the available height so four rows always fit.
KeyboardMetrics keyboardMetrics({
  required double panelWidth,
  required double panelHeight,
  int rows = 4,
}) {
  final keyWidth =
      (panelWidth - panelPadding * 2 - rowGap * (letterColumns - 1)) /
          letterColumns;
  final available =
      panelHeight - headerHeight - panelPadding * 2 - rowGap * (rows - 1);
  final rowHeight = available / rows < keyWidth * 0.92
      ? available / rows
      : keyWidth * 0.92;
  final fontSize = (rowHeight * 0.42).clamp(11.0, 22.0);
  return KeyboardMetrics(
    panelWidth: panelWidth,
    panelHeight: panelHeight,
    keyWidth: keyWidth,
    rowHeight: rowHeight,
    fontSize: fontSize,
    keyRadius: rowHeight * 0.18,
  );
}

/// Clamps a requested panel size to the supported range.
({double width, double height}) clampPanelSize(
  ({double width, double height}) screen,
  ({double width, double height}) requested,
) {
  return (
    width: requested.width.clamp(
      screen.width * minPanelWidthRatio,
      screen.width * maxPanelWidthRatio,
    ),
    height: requested.height.clamp(
      screen.height * minPanelHeightRatio,
      screen.height * maxPanelHeightRatio,
    ),
  );
}

/// Keeps at least 48 logical pixels of the panel on screen.
({double x, double y}) clampPanelPosition(
  ({double width, double height}) screen,
  ({double width, double height}) panel,
  ({double x, double y}) requested,
) {
  const margin = 48.0;
  return (
    x: requested.x.clamp(-panel.width + margin, screen.width - margin),
    y: requested.y.clamp(-panel.height + margin, screen.height - margin),
  );
}

/// Snaps a panel position to an edge when it is released close to one.
({double x, double y}) snapPanelPosition(
  ({double width, double height}) screen,
  ({double width, double height}) panel,
  ({double x, double y}) position, {
  double threshold = 24,
}) {
  var x = position.x;
  var y = position.y;
  if (x < threshold) x = 0;
  if (x + panel.width > screen.width - threshold) {
    x = screen.width - panel.width;
  }
  if (y < threshold) y = 0;
  if (y + panel.height > screen.height - threshold) {
    y = screen.height - panel.height;
  }
  return (x: x, y: y);
}

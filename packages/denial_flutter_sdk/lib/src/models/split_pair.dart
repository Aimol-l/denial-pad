import 'dart:math' as math;

/// Which pane of a split pair receives input.
enum SplitSide { first, second }

/// The closest a divider may bring a pane to the screen edge.
const double splitMinFraction = 0.2;

/// The furthest a divider may push a pane.
const double splitMaxFraction = 0.8;

/// A divider this close to the middle snaps to an even split.
const double splitSnapWindow = 0.03;

/// The share a split starts with.
const double splitDefaultFraction = 0.5;

/// One split pair: two windows, the axis they share, and the first pane's
/// share of the screen. The compositor owns the rectangles; this type owns the
/// ratio the divider drags and which pane is active.
class SplitPair {
  const SplitPair({
    required this.first,
    required this.second,
    required this.vertical,
    this.ratio = splitDefaultFraction,
    this.active = SplitSide.first,
  });

  /// The left (landscape) or top (portrait) window; zero while that side is
  /// still showing the picker, which happens when the app was dropped on the
  /// other side.
  final int first;

  /// The right or bottom window; zero while the picker is still open.
  final int second;
  final bool vertical;
  final double ratio;
  final SplitSide active;

  bool get isComplete => first > 0 && second > 0;

  bool contains(int windowId) =>
      (first > 0 && windowId == first) || (second > 0 && windowId == second);

  /// The window recents draws its card for: the left/top app, or the other
  /// app while the leading side is still empty.
  int get leadingWindow => first > 0 ? first : second;

  /// The app on the side that is not [leadingWindow]; zero when that side is
  /// still empty.
  int get otherWindow => first > 0 ? second : 0;

  SplitPair withRatio(double ratio) => SplitPair(
    first: first,
    second: second,
    vertical: vertical,
    ratio: ratio.clamp(splitMinFraction, splitMaxFraction),
    active: active,
  );

  SplitPair withActive(SplitSide side) => SplitPair(
    first: first,
    second: second,
    vertical: vertical,
    ratio: ratio,
    active: side,
  );

  /// Fills the side the picker still holds, keeping the ratio and the active
  /// side, so the app the person dropped does not move.
  SplitPair filled(int windowId) => first > 0
      ? SplitPair(
          first: first,
          second: windowId,
          vertical: vertical,
          ratio: ratio,
          active: active,
        )
      : SplitPair(
          first: windowId,
          second: second,
          vertical: vertical,
          ratio: ratio,
          active: active,
        );

  SplitPair swapped() => SplitPair(
    first: second,
    second: first,
    vertical: vertical,
    ratio: 1 - ratio,
    active: active == SplitSide.first ? SplitSide.second : SplitSide.first,
  );

  int get activeWindow => active == SplitSide.first ? first : second;
  int get inactiveWindow => active == SplitSide.first ? second : first;

  @override
  bool operator ==(Object other) =>
      other is SplitPair &&
      other.first == first &&
      other.second == second &&
      other.vertical == vertical &&
      other.ratio == ratio &&
      other.active == active;

  @override
  int get hashCode => Object.hash(first, second, vertical, ratio, active);
}

/// The two shares a divider at [ratio] produces, with the middle snap and the
/// draggable range applied.
({double first, double second}) splitFractions(double ratio) {
  final clamped = ratio.clamp(splitMinFraction, splitMaxFraction);
  // 47% and 53% are the advertised edges of the snap window; comparing the
  // exact doubles would miss them by one ulp.
  if ((clamped - 0.5).abs() <= splitSnapWindow + 1e-9) {
    return (first: 0.5, second: 0.5);
  }
  return (first: clamped, second: 1 - clamped);
}

/// A split pane in shell coordinates.
typedef SplitPaneRect = ({
  double left,
  double top,
  double width,
  double height,
});

/// The ratio interval that keeps both panes at or above their minimum size,
/// intersected with the draggable range. Null when no ratio can host both.
({double min, double max})? splitRatioBounds({
  required double extent,
  required double firstMin,
  required double secondMin,
  double minRatio = splitMinFraction,
  double maxRatio = splitMaxFraction,
}) {
  final span = extent <= 0 ? 1.0 : extent;
  final first = firstMin < 1 ? 1.0 : firstMin;
  final second = secondMin < 1 ? 1.0 : secondMin;
  if (first + second > span) return null;
  final low = (first / span).clamp(minRatio, maxRatio);
  final high = (1 - second / span).clamp(minRatio, maxRatio);
  return low <= high ? (min: low, max: high) : null;
}

/// Whether a split of [width] × [height] (status bar [topInset] tall) can host
/// both clients at their minimum size.
bool splitFits({
  required double width,
  required double height,
  required double topInset,
  required bool vertical,
  required double firstMinWidth,
  required double firstMinHeight,
  required double secondMinWidth,
  required double secondMinHeight,
}) {
  final extent = vertical ? height - topInset : width;
  return splitRatioBounds(
        extent: extent,
        firstMin: vertical ? firstMinHeight : firstMinWidth,
        secondMin: vertical ? secondMinHeight : secondMinWidth,
      ) !=
      null;
}

/// The window left after [closedWindowId] leaves [pair]; zero when neither.
int pairSurvivor(SplitPair pair, int closedWindowId) {
  if (closedWindowId == pair.first) return pair.second;
  if (closedWindowId == pair.second) return pair.first;
  return 0;
}

/// The first pane's share for a pointer at [position] along the split axis.
double splitRatioAt(
  double position, {
  required double extent,
  required ({double min, double max}) bounds,
}) {
  final span = extent <= 0 ? 1.0 : extent;
  return (position / span).clamp(bounds.min, bounds.max);
}

/// The two panes of [pair] inside a view whose status bar is [topInset] tall.
///
/// Mirrors the compositor's `split_rects`, so the shell draws each window at
/// exactly the rectangle the client was configured for: the two panes tile
/// the area below the status bar with nothing between them.
List<SplitPaneRect> splitPaneRects(
  double viewWidth,
  double viewHeight,
  SplitPair pair, {
  required double topInset,
}) {
  final width = math.max(1.0, viewWidth);
  final height = math.max(1.0, viewHeight - topInset);
  final originY = topInset;
  final fractions = splitFractions(pair.ratio);
  if (pair.vertical) {
    return [
      (left: 0, top: originY, width: width, height: height * fractions.first),
      (
        left: 0,
        top: originY + height * fractions.first,
        width: width,
        height: height * fractions.second,
      ),
    ];
  }
  return [
    (left: 0, top: originY, width: width * fractions.first, height: height),
    (
      left: width * fractions.first,
      top: originY,
      width: width * fractions.second,
      height: height,
    ),
  ];
}

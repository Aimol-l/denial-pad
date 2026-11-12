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

  /// The left (landscape) or top (portrait) window.
  final int first;

  /// The right or bottom window; zero while the picker is still open.
  final int second;
  final bool vertical;
  final double ratio;
  final SplitSide active;

  bool get isComplete => second > 0;

  bool contains(int windowId) =>
      windowId == first || (second > 0 && windowId == second);

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

  SplitPair withSecond(int windowId) => SplitPair(
    first: first,
    second: windowId,
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

/// A split card in shell coordinates.
typedef SplitPaneRect = ({
  double left,
  double top,
  double width,
  double height,
});

/// The margin each split card keeps from the screen edge.
const double splitCardMargin = 14;

/// The gap between the two split cards, where the divider floats.
const double splitCardGutter = 14;

/// The extra room below the status bar before the first card starts.
const double splitCardTopGap = 10;

/// The corner radius of a split card.
const double splitCardRadius = 20;

/// The two cards of [pair] inside a view whose status bar is [topInset] tall.
///
/// Mirrors the compositor's `split_rects`, so the shell draws each window at
/// exactly the rectangle the client was configured for.
List<SplitPaneRect> splitPaneRects(
  double viewWidth,
  double viewHeight,
  SplitPair pair, {
  required double topInset,
}) {
  final width = math.max(1.0, viewWidth - splitCardMargin * 2);
  final height = math.max(
    1.0,
    viewHeight - topInset - splitCardTopGap - splitCardMargin,
  );
  final originX = splitCardMargin;
  final originY = topInset + splitCardTopGap;
  final span = pair.vertical ? height : width;
  final gutter = math.min(splitCardGutter, math.max(0.0, span - 2));
  final firstExtent = (span - gutter) * splitFractions(pair.ratio).first;
  final secondExtent = math.max(0.0, span - gutter - firstExtent);
  if (pair.vertical) {
    return [
      (left: originX, top: originY, width: width, height: firstExtent),
      (
        left: originX,
        top: originY + firstExtent + gutter,
        width: width,
        height: secondExtent,
      ),
    ];
  }
  return [
    (left: originX, top: originY, width: firstExtent, height: height),
    (
      left: originX + firstExtent + gutter,
      top: originY,
      width: secondExtent,
      height: height,
    ),
  ];
}

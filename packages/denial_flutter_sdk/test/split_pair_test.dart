import 'package:denial_flutter_sdk/src/models/split_pair.dart';
import 'package:test/test.dart';

void main() {
  test('a ratio near the middle snaps to half and half', () {
    expect(splitFractions(0.5), (first: 0.5, second: 0.5));
    expect(splitFractions(0.48), (first: 0.5, second: 0.5));
    expect(splitFractions(0.47), (first: 0.5, second: 0.5));
    expect(splitFractions(0.44), (first: 0.44, second: 0.56));
  });

  test('a ratio outside the draggable range is clamped', () {
    expect(splitFractions(0.05).first, 0.2);
    expect(splitFractions(0.95).first, 0.8);
  });

  test('a pair keeps its axis and ratio when the ratio moves', () {
    const pair = SplitPair(
      first: 3,
      second: 5,
      vertical: true,
      ratio: 0.53,
      active: SplitSide.first,
    );
    final moved = pair.withRatio(0.7);
    expect(moved.vertical, isTrue);
    expect(moved.first, 3);
    expect(moved.second, 5);
    expect(moved.ratio, 0.7);
  });

  test('swapping trades the panes and the active side', () {
    const pair = SplitPair(
      first: 3,
      second: 5,
      vertical: false,
      ratio: 0.53,
      active: SplitSide.first,
    );
    final flipped = pair.swapped();
    expect(flipped.first, 5);
    expect(flipped.second, 3);
    expect(flipped.ratio, closeTo(0.47, 1e-9));
    expect(flipped.active, SplitSide.second);
  });

  test('an incomplete pair reports the pane still missing', () {
    const pair = SplitPair(first: 3, second: 0, vertical: false);
    expect(pair.isComplete, isFalse);
    expect(pair.filled(9).isComplete, isTrue);
  });

  test('landscape panes tile the screen below the status bar', () {
    const pair = SplitPair(first: 3, second: 5, vertical: false);
    final [left, right] = splitPaneRects(1600, 1000, pair, topInset: 45);
    expect(left, (left: 0.0, top: 45.0, width: 800.0, height: 955.0));
    expect(right, (left: 800.0, top: 45.0, width: 800.0, height: 955.0));
    expect(right.left, left.left + left.width);
    expect(right.left + right.width, 1600);
  });

  test('portrait panes tile the screen below the status bar', () {
    const pair = SplitPair(first: 3, second: 5, vertical: true);
    final [top, bottom] = splitPaneRects(800, 1245, pair, topInset: 45);
    expect(top, (left: 0.0, top: 45.0, width: 800.0, height: 600.0));
    expect(bottom, (left: 0.0, top: 645.0, width: 800.0, height: 600.0));
    expect(bottom.top, top.top + top.height);
    expect(bottom.top + bottom.height, 1245);
  });

  test('a split is refused when both minimums cannot fit', () {
    expect(
      splitRatioBounds(extent: 1600, firstMin: 900, secondMin: 800),
      isNull,
    );
    final bounds = splitRatioBounds(
      extent: 1600,
      firstMin: 700,
      secondMin: 600,
    )!;
    expect(bounds.min, closeTo(0.4375, 1e-9));
    expect(bounds.max, closeTo(0.625, 1e-9));
  });

  test('a landscape split asks for the width, a portrait one the height', () {
    expect(
      splitFits(
        width: 1600,
        height: 1000,
        topInset: 45,
        vertical: false,
        firstMinWidth: 700,
        firstMinHeight: 600,
        secondMinWidth: 600,
        secondMinHeight: 600,
      ),
      isTrue,
    );
    expect(
      splitFits(
        width: 800,
        height: 1000,
        topInset: 45,
        vertical: true,
        firstMinWidth: 1,
        firstMinHeight: 500,
        secondMinWidth: 1,
        secondMinHeight: 500,
      ),
      isFalse,
    );
  });
}

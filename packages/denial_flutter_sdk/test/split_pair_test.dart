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
    expect(pair.withSecond(9).isComplete, isTrue);
  });
}

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// A screen edge a dragged recents card can be dropped on.
enum SplitDropSide {
  left,
  right,
  top,
  bottom;

  bool get vertical => this == top || this == bottom;

  String get label => switch (this) {
    left => '放到左侧',
    right => '放到右侧',
    top => '拖到这里 = 上分屏',
    bottom => '拖到这里 = 下分屏',
  };
}

/// The dashed regions a picked-up card can be dropped on.
///
/// Both sides are always visible once a card is picked up, so the gesture reads
/// as split screen before the finger travels anywhere; the side under the
/// finger brightens.
class SplitDropOverlay extends StatelessWidget {
  const SplitDropOverlay({
    super.key,
    required this.side,
    required this.vertical,
    this.refusal,
  });

  final SplitDropSide? side;
  final bool vertical;

  /// Why the last drop could not start a split, if it could not.
  final String? refusal;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final active = side;
    final sides = vertical
        ? [SplitDropSide.top, SplitDropSide.bottom]
        : [SplitDropSide.left, SplitDropSide.right];
    return IgnorePointer(
      child: Stack(
        children: [
          for (final candidate in sides)
            Positioned.fromRect(
              rect: _rectFor(candidate, size),
              child: _DropRegion(
                label: candidate.label,
                detail: _detail(size, MediaQuery.devicePixelRatioOf(context)),
                active: candidate == active,
              ),
            ),
          if (refusal case final message?)
            Positioned(
              left: 24,
              right: 24,
              bottom: 96,
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xE614161C),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFF2F3F7),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (active == null)
            Positioned(
              left: 0,
              right: 0,
              top: size.height * 0.8,
              child: const Center(
                child: Text(
                  '松手取消',
                  style: TextStyle(
                    color: Color(0x80FFFFFF),
                    fontSize: 13,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// The pane each side would become: half the usable area, minus the gutter.
  /// Sizes are shown in logical pixels, whatever space the deck measures in.
  String _detail(Size size, double devicePixelRatio) {
    const margin = 14.0;
    const gutter = 14.0;
    const status = 45.0;
    final width = size.width / devicePixelRatio;
    final height = size.height / devicePixelRatio;
    final usableWidth = width - margin * 2 - gutter;
    final usableHeight = height - status - margin;
    final paneWidth = (vertical ? usableWidth : usableWidth / 2).round();
    final paneHeight = (vertical ? (usableHeight - gutter) / 2 : usableHeight)
        .round();
    return '50% · 约 $paneWidth × $paneHeight';
  }

  Rect _rectFor(SplitDropSide side, Size size) {
    // Each drop side is 40% of the screen; the middle 20% cancels.
    const margin = 14.0;
    final span = size.width * 0.4 - margin;
    final rise = size.height * 0.4 - margin;
    return switch (side) {
      SplitDropSide.left => Rect.fromLTWH(
        margin,
        margin,
        span,
        size.height - margin * 2,
      ),
      SplitDropSide.right => Rect.fromLTWH(
        size.width - margin - span,
        margin,
        span,
        size.height - margin * 2,
      ),
      SplitDropSide.top => Rect.fromLTWH(
        margin,
        margin,
        size.width - margin * 2,
        rise,
      ),
      SplitDropSide.bottom => Rect.fromLTWH(
        margin,
        size.height - margin - rise,
        size.width - margin * 2,
        rise,
      ),
    };
  }
}

class _DropRegion extends StatelessWidget {
  const _DropRegion({
    required this.label,
    required this.detail,
    required this.active,
  });

  final String label;
  final String detail;
  final bool active;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF6D5BD0);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: active ? const Color(0x246D5BD0) : const Color(0x146D5BD0),
        borderRadius: BorderRadius.circular(22),
      ),
      child: CustomPaint(
        painter: _DashedBorderPainter(
          color: active ? accent : const Color(0x806D5BD0),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: active ? accent : const Color(0xB36D5BD0),
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                detail,
                style: TextStyle(
                  color: active
                      ? const Color(0xB36D5BD0)
                      : const Color(0x806D5BD0),
                  fontSize: 12.5,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
          const Radius.circular(22),
        ),
      );
    const dash = 10.0;
    const gap = 6.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}

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
  const SplitDropOverlay({super.key, required this.side, required this.vertical});

  final SplitDropSide? side;
  final bool vertical;

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
                active: candidate == active,
              ),
            ),
        ],
      ),
    );
  }

  Rect _rectFor(SplitDropSide side, Size size) {
    const margin = 12.0;
    const gap = 8.0;
    final halfWidth = (size.width - margin * 2 - gap) / 2;
    final halfHeight = (size.height - margin * 2 - gap) / 2;
    return switch (side) {
      SplitDropSide.left => Rect.fromLTWH(
        margin,
        margin,
        halfWidth,
        size.height - margin * 2,
      ),
      SplitDropSide.right => Rect.fromLTWH(
        margin + halfWidth + gap,
        margin,
        halfWidth,
        size.height - margin * 2,
      ),
      SplitDropSide.top => Rect.fromLTWH(
        margin,
        margin,
        size.width - margin * 2,
        halfHeight,
      ),
      SplitDropSide.bottom => Rect.fromLTWH(
        margin,
        margin + halfHeight + gap,
        size.width - margin * 2,
        halfHeight,
      ),
    };
  }
}

class _DropRegion extends StatelessWidget {
  const _DropRegion({required this.label, required this.active});

  final String label;
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
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: active ? accent : const Color(0xB36D5BD0),
              fontSize: 17,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
            ),
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

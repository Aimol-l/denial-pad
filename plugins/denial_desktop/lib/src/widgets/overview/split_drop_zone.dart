import 'package:flutter/widgets.dart';

/// A screen edge a dragged recents card can be dropped on.
enum SplitDropSide {
  left,
  right,
  top,
  bottom;

  bool get vertical => this == top || this == bottom;

  bool get first => this == left || this == top;

  String get label => switch (this) {
    left => '左侧',
    right => '右侧',
    top => '上方',
    bottom => '下方',
  };
}

/// What dropping a card on an edge does.
enum SplitDropFunction {
  /// Put the card into that half of the screen.
  split,

  /// Keep the task: swiping it away no longer closes it.
  pin,

  /// Close the app, as the up-swipe would.
  close,
}

@immutable
class SplitDropTarget {
  const SplitDropTarget(this.side, this.function);

  final SplitDropSide side;
  final SplitDropFunction function;

  @override
  bool operator ==(Object other) =>
      other is SplitDropTarget &&
      other.side == side &&
      other.function == function;

  @override
  int get hashCode => Object.hash(side, function);
}

/// The three targets a picked-up card can be dropped on, on both edges.
///
/// Each edge is a column of functions — split, pin, close — so the gesture
/// answers "what will happen" before the finger lands. The side under the
/// finger stays bright; the rest fades.
class SplitDropOverlay extends StatelessWidget {
  const SplitDropOverlay({
    super.key,
    required this.target,
    required this.vertical,
    this.refusal,
  });

  final SplitDropTarget? target;
  final bool vertical;

  /// Why the last drop could not start a split, if it could not.
  final String? refusal;

  static const _functions = <SplitDropFunction>[
    SplitDropFunction.split,
    SplitDropFunction.pin,
    SplitDropFunction.close,
  ];

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final sides = vertical
        ? const <SplitDropSide>[SplitDropSide.top, SplitDropSide.bottom]
        : const <SplitDropSide>[SplitDropSide.left, SplitDropSide.right];
    final active = target;
    // The drop targets fade in as the card lifts, so the gesture explains
    // itself instead of waiting for the first move.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.scale(scale: 0.98 + 0.02 * value, child: child),
      ),
      child: IgnorePointer(
        child: Stack(
          fit: StackFit.expand,
          children: [
            for (final side in sides)
              Positioned.fromRect(
                rect: _bandFor(side, size, vertical),
                child: Flex(
                  direction: vertical ? Axis.horizontal : Axis.vertical,
                  // Stretch across the band: the default centre alignment
                  // shrank every target to the width of its own text.
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final function in _functions)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(5),
                          child: _DropRegion(
                            side: side,
                            function: function,
                            active:
                                active != null &&
                                active.side == side &&
                                active.function == function,
                            dimmed: active != null && active.side != side,
                          ),
                        ),
                      ),
                  ],
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
                top: size.height * 0.5 - 16,
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
      ),
    );
  }

  /// The band each edge owns: 28% of the screen, vertically between 12% and
  /// 88% so it stays clear of the status bar and the home gesture.
  Rect _bandFor(SplitDropSide side, Size size, bool vertical) {
    const margin = 14.0;
    final usable = size.width > 0 ? size : const Size(1600, 1000);
    final width = usable.width;
    final height = usable.height;
    return switch (side) {
      SplitDropSide.left => Rect.fromLTWH(
        margin,
        height * 0.12,
        width * 0.28 - margin,
        height * 0.76,
      ),
      SplitDropSide.right => Rect.fromLTWH(
        width * 0.72,
        height * 0.12,
        width * 0.28 - margin,
        height * 0.76,
      ),
      SplitDropSide.top => Rect.fromLTWH(
        width * 0.12,
        margin,
        width * 0.76,
        height * 0.28 - margin,
      ),
      SplitDropSide.bottom => Rect.fromLTWH(
        width * 0.12,
        height * 0.72,
        width * 0.76,
        height * 0.28 - margin,
      ),
    };
  }
}

class _DropRegion extends StatelessWidget {
  const _DropRegion({
    required this.side,
    required this.function,
    required this.active,
    required this.dimmed,
  });

  final SplitDropSide side;
  final SplitDropFunction function;
  final bool active;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final danger = function == SplitDropFunction.close;
    final accent = danger ? const Color(0xFFD2544C) : const Color(0xFF8B5CF6);
    final (glyph, title, detail) = switch (function) {
      SplitDropFunction.split => ('◫', '分屏', '放到${side.label}'),
      SplitDropFunction.pin => ('🔒', '锁定', '上滑不关闭'),
      SplitDropFunction.close => ('✕', '关闭', '关闭应用'),
    };
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 140),
      opacity: dimmed ? 0.28 : 1,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          // Dark enough to read on top of the white card being carried.
          color: active
              ? accent.withValues(alpha: 0.38)
              : const Color(0x660A0A10),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: active ? accent : const Color(0x99FFFFFF),
            width: active ? 1.6 : 1.2,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.25),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              glyph,
              style: TextStyle(
                fontSize: 20,
                color: active
                    ? const Color(0xFFF3F4F7)
                    : const Color(0xB3F3F4F7),
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: active
                    ? const Color(0xFFF3F4F7)
                    : const Color(0xCCF3F4F7),
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10.5,
                color: active
                    ? const Color(0xCCF3F4F7)
                    : const Color(0x80F3F4F7),
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

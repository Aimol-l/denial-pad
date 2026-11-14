import 'package:flutter/widgets.dart';

import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/shell_theme.dart';

/// The thin handle on the seam between the two panes.
///
/// It is a 1.5 px line with a 28 px touch band around it: dragging changes the
/// split ratio, but never past the point where either client would have to
/// shrink below the minimum size it declares. A double tap returns to 50:50.
class SplitDivider extends StatefulWidget {
  const SplitDivider({
    super.key,
    required this.vertical,
    required this.ratio,
    required this.bounds,
    required this.onRatio,
    required this.onReset,
  });

  /// Panes stacked top and bottom instead of side by side.
  final bool vertical;

  /// The first pane's share of the axis, as drawn.
  final double ratio;

  /// The interval that keeps both clients at their minimum size.
  final ({double min, double max}) bounds;

  final ValueChanged<double> onRatio;
  final VoidCallback onReset;

  @override
  State<SplitDivider> createState() => _SplitDividerState();
}

class _SplitDividerState extends State<SplitDivider> {
  /// How wide the finger may land from the line.
  static const double _hitWidth = 28;

  /// The ratio under the finger while dragging; null at rest.
  double? _drag;

  bool _dragging = false;

  Size _size = Size.zero;

  Offset _toLocal(Offset global) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return global;
    return box.globalToLocal(global);
  }

  void _update(Offset global) {
    final local = _toLocal(global);
    final extent = widget.vertical ? _size.height : _size.width;
    final position = widget.vertical ? local.dy : local.dx;
    var ratio = splitRatioAt(position, extent: extent, bounds: widget.bounds);
    // The middle is where most splits live; a couple of pixels decide nothing.
    if ((ratio - 0.5).abs() <= splitSnapWindow) ratio = 0.5;
    setState(() => _drag = ratio);
    widget.onRatio(ratio);
  }

  void _end() {
    if (!_dragging) return;
    setState(() {
      _dragging = false;
      _drag = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = _size = constraints.biggest;
        final ratio = (_drag ?? widget.ratio).clamp(
          widget.bounds.min,
          widget.bounds.max,
        );
        final along = (widget.vertical ? size.height : size.width) * ratio;
        final accent = ShellTheme.of(context).accent;
        final line = DecoratedBox(
          decoration: BoxDecoration(
            color: _dragging ? accent : accent.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(1),
          ),
          child: SizedBox(
            width: widget.vertical ? null : 2,
            height: widget.vertical ? 2 : null,
          ),
        );
        return Stack(
          children: [
            Positioned(
              left: widget.vertical ? 0 : along - _hitWidth / 2,
              top: widget.vertical ? along - _hitWidth / 2 : 0,
              width: widget.vertical ? size.width : _hitWidth,
              height: widget.vertical ? _hitWidth : size.height,
              child: MouseRegion(
                cursor: widget.vertical
                    ? SystemMouseCursors.resizeUpDown
                    : SystemMouseCursors.resizeLeftRight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: widget.onReset,
                  onHorizontalDragStart: widget.vertical
                      ? null
                      : (details) {
                          setState(() => _dragging = true);
                          _update(details.globalPosition);
                        },
                  onHorizontalDragUpdate: widget.vertical
                      ? null
                      : (details) => _update(details.globalPosition),
                  onHorizontalDragEnd: widget.vertical ? null : (_) => _end(),
                  onHorizontalDragCancel: widget.vertical ? null : _end,
                  onVerticalDragStart: widget.vertical
                      ? (details) {
                          setState(() => _dragging = true);
                          _update(details.globalPosition);
                        }
                      : null,
                  onVerticalDragUpdate: widget.vertical
                      ? (details) => _update(details.globalPosition)
                      : null,
                  onVerticalDragEnd: widget.vertical ? (_) => _end() : null,
                  onVerticalDragCancel: widget.vertical ? _end : null,
                  child: Center(child: line),
                ),
              ),
            ),
            if (_dragging)
              Positioned(
                left: widget.vertical ? 0 : along + 12,
                top: widget.vertical ? along + 12 : null,
                bottom: widget.vertical ? null : size.height / 2 + 12,
                child: IgnorePointer(child: _RatioBubble(ratio: ratio)),
              ),
          ],
        );
      },
    );
  }
}

/// The share under the finger, shown while dragging.
class _RatioBubble extends StatelessWidget {
  const _RatioBubble({required this.ratio});

  final double ratio;

  @override
  Widget build(BuildContext context) {
    final first = (ratio * 100).round();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xE614161C),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          '$first : ${100 - first}',
          style: const TextStyle(
            color: Color(0xFFF2F3F7),
            fontSize: 11,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}

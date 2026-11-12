import 'package:flutter/widgets.dart';

import 'package:denial_flutter_sdk/models.dart';

/// The handle that floats in the gutter between the two cards.
///
/// It drags the ratio (20–80% with the middle snap), resets on a double tap,
/// and closes the split from its ✕. Dragging into the last 10% on either side
/// is a close preview: the windows stay at their limit while a red ghost over
/// the squeezed card says it closes on release.
class SplitDivider extends StatefulWidget {
  const SplitDivider({
    super.key,
    required this.pair,
    required this.panes,
    required this.onRatio,
    required this.onReset,
    required this.onClose,
  });

  final SplitPair pair;

  /// The two cards, first then second, exactly where they are drawn.
  final List<Rect> panes;

  /// The windows' ratio, already snapped and clamped.
  final ValueChanged<double> onRatio;
  final VoidCallback onReset;
  final VoidCallback onClose;

  @override
  State<SplitDivider> createState() => SplitDividerState();
}

class SplitDividerState extends State<SplitDivider> {
  /// Where the handle follows the finger while dragging; null at rest.
  double? _drag;

  /// 0 or 1 while the drag is in a close band.
  int? _closing;

  /// The gap between the ✕ and the grip, both centred on the gutter.
  static const double _closeOffset = 48;
  static const double _hit = 44;

  Offset _toLocal(Offset global) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return global;
    return box.globalToLocal(global);
  }

  /// The ratio a finger at [global] asks for, with the gutter centred on it.
  double _ratioAt(Offset global) {
    final local = _toLocal(global);
    final vertical = widget.pair.vertical;
    final first = widget.panes.first;
    final second = widget.panes.last;
    final origin = vertical ? first.top : first.left;
    final gutter = vertical
        ? second.top - first.bottom
        : second.left - first.right;
    final span = (vertical ? second.bottom : second.right) - origin;
    final travel = span - gutter;
    if (travel <= 0) return widget.pair.ratio;
    final along = vertical ? local.dy : local.dx;
    return (along - gutter / 2 - origin) / travel;
  }

  void _update(Offset global) {
    final clamped = _ratioAt(global).clamp(0.0, 1.0);
    final closing = clamped <= 0.1
        ? 0
        : clamped >= 0.9
        ? 1
        : null;
    setState(() {
      _drag = clamped;
      _closing = closing;
    });
    // The panes keep their 20–80 limit while the handle reaches the band.
    widget.onRatio(splitFractions(clamped).first);
  }

  void _end() {
    final closing = _closing;
    setState(() {
      _drag = null;
      _closing = null;
    });
    if (closing != null) widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final pair = widget.pair;
    final vertical = pair.vertical;
    final first = widget.panes.first;
    final second = widget.panes.last;
    final origin = vertical ? first.top : first.left;
    final gutter = vertical
        ? second.top - first.bottom
        : second.left - first.right;
    final span = (vertical ? second.bottom : second.right) - origin;
    final ratio = _drag ?? splitFractions(pair.ratio).first;
    final along = origin + (span - gutter) * ratio + gutter / 2;
    final cross = vertical
        ? (first.left + first.right) / 2
        : (first.top + first.bottom) / 2;
    final center = vertical ? Offset(cross, along) : Offset(along, cross);
    final gripSize = vertical ? const Size(86, 38) : const Size(38, 86);
    return Stack(
      children: [
        if (_closing case final side?)
          Positioned.fromRect(
            rect: widget.panes[side],
            child: const _ClosingPreview(),
          ),
        Positioned(
          left: center.dx - _hit / 2,
          top: center.dy - _closeOffset - _hit / 2,
          width: _hit,
          height: _hit,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onClose,
            child: const Center(child: _CloseButton()),
          ),
        ),
        Positioned(
          left: center.dx - gripSize.width / 2,
          top: center.dy - gripSize.height / 2,
          width: gripSize.width,
          height: gripSize.height,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTap: widget.onReset,
            onHorizontalDragStart: vertical ? null : (_) {},
            onHorizontalDragUpdate: vertical
                ? null
                : (details) => _update(details.globalPosition),
            onHorizontalDragEnd: vertical ? null : (_) => _end(),
            onHorizontalDragCancel: vertical ? null : _end,
            onVerticalDragStart: vertical ? (_) {} : null,
            onVerticalDragUpdate: vertical
                ? (details) => _update(details.globalPosition)
                : null,
            onVerticalDragEnd: vertical ? (_) => _end() : null,
            onVerticalDragCancel: vertical ? _end : null,
            child: _Grip(vertical: vertical),
          ),
        ),
      ],
    );
  }
}

class _Grip extends StatelessWidget {
  const _Grip({required this.vertical});

  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final bars = vertical
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              _Bar(horizontal: true),
              SizedBox(height: 4),
              _Bar(horizontal: true),
            ],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: const [_Bar(), SizedBox(width: 4), _Bar()],
          );
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xEBFFFFFF),
        borderRadius: BorderRadius.circular(19),
        boxShadow: const [
          BoxShadow(
            color: Color(0x3814161C),
            blurRadius: 20,
            offset: Offset(0, 6),
          ),
          BoxShadow(color: Color(0x0F14161C), spreadRadius: 1),
        ],
      ),
      alignment: Alignment.center,
      child: bars,
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({this.horizontal = false});

  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: horizontal ? 22 : 3,
      height: horizontal ? 3 : 22,
      decoration: BoxDecoration(
        color: const Color(0xFFC8CCD4),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: const BoxDecoration(
        color: Color(0xEBFFFFFF),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Color(0x2E14161C),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
          BoxShadow(color: Color(0x0F14161C), spreadRadius: 1),
        ],
      ),
      alignment: Alignment.center,
      child: const SizedBox(
        width: 12,
        height: 12,
        child: CustomPaint(painter: _CrossPainter()),
      ),
    );
  }
}

class _CrossPainter extends CustomPainter {
  const _CrossPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF5F6470)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset.zero, Offset(size.width, size.height), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant _CrossPainter oldDelegate) => false;
}

/// The red ghost over the card that would close if the finger lifted now.
class _ClosingPreview extends StatelessWidget {
  const _ClosingPreview();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0x24E5534B),
          borderRadius: BorderRadius.circular(splitCardRadius),
          border: Border.all(color: const Color(0x99E5534B), width: 2),
        ),
        alignment: Alignment.center,
        child: const Text(
          '松手关闭\n这一侧',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFFB8433B),
            fontSize: 14,
            height: 1.5,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}

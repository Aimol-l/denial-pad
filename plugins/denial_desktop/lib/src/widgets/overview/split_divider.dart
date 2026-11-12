import 'package:flutter/widgets.dart';

import 'package:denial_flutter_sdk/models.dart';

/// The handle that sits in the gutter between the two panes.
///
/// It drags the ratio (20–80% with the middle snap), resets on a double tap,
/// and closes the split from its ✕. Dragging past the last 10% on either side
/// is a close preview: the windows stay at their limit while a red overlay
/// says the side will close on release.
class SplitDivider extends StatefulWidget {
  const SplitDivider({
    super.key,
    required this.pair,
    required this.onRatio,
    required this.onReset,
    required this.onClose,
  });

  final SplitPair pair;

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

  /// The gap between the ✕ and the grip, both centred on the divider.
  static const double _closeOffset = 48;
  static const double _hit = 44;

  Size _renderSize = Size.zero;

  Offset _toLocal(Offset global) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return global;
    return box.globalToLocal(global);
  }

  void _update(Offset global) {
    final local = _toLocal(global);
    final vertical = widget.pair.vertical;
    final span = vertical ? _renderSize.height : _renderSize.width;
    if (span <= 0) return;
    final fraction = (vertical ? local.dy : local.dx) / span;
    final clamped = fraction.clamp(0.0, 1.0);
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = _renderSize = constraints.biggest;
        final fraction = _drag ?? splitFractions(pair.ratio).first;
        final center = Offset(
          vertical ? size.width / 2 : size.width * fraction,
          vertical ? size.height * fraction : size.height / 2,
        );
        final gripSize = vertical
            ? const Size(86, 38)
            : const Size(38, 86);
        return Stack(
          children: [
            if (_closing case final side?)
              Positioned(
                left: vertical ? 0 : (side == 0 ? 0 : null),
                right: vertical ? 0 : (side == 1 ? 0 : null),
                top: vertical ? (side == 0 ? 0 : null) : 0,
                bottom: vertical ? (side == 1 ? 0 : null) : 0,
                width: vertical ? null : 190,
                height: vertical ? 190 : null,
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
      },
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

class _ClosingPreview extends StatelessWidget {
  const _ClosingPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0x24E5534B),
        borderRadius: BorderRadius.circular(20),
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
    );
  }
}

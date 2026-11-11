import 'package:flutter/widgets.dart';

/// Scrolls without drawing a scrollbar or an overscroll glow.
///
/// The keyboard pages are swiped with a finger over keys; a scrollbar would
/// sit on top of the symbols, and the glow reads as a rendering fault.
class QuietScroll extends StatelessWidget {
  const QuietScroll({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        scrollbars: false,
        overscroll: false,
      ),
      child: child,
    );
  }
}

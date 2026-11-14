part of 'notification_banner.dart';

class _NotificationActivator extends StatefulWidget {
  const _NotificationActivator({
    required this.semanticLabel,
    required this.onActivate,
    required this.borderRadius,
    required this.child,
  });

  final String semanticLabel;
  final VoidCallback onActivate;
  final BorderRadius borderRadius;
  final Widget child;

  @override
  State<_NotificationActivator> createState() => _NotificationActivatorState();
}

class _NotificationActivatorState extends State<_NotificationActivator> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      mouseCursor: SystemMouseCursors.click,
      onShowFocusHighlight: (focused) => setState(() => _focused = focused),
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onActivate();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onActivate,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            border: _focused
                ? Border.all(color: ShellTheme.of(context).accent, width: 1.5)
                : null,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// One action of a notification. An icon reads faster than a word when the
/// notification names its actions that way (`action-icons`) or when the label
/// is one we know; anything else keeps its text.
class _ResolvedActionButton extends ConsumerWidget {
  const _ResolvedActionButton({
    required this.action,
    required this.actionIcons,
    required this.onPressed,
    this.mobile = false,
    this.fontSize = 12,
    this.textColor,
    this.visualScale = 1,
  });

  final DesktopNotificationAction action;

  /// The notification asked for its actions to be drawn as icons, so each
  /// label is an icon name.
  final bool actionIcons;
  final bool mobile;
  final double fontSize;
  final Color? textColor;
  final double visualScale;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var icon = _actionIconFor(action.label);
    String? iconPath;
    if (icon == null && actionIcons && action.label.trim().isNotEmpty) {
      iconPath = ref
          .watch(
            notificationIconPathProvider(
              NotificationIconRequest(
                appIcon: action.label.trim(),
                desktopEntry: '',
                appName: '',
              ),
            ),
          )
          .value;
    }
    return _NotificationActionButton(
      label: action.label.isEmpty ? action.key : action.label,
      icon: icon,
      iconPath: iconPath,
      onPressed: onPressed,
      mobile: mobile,
      fontSize: fontSize,
      textColor: textColor,
      visualScale: visualScale,
    );
  }
}

/// The icon for the actions applications repeat: media transport, messaging
/// and the usual dismissals, in the languages this shell speaks.
IconData? _actionIconFor(String label) {
  final text = label.trim().toLowerCase();
  if (text.isEmpty) {
    return null;
  }
  bool matches(List<String> needles) =>
      needles.any((needle) => text == needle || text.contains(needle));
  if (matches(const <String>['上一首', '上一曲', 'previous', 'prev', 'back'])) {
    return Icons.skip_previous_rounded;
  }
  if (matches(const <String>['下一首', '下一曲', 'next', 'forward'])) {
    return Icons.skip_next_rounded;
  }
  if (matches(const <String>['暂停', 'pause'])) {
    return Icons.pause_rounded;
  }
  if (matches(const <String>['播放', '继续', 'play', 'resume'])) {
    return Icons.play_arrow_rounded;
  }
  if (matches(const <String>['停止', 'stop'])) {
    return Icons.stop_rounded;
  }
  if (matches(const <String>['静音', 'mute', 'silence'])) {
    return Icons.volume_off_rounded;
  }
  if (matches(const <String>['回复', 'reply'])) {
    return Icons.reply_rounded;
  }
  if (matches(const <String>['已读', 'mark as read', 'read all'])) {
    return Icons.done_all_rounded;
  }
  if (matches(const <String>['收藏', '喜欢', 'like', 'favourite', 'favorite'])) {
    return Icons.favorite_border_rounded;
  }
  if (matches(const <String>['稍后', 'snooze'])) {
    return Icons.schedule_rounded;
  }
  if (matches(const <String>['删除', 'delete', 'remove'])) {
    return Icons.delete_outline_rounded;
  }
  if (matches(const <String>['打开', 'open'])) {
    return Icons.open_in_new_rounded;
  }
  if (matches(const <String>['取消', '关闭', '忽略', 'cancel', 'dismiss', 'close'])) {
    return Icons.close_rounded;
  }
  if (matches(const <String>['接听', 'answer', 'accept'])) {
    return Icons.call_rounded;
  }
  if (matches(const <String>['挂断', 'decline', 'hang up', 'reject'])) {
    return Icons.call_end_rounded;
  }
  return null;
}

class _NotificationActionButton extends StatefulWidget {
  const _NotificationActionButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.iconPath,
    this.mobile = false,
    this.fontSize = 12,
    this.textColor,
    this.visualScale = 1,
  });

  final String label;
  final IconData? icon;
  final String? iconPath;
  final bool mobile;
  final double fontSize;
  final Color? textColor;
  final double visualScale;
  final VoidCallback onPressed;

  bool get iconOnly => icon != null || iconPath != null;

  @override
  State<_NotificationActionButton> createState() =>
      _NotificationActionButtonState();
}

class _NotificationActionButtonState extends State<_NotificationActionButton> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final scale = widget.visualScale;
    final iconOnly = widget.iconOnly;
    return Semantics(
      button: true,
      label: widget.label,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (hovered) => setState(() => _hovered = hovered),
        onShowFocusHighlight: (focused) => setState(() => _focused = focused),
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : Motion.pill,
            curve: Motion.standard,
            constraints: BoxConstraints(
              minWidth: MobileNotificationMetrics.actionMinimumWidth * scale,
            ),
            padding: EdgeInsets.symmetric(
              horizontal: iconOnly
                  ? 0
                  : MobileNotificationMetrics.actionHorizontalInset * scale,
            ),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hovered || _focused
                  ? context.shellTheme.accentPalette.container
                  : context.shellColors.surfaceContainerHighest,
              borderRadius: context.shellTheme.borderRadius(
                MobileNotificationMetrics.actionRadius * scale,
              ),
              border: _focused
                  ? Border.all(color: ShellTheme.of(context).accent)
                  : widget.mobile &&
                        context.shellTheme.transparencyMode ==
                            ShellTransparencyMode.glass
                  ? null
                  : Border.all(color: context.shellColors.hairlineSoft),
            ),
            child: iconOnly
                ? SizedBox.square(
                    dimension: MobileNotificationMetrics.actionHeight * scale,
                    child: Center(
                      child: widget.iconPath != null
                          ? SizedBox.square(
                              dimension:
                                  MobileNotificationMetrics.actionIconSize *
                                  scale,
                              child: AppIconImage(iconPath: widget.iconPath),
                            )
                          : Icon(
                              widget.icon,
                              size:
                                  MobileNotificationMetrics.actionIconSize *
                                  scale,
                              color:
                                  widget.textColor ??
                                  context.shellColors.textPrimary,
                            ),
                    ),
                  )
                : Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ShellText.cardTitle.copyWith(
                      fontSize: widget.fontSize,
                      color: widget.textColor,
                      fontWeight: widget.textColor != null
                          ? FontWeight.w700
                          : FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Gives desktop notification cards a bidirectional swipe-to-dismiss gesture
/// without requiring the card to disappear when the dismissal request fails.
class DesktopNotificationSwipeDismiss extends StatefulWidget {
  const DesktopNotificationSwipeDismiss({
    required this.child,
    required this.onDismiss,
    super.key,
    this.enabled = true,
  });

  final Widget child;
  final bool Function() onDismiss;
  final bool enabled;

  @override
  State<DesktopNotificationSwipeDismiss> createState() =>
      _DesktopNotificationSwipeDismissState();
}

class _DesktopNotificationSwipeDismissState
    extends State<DesktopNotificationSwipeDismiss> {
  static const double _distanceThreshold = 0.24;
  static const double _velocityThreshold = 700;

  double _dragOffset = 0;
  bool _dragging = false;
  bool _dismissed = false;

  void _startDrag() {
    setState(() {
      _dragging = true;
      _dragOffset = 0;
      _dismissed = false;
    });
  }

  void _updateDrag(DragUpdateDetails details, double width) {
    setState(() {
      _dragOffset = (_dragOffset + (details.primaryDelta ?? 0))
          .clamp(-width, width)
          .toDouble();
    });
  }

  void _endDrag(DragEndDetails details, double width) {
    final velocity = details.primaryVelocity ?? 0;
    final shouldDismiss =
        _dragOffset.abs() >= width * _distanceThreshold ||
        velocity.abs() >= _velocityThreshold;
    final direction = _dragOffset == 0
        ? (velocity < 0 ? -1.0 : 1.0)
        : _dragOffset.sign;
    final dismissed = shouldDismiss && widget.onDismiss();
    setState(() {
      _dragging = false;
      _dismissed = dismissed;
      _dragOffset = dismissed ? direction * width : 0;
    });
  }

  void _cancelDrag() {
    setState(() {
      _dragging = false;
      _dragOffset = 0;
      _dismissed = false;
    });
  }

  void _dismissFromSemantics(double width) {
    if (!widget.onDismiss()) {
      return;
    }
    setState(() {
      _dragging = false;
      _dragOffset = width;
      _dismissed = true;
    });
  }

  @override
  void didUpdateWidget(covariant DesktopNotificationSwipeDismiss oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled && !_dismissed) {
      _dragging = false;
      _dragOffset = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth > 0 && constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 1.0;
        final slide = _dragOffset / width;
        return Semantics(
          onDismiss: widget.enabled ? () => _dismissFromSemantics(width) : null,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: widget.enabled ? (_) => _startDrag() : null,
            onHorizontalDragUpdate: widget.enabled
                ? (details) => _updateDrag(details, width)
                : null,
            onHorizontalDragEnd: widget.enabled
                ? (details) => _endDrag(details, width)
                : null,
            onHorizontalDragCancel: widget.enabled ? _cancelDrag : null,
            child: AnimatedSlide(
              offset: Offset(slide, 0),
              duration: _dragging || MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : Motion.pill,
              curve: Motion.standard,
              child: widget.child,
            ),
          ),
        );
      },
    );
  }
}

class _NotificationIconButton extends StatefulWidget {
  const _NotificationIconButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.visualScale = 1,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final double visualScale;

  @override
  State<_NotificationIconButton> createState() =>
      _NotificationIconButtonState();
}

class _NotificationIconButtonState extends State<_NotificationIconButton> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (hovered) => setState(() => _hovered = hovered),
        onShowFocusHighlight: (focused) => setState(() => _focused = focused),
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : Motion.pill,
            width: MobileNotificationMetrics.dismissExtent * widget.visualScale,
            height:
                MobileNotificationMetrics.dismissExtent * widget.visualScale,
            decoration: BoxDecoration(
              color: _hovered || _focused
                  ? context.shellColors.surfaceContainerHighest
                  : ShellMediaColors.transparentDark,
              borderRadius: context.shellTheme.borderRadius(
                MobileNotificationMetrics.dismissRadius * widget.visualScale,
              ),
              border: _focused
                  ? Border.all(color: ShellTheme.of(context).accent)
                  : null,
            ),
            child: Icon(
              widget.icon,
              size: MobileNotificationMetrics.dismissIcon * widget.visualScale,
              color: context.shellColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

Offset _notificationEntryOffset(ShellPopupAnchor anchor) {
  if (anchor.vertical != 0) {
    return Offset(0, anchor.vertical.toDouble());
  }
  if (anchor.horizontal != 0) {
    return Offset(anchor.horizontal.toDouble(), 0);
  }
  return const Offset(0, -1);
}

String notificationAppName(
  DesktopNotification notification,
  AppLocalizations l10n,
) {
  if (notification.appName.isNotEmpty) {
    return notification.appName;
  }
  if (notification.desktopEntry.isNotEmpty) {
    return notification.desktopEntry;
  }
  return l10n.notificationGeneric;
}

String plainNotificationBody(String value) {
  return value
      .replaceAll(RegExp(r'<\s*br\s*/?\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&')
      .trim();
}

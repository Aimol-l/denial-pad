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
class _ResolvedActionButton extends ConsumerStatefulWidget {
  const _ResolvedActionButton({
    required this.action,
    required this.actionIcons,
    required this.toggleKey,
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

  /// Identifies the notification's current content (id and summary): a new
  /// track or page starts the flips over.
  final String toggleKey;
  final bool mobile;
  final double fontSize;
  final Color? textColor;
  final double visualScale;
  final VoidCallback onPressed;

  @override
  ConsumerState<_ResolvedActionButton> createState() =>
      _ResolvedActionButtonState();
}

class _ResolvedActionButtonState extends ConsumerState<_ResolvedActionButton> {
  /// Actions already tapped, by notification content and action key. Playing,
  /// pausing, liking: the application keeps sending the same key, so the
  /// button remembers what the tap did until the content changes.
  static final Map<String, bool> _flipped = <String, bool>{};

  String get _flipKey => '${widget.toggleKey}:${widget.action.key}';

  bool get _isFlipped => _flipped[_flipKey] ?? false;

  void _tap() {
    if (_flipOpposite(_icon) != null) {
      setState(() => _flipped[_flipKey] = !_isFlipped);
    }
    widget.onPressed();
  }

  IconData? get _icon {
    final icon =
        _actionIconFor(widget.action.label) ??
        (_isPlayPause(widget.action.label) ? _transportIcon : null);
    if (icon == null || !_isFlipped) {
      return icon;
    }
    return _flipOpposite(icon) ?? icon;
  }

  /// A play/pause toggle has no glyph of its own: the transport state the
  /// session reports says which half to draw.
  IconData get _transportIcon {
    final playing = ref.watch(
      mediaPlaybackProvider.select(
        (playback) => playback.value?.status == MprisPlaybackStatus.playing,
      ),
    );
    return playing ? Icons.pause_rounded : Icons.play_arrow_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final icon = _icon;
    String? iconPath;
    if (icon == null &&
        widget.actionIcons &&
        widget.action.label.trim().isNotEmpty) {
      iconPath = ref
          .watch(
            notificationIconPathProvider(
              NotificationIconRequest(
                appIcon: widget.action.label.trim(),
                desktopEntry: '',
                appName: '',
              ),
            ),
          )
          .value;
    }
    return _NotificationActionButton(
      label: _actionLabel(widget.action),
      icon: icon,
      iconPath: iconPath,
      onPressed: _tap,
      mobile: widget.mobile,
      fontSize: widget.fontSize,
      textColor: widget.textColor,
      visualScale: widget.visualScale,
    );
  }
}

/// The words a few actions read better than any glyph. `lyric` asks for the
/// lyrics panel; one character says it in the space a glyph would take.
String _actionLabel(DesktopNotificationAction action) {
  final text = action.label.trim().toLowerCase();
  if (text == 'lyric' || text == 'lyrics') {
    return '词';
  }
  return action.label.isEmpty ? action.key : action.label;
}

/// The other half of a toggle, or null when the icon does not toggle.
IconData? _flipOpposite(IconData? icon) => switch (icon) {
  Icons.play_arrow_rounded => Icons.pause_rounded,
  Icons.pause_rounded => Icons.play_arrow_rounded,
  Icons.favorite_border_rounded => Icons.favorite_rounded,
  Icons.favorite_rounded => Icons.favorite_border_rounded,
  Icons.star_border_rounded => Icons.star_rounded,
  Icons.star_rounded => Icons.star_border_rounded,
  _ => null,
};

bool _isPlayPause(String label) {
  final text = label.trim().toLowerCase();
  return text == 'toggle' || text == 'play_pause' || text == 'play-pause';
}

/// The icon for the actions applications repeat: media transport, messaging
/// and the usual dismissals, in the languages this shell speaks.
IconData? _actionIconFor(String label) {
  final text = label.trim().toLowerCase();
  if (text.isEmpty) {
    return null;
  }
  // Short keys travel as action identifiers rather than sentences: NetEase
  // Cloud Music sends `pre`, `toggle`, `next` and `lyric`. They match whole.
  final exact = switch (text) {
    'pre' || 'prev' || 'previous' || 'back' => Icons.skip_previous_rounded,
    'next' || 'forward' => Icons.skip_next_rounded,
    'fore_back' || 'rewind' || 'seek_back' => Icons.fast_rewind_rounded,
    'fore_ahead' || 'seek_forward' => Icons.fast_forward_rounded,
    'like' || 'favourite' || 'favorite' => Icons.favorite_border_rounded,
    'unlike' || 'unfavourite' || 'unfavorite' => Icons.favorite_rounded,
    'playlist' || 'queue' => Icons.queue_music_rounded,
    'download' => Icons.download_rounded,
    'share' => Icons.share_rounded,
    'comment' => Icons.mode_comment_outlined,
    'volume' || 'volume_up' => Icons.volume_up_rounded,
    _ => null,
  };
  if (exact != null) {
    return exact;
  }
  bool matches(List<String> needles) =>
      needles.any((needle) => text == needle || text.contains(needle));
  if (matches(const <String>['上一首', '上一曲', 'back'])) {
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

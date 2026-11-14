part of 'notification_banner.dart';

/// The same card presentation and expansion controls in heads-up and history.
class MobileNotificationCard extends StatefulWidget {
  const MobileNotificationCard({
    required this.notification,
    super.key,
    this.previewMode = NotificationPreviewMode.full,
    this.interactive = true,
    this.announce = false,
    this.groupedBackdrop = false,
    this.cachedBackdrop = false,
    this.surfaceBuilder,
    this.group,
    this.onExpandGroup,
    this.onDefaultAction,
    this.onAction,
  });

  static const horizontalMargin = MobileNotificationMetrics.horizontalMargin;

  final DesktopNotification notification;
  final NotificationPreviewMode previewMode;
  final bool interactive;
  final bool announce;
  final bool groupedBackdrop;
  final bool cachedBackdrop;
  final Widget Function(BuildContext, Widget)? surfaceBuilder;

  /// A collapsed group this card stands for; a tap runs [onExpandGroup].
  final DesktopNotificationGroup? group;
  final VoidCallback? onExpandGroup;

  final VoidCallback? onDefaultAction;
  final ValueChanged<String>? onAction;

  @override
  State<MobileNotificationCard> createState() => _MobileNotificationCardState();
}

class _MobileNotificationCardState extends State<MobileNotificationCard> {
  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    if (group != null && group.stacked) return _buildGroup(context, group);
    final canOpen =
        widget.interactive &&
        widget.previewMode == NotificationPreviewMode.full &&
        widget.onDefaultAction != null &&
        widget.notification.opensApp;
    // Every card shows what it has: no fold-back chevron, no hidden lines.
    final card = NotificationCard(
      notification: widget.notification,
      mobile: true,
      announce: widget.announce,
      groupedBackdrop: widget.groupedBackdrop,
      cachedBackdrop: widget.cachedBackdrop,
      expanded: true,
      showActions: true,
      previewMode: widget.previewMode,
      onDefaultAction: canOpen ? widget.onDefaultAction : null,
      onAction: widget.interactive ? widget.onAction : null,
    );
    return widget.surfaceBuilder?.call(context, card) ?? card;
  }

  Widget _buildGroup(BuildContext context, DesktopNotificationGroup group) {
    final card = NotificationCard(
      notification: widget.notification,
      mobile: true,
      announce: widget.announce,
      groupedBackdrop: widget.groupedBackdrop,
      cachedBackdrop: widget.cachedBackdrop,
      showActions: false,
      previewMode: widget.previewMode,
      group: group,
      onExpandGroup: widget.interactive ? widget.onExpandGroup : null,
    );
    return widget.surfaceBuilder?.call(context, card) ?? card;
  }
}

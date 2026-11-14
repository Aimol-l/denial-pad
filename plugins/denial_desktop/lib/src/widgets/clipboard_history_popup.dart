import 'dart:async';

import 'package:flutter/material.dart' show CircularProgressIndicator, Icons;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:denial_flutter_sdk/effects.dart' show ShellBackdropBlur;
import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/motion.dart';
import 'package:denial_flutter_sdk/shell_theme.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/tokens.dart';

import '../state/clipboard_tray.dart'
    show ClipboardDataKey, clipboardEntryDataProvider, clipboardImageMimeType;

/// The recent copies, in the popup the shade opens over itself on a tablet.
///
/// It is the same surface the Wi-Fi and Bluetooth details use: one panel, a
/// titled header with icon buttons, and one card per entry. A tap puts an
/// entry back on the clipboard and closes the popup; only [visible] entries
/// are drawn so even a long history fits the panel.
class ClipboardHistoryPopup extends ConsumerWidget {
  const ClipboardHistoryPopup({required this.onClose, super.key});

  final VoidCallback onClose;

  static const int visible = 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(clipboardHistoryProvider);
    final entries = state.entries.take(visible).toList(growable: false);
    final theme = ShellTheme.of(context);
    final l10n = context.l10n;
    return SafeArea(
      minimum: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540, maxHeight: 720),
          child: ShellBackdropBlur(
            separateChild: true,
            blur: theme.effectivePanelOpacity < 1.0,
            borderRadius: BorderRadius.circular(theme.panelRadius),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.panelColor(context.shellColors.panelBackground),
                borderRadius: BorderRadius.circular(theme.panelRadius),
                border: Border.all(color: context.shellColors.hairline),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(
                          Icons.content_paste_rounded,
                          size: 23,
                          color: theme.accent,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                l10n.quickSettingsClipboard,
                                style: ShellText.statusClock.copyWith(
                                  fontSize: 20,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                l10n.clipboardHistorySubtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: ShellText.base.copyWith(
                                  color: context.shellColors.textTertiary,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _ClipboardIconButton(
                          label: l10n.clipboardClearAll,
                          icon: Icons.delete_sweep_rounded,
                          enabled: entries.isNotEmpty && !state.clearing,
                          busy: state.clearing,
                          onPressed: () => unawaited(
                            ref.read(clipboardHistoryProvider.notifier).clear(),
                          ),
                        ),
                        const SizedBox(width: 7),
                        _ClipboardIconButton(
                          label: l10n.clipboardCloseHistory,
                          icon: Icons.close_rounded,
                          onPressed: onClose,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: _ClipboardHistoryBody(
                        state: state,
                        entries: entries,
                        onActivate: (entry) async {
                          final copied = await ref
                              .read(clipboardHistoryProvider.notifier)
                              .activate(entry.id);
                          if (copied) onClose();
                        },
                        onRetry: () => unawaited(
                          ref.read(clipboardHistoryProvider.notifier).refresh(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The list, or the one message that stands in for it.
class _ClipboardHistoryBody extends StatelessWidget {
  const _ClipboardHistoryBody({
    required this.state,
    required this.entries,
    required this.onActivate,
    required this.onRetry,
  });

  final ClipboardHistoryViewState state;
  final List<ClipboardHistoryEntry> entries;
  final ValueChanged<ClipboardHistoryEntry> onActivate;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (state.snapshot?.locked ?? false) {
      return _ClipboardMessage(
        icon: Icons.lock_outline_rounded,
        title: l10n.clipboardHistoryLockedTitle,
        body: l10n.clipboardHistoryLockedDescription,
      );
    }
    if (entries.isEmpty) {
      if (state.loading) {
        return Center(
          child: SizedBox.square(
            dimension: 25,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: ShellTheme.of(context).accent,
            ),
          ),
        );
      }
      if (state.error != null) {
        return _ClipboardMessage(
          icon: Icons.sync_problem_rounded,
          title: l10n.clipboardUnavailableTitle,
          body: l10n.clipboardUnavailableDescription,
          actionLabel: l10n.commonRetry,
          onAction: onRetry,
        );
      }
      return _ClipboardMessage(
        icon: Icons.content_paste_off_rounded,
        title: l10n.clipboardEmptyTitle,
        body: l10n.clipboardEmptyDescription,
      );
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 7),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return _ClipboardRow(
          key: ValueKey<int>(entry.id),
          entry: entry,
          onTap: () => onActivate(entry),
        );
      },
    );
  }
}

/// One copy, drawn as the card the Wi-Fi rows use.
class _ClipboardRow extends StatefulWidget {
  const _ClipboardRow({required this.entry, required this.onTap, super.key});

  final ClipboardHistoryEntry entry;
  final VoidCallback onTap;

  @override
  State<_ClipboardRow> createState() => _ClipboardRowState();
}

class _ClipboardRowState extends State<_ClipboardRow> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final theme = ShellTheme.of(context);
    final l10n = context.l10n;
    final active = entry.active;
    final palette = theme.accentPalette;
    final imageMime = clipboardImageMimeType(entry);
    final preview = entry.preview.trim().replaceAll(RegExp(r'\s+'), ' ');
    // An image carries no text preview, so it is named by its kind and size
    // instead of looking like a copy that failed to arrive.
    final title = imageMime != null
        ? l10n.clipboardImageLabel
        : preview.isEmpty
        ? l10n.clipboardPreviewUnavailable
        : preview;
    final detail = <String>[
      if (imageMime != null) '${entry.width} × ${entry.height}',
      _time(entry.capturedAt),
      if (entry.sourceTitle.isNotEmpty) entry.sourceTitle,
    ].join(' · ');
    final typeLabel = imageMime != null
        ? l10n.clipboardImageLabel
        : l10n.clipboardTypeText;
    return Semantics(
      button: true,
      label: l10n.clipboardItemSemantics(typeLabel, title),
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
              widget.onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : Motion.tile,
            constraints: const BoxConstraints(minHeight: 62),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: active
                  ? palette.container
                  : _hovered || _focused
                  ? context.shellColors.surfaceContainerHighest
                  : context.shellColors.surfaceContainer,
              borderRadius: theme.borderRadius(16),
              border: Border.all(
                color: _focused
                    ? theme.accent
                    : context.shellColors.hairlineSoft,
              ),
            ),
            child: Row(
              children: <Widget>[
                if (imageMime != null)
                  _ClipboardThumbnail(entry: entry, mimeType: imageMime)
                else
                  Icon(
                    Icons.notes_rounded,
                    size: 23,
                    color: active
                        ? palette.onContainer
                        : context.shellColors.textPrimary,
                  ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ShellText.cardTitle.copyWith(
                          color: active ? palette.onContainer : null,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ShellText.base.copyWith(
                          color: active
                              ? palette.onContainerSecondary
                              : context.shellColors.textTertiary,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.content_copy_rounded,
                  size: 18,
                  color: active
                      ? palette.onContainerSecondary
                      : context.shellColors.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The clock time of the copy, prefixed with the day when it is older.
  static String _time(DateTime capturedAt) {
    final local = capturedAt.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    final time = '${two(local.hour)}:${two(local.minute)}';
    final now = DateTime.now();
    final sameDay =
        now.year == local.year &&
        now.month == local.month &&
        now.day == local.day;
    return sameDay ? time : '${two(local.month)}-${two(local.day)} $time';
  }
}

class _ClipboardThumbnail extends ConsumerStatefulWidget {
  const _ClipboardThumbnail({required this.entry, required this.mimeType});

  final ClipboardHistoryEntry entry;
  final String mimeType;

  static const double _size = 40;
  static const int _retries = 2;

  @override
  ConsumerState<_ClipboardThumbnail> createState() =>
      _ClipboardThumbnailState();
}

class _ClipboardThumbnailState extends ConsumerState<_ClipboardThumbnail> {
  int _attempt = 0;
  bool _reported = false;

  ClipboardDataKey get _key =>
      ClipboardDataKey(widget.entry.id, widget.mimeType);

  @override
  void didUpdateWidget(_ClipboardThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.id != widget.entry.id ||
        oldWidget.mimeType != widget.mimeType) {
      _attempt = 0;
      _reported = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    final data = ref.watch(clipboardEntryDataProvider(_key));
    return ClipRRect(
      borderRadius: theme.borderRadius(10),
      child: SizedBox.square(
        dimension: _ClipboardThumbnail._size,
        child: data.when(
          data: (value) => Image.memory(
            value.bytes,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            cacheWidth:
                (_ClipboardThumbnail._size *
                        MediaQuery.devicePixelRatioOf(context))
                    .round(),
            errorBuilder: (context, _, _) => _placeholder(context),
          ),
          loading: () => ColoredBox(
            color: context.shellColors.hairlineSoft,
            child: const Center(
              child: SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (error, _) {
            // A capture in flight can hold the compositor long enough for the
            // first read to lapse; try again before calling the image lost.
            if (_attempt < _ClipboardThumbnail._retries) {
              _attempt += 1;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  ref.invalidate(clipboardEntryDataProvider(_key));
                }
              });
            } else if (!_reported) {
              _reported = true;
              debugPrint(
                'clipboard thumbnail ${widget.entry.id} unavailable: $error',
              );
            }
            return _placeholder(context);
          },
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext context) => ColoredBox(
    color: context.shellColors.hairlineSoft,
    child: Icon(
      Icons.image_outlined,
      size: 18,
      color: context.shellColors.textSecondary,
    ),
  );
}

/// A rounded square icon action, the same size as the Wi-Fi details' buttons.
class _ClipboardIconButton extends StatefulWidget {
  const _ClipboardIconButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.busy = false,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool busy;
  final bool enabled;

  @override
  State<_ClipboardIconButton> createState() => _ClipboardIconButtonState();
}

class _ClipboardIconButtonState extends State<_ClipboardIconButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.label,
      child: FocusableActionDetector(
        enabled: widget.enabled,
        mouseCursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowFocusHighlight: (focused) => setState(() => _focused = focused),
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              if (widget.enabled) {
                widget.onPressed();
              }
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? widget.onPressed : null,
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : Motion.pill,
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: context.shellColors.surfaceContainerHigh,
              borderRadius: theme.borderRadius(12),
              border: Border.all(
                color: _focused
                    ? theme.accent
                    : context.shellColors.hairlineSoft,
              ),
            ),
            child: widget.busy
                ? Padding(
                    padding: const EdgeInsets.all(9),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.accent,
                    ),
                  )
                : Icon(
                    widget.icon,
                    size: 18,
                    color: widget.enabled
                        ? context.shellColors.textSecondary
                        : context.shellColors.glyphInactive,
                  ),
          ),
        ),
      ),
    );
  }
}

/// A centred icon, title and explanation, like the Wi-Fi empty states.
class _ClipboardMessage extends StatelessWidget {
  const _ClipboardMessage({
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: context.l10n.commonTitleAndBody(title, body),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 330),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 36, color: context.shellColors.textTertiary),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: ShellText.cardTitle,
              ),
              const SizedBox(height: 5),
              Text(
                body,
                textAlign: TextAlign.center,
                style: ShellText.base.copyWith(
                  color: context.shellColors.textTertiary,
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
              if (actionLabel case final label?) ...<Widget>[
                const SizedBox(height: 12),
                _ClipboardTextButton(
                  label: label,
                  onPressed: onAction ?? () {},
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ClipboardTextButton extends StatefulWidget {
  const _ClipboardTextButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  State<_ClipboardTextButton> createState() => _ClipboardTextButtonState();
}

class _ClipboardTextButtonState extends State<_ClipboardTextButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    return Semantics(
      button: true,
      label: widget.label,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
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
            decoration: BoxDecoration(
              color: context.shellColors.surfaceContainerHighest,
              borderRadius: theme.borderRadius(11),
              border: Border.all(
                color: _focused
                    ? theme.accent
                    : context.shellColors.hairlineSoft,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
              child: Text(
                widget.label,
                style: ShellText.cardTitle.copyWith(
                  color: context.shellColors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

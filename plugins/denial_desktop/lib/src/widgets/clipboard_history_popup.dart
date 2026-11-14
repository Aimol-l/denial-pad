import 'package:flutter/material.dart'
    show CircularProgressIndicator, Divider, Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:denial_flutter_sdk/effects.dart' show ShellBackdropBlur;
import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/shell_theme.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/tokens.dart';

import '../state/clipboard_tray.dart'
    show ClipboardDataKey, clipboardEntryDataProvider, clipboardImageMimeType;

/// The recent copies, in the popup the shell's tray opens on a tablet.
///
/// The list is the compositor's clipboard history, newest first; a tap puts
/// an entry back on the clipboard and closes the popup. Only [visible] rows
/// are drawn so a long history still fits the panel the popup gives us.
class ClipboardHistoryPopup extends ConsumerWidget {
  const ClipboardHistoryPopup({required this.onClose, super.key});

  final VoidCallback onClose;

  static const int visible = 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(clipboardHistoryProvider);
    final entries = state.entries.take(visible).toList(growable: false);
    final theme = ShellTheme.of(context);
    return SafeArea(
      minimum: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 460),
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
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(
                          Icons.content_paste_rounded,
                          size: 18,
                          color: context.shellColors.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            context.l10n.quickSettingsClipboard,
                            style: ShellText.cardTitle.copyWith(
                              color: context.shellColors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        _CloseButton(onPressed: onClose),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (entries.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        child: Text(
                          state.loading
                              ? context.l10n.commonLoading
                              : state.error != null
                              ? context.l10n.clipboardUnavailableTitle
                              : context.l10n.clipboardEmptyTitle,
                          textAlign: TextAlign.center,
                          style: ShellText.base.copyWith(
                            color: context.shellColors.textSecondary,
                          ),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: entries.length,
                          separatorBuilder: (_, _) => Divider(
                            height: 1,
                            thickness: 1,
                            color: context.shellColors.hairlineSoft,
                          ),
                          itemBuilder: (context, index) => _ClipboardRow(
                            entry: entries[index],
                            onTap: () async {
                              final copied = await ref
                                  .read(clipboardHistoryProvider.notifier)
                                  .activate(entries[index].id);
                              if (copied) onClose();
                            },
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

class _ClipboardRow extends ConsumerWidget {
  const _ClipboardRow({required this.entry, required this.onTap});

  final ClipboardHistoryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final imageMime = clipboardImageMimeType(entry);
    final preview = entry.preview.trim().replaceAll(RegExp(r'\s+'), ' ');
    // An image carries no text preview, so it is named by its kind and size
    // instead of looking like a copy that failed to arrive.
    final title = imageMime != null
        ? l10n.clipboardTypeImage
        : preview.isEmpty
        ? l10n.clipboardPreviewUnavailable
        : preview;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (imageMime != null)
              _ClipboardThumbnail(
                key: ValueKey<int>(entry.id),
                entry: entry,
                mimeType: imageMime,
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.notes_rounded,
                  size: 16,
                  color: context.shellColors.textSecondary,
                ),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: ShellText.base.copyWith(
                      color: context.shellColors.textPrimary,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (imageMime != null) _dimensions(entry),
                      _time(entry.capturedAt),
                      if (entry.sourceTitle.isNotEmpty) entry.sourceTitle,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ShellText.base.copyWith(
                      color: context.shellColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _dimensions(ClipboardHistoryEntry entry) =>
      '${entry.width} × ${entry.height}';

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
  const _ClipboardThumbnail({
    required this.entry,
    required this.mimeType,
    super.key,
  });

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
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(clipboardEntryDataProvider(_key));
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
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

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: SizedBox.square(
        dimension: 28,
        child: Icon(
          Icons.close_rounded,
          size: 18,
          color: context.shellColors.textSecondary,
        ),
      ),
    );
  }
}

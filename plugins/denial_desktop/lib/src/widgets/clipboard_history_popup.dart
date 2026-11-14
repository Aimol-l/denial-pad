import 'package:flutter/material.dart' show Divider, Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:denial_flutter_sdk/effects.dart' show ShellBackdropBlur;
import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/shell_theme.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/tokens.dart';

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

class _ClipboardRow extends StatelessWidget {
  const _ClipboardRow({required this.entry, required this.onTap});

  final ClipboardHistoryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final preview = entry.preview.trim().replaceAll(RegExp(r'\s+'), ' ');
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              _iconFor(entry.kind),
              size: 16,
              color: context.shellColors.textSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    preview.isEmpty
                        ? context.l10n.clipboardEmptyTitle
                        : preview,
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

  static IconData _iconFor(ClipboardHistoryContentKind kind) => switch (kind) {
    ClipboardHistoryContentKind.text => Icons.notes_rounded,
    ClipboardHistoryContentKind.image => Icons.image_outlined,
  };

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

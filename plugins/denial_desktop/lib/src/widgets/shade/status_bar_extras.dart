import 'package:denial_desktop/src/state/system_telemetry.dart';
import 'package:denial_flutter_sdk/models.dart' show DesktopNotification;
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/system_services.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../notification_media.dart' show NotificationAppIcon;
import 'status_glyphs.dart';

/// Whether the radios are all off: airplane mode, as the shade's tile reads it.
bool radiosOff({
  required bool wifiOn,
  required bool bluetoothOn,
  required bool hasModem,
  required bool mobileOn,
}) => !wifiOn && !bluetoothOn && (!hasModem || !mobileOn);

/// Download rate, memory use, the radios and the battery, in the order the
/// bar reads them: ↓ speed · memory · mobile · wifi · bluetooth · battery.
class StatusTelemetry extends ConsumerWidget {
  const StatusTelemetry({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final network = ref.watch(networkConnectivityProvider);
    final bluetooth = ref.watch(bluetoothProvider);
    final mobile =
        ref.watch(mobileNetworkProvider).value ?? const MobileNetworkSnapshot();
    final wifiOn =
        network.snapshot.wirelessEnabled &&
        network.snapshot.wifiDeviceAvailable;
    final bluetoothOn = bluetooth.powered && bluetooth.available;
    final hasModem = mobile.modemPath != null;
    final mobileOn = mobile.enabled;
    final airplane = radiosOff(
      wifiOn: wifiOn,
      bluetoothOn: bluetoothOn,
      hasModem: hasModem,
      mobileOn: mobileOn,
    );
    final connected = network.snapshot.connectedNetwork;
    final rate = ref.watch(downloadSpeedProvider);
    final memory = ref.watch(memoryPercentProvider);
    final battery = ref.watch(batteryProvider);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _Readout(
          icon: Icons.arrow_downward_rounded,
          value: formatDownloadRate(rate),
          color: color,
        ),
        const SizedBox(width: 12),
        _Readout(icon: Icons.memory_rounded, value: '$memory%', color: color),
        if (airplane) ...<Widget>[
          const SizedBox(width: 12),
          Icon(Icons.airplanemode_active_rounded, size: 16, color: color),
        ] else ...<Widget>[
          const SizedBox(width: 12),
          if (mobile.showCellular && (hasModem ? mobileOn : true))
            _MobileMark(color: color, snapshot: mobile),
          if (wifiOn) ...<Widget>[
            const SizedBox(width: 8),
            Icon(
              Icons.wifi_rounded,
              size: 17,
              color: color.withValues(alpha: connected == null ? 0.4 : 1),
            ),
          ],
          if (bluetoothOn) ...<Widget>[
            const SizedBox(width: 8),
            Icon(Icons.bluetooth_rounded, size: 16, color: color),
          ],
        ],
        const SizedBox(width: 10),
        BatteryMark(
          status: battery,
          scale: 1.18,
          textScale: 1.18,
          color: color,
        ),
      ],
    );
  }
}

class _Readout extends StatelessWidget {
  const _Readout({
    required this.icon,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final parts = value.split(' ');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 12, color: color.withValues(alpha: 0.7)),
        const SizedBox(width: 3),
        Text(
          parts.first,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            height: 1,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
        if (parts.length > 1)
          Text(
            ' ${parts.skip(1).join(' ')}',
            style: TextStyle(
              color: color.withValues(alpha: 0.62),
              fontSize: 12,
              height: 1,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
      ],
    );
  }
}

/// The mobile signal and its technology, or a warning when it is unavailable.
class _MobileMark extends StatelessWidget {
  const _MobileMark({required this.color, required this.snapshot});

  final Color color;
  final MobileNetworkSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final signal =
        snapshot.simPresence == MobileSimPresence.present &&
        snapshot.registered &&
        !snapshot.locked;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SignalGlyph(
          active: signal,
          strength: snapshot.strength,
          scale: 1.25,
          color: color,
        ),
        if (snapshot.cellularWorking &&
            snapshot.technology.isNotEmpty) ...<Widget>[
          const SizedBox(width: 3),
          Text(
            snapshot.technology,
            style: TextStyle(
              color: color,
              fontSize: 11,
              height: 1,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        if (!signal) Icon(Icons.priority_high_rounded, size: 12, color: color),
      ],
    );
  }
}

/// App icons of the notifications waiting in the shade, newest first: at most
/// four, then a count.
class StatusNotificationTiles extends ConsumerWidget {
  const StatusNotificationTiles({super.key, required this.color});

  final Color color;

  static const int _maxTiles = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(
      desktopNotificationsProvider.select(
        (state) => (active: state.active, history: state.history),
      ),
    );
    final seen = <String>{};
    final apps = <DesktopNotification>[];
    for (final record in state.history) {
      final notification = record.notification;
      if (state.active[notification.id] == null) {
        continue;
      }
      if (seen.add(notification.appName)) {
        apps.add(notification);
      }
    }
    if (apps.isEmpty) {
      return const SizedBox.shrink();
    }
    final shown = apps.take(_maxTiles).toList(growable: false);
    final more = apps.length - shown.length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final app in shown) ...<Widget>[
          _AppTile(notification: app),
          const SizedBox(width: 4),
        ],
        if (more > 0)
          Text(
            '+$more',
            style: TextStyle(
              color: color.withValues(alpha: 0.65),
              fontSize: 11,
              height: 1,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}

/// One notification's application icon, as the shade draws it: the real
/// desktop-entry icon, rounded to the tile.
class _AppTile extends StatelessWidget {
  const _AppTile({required this.notification});

  final DesktopNotification notification;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: SizedBox.square(
        dimension: 17,
        child: NotificationAppIcon(notification: notification),
      ),
    );
  }
}

/// What the person is listening to, or the newest notification, centred.
class StatusTicker extends ConsumerWidget {
  const StatusTicker({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(mediaPlaybackProvider).value;
    final notifications = ref.watch(
      desktopNotificationsProvider.select(
        (state) => (active: state.active, history: state.history),
      ),
    );
    final (IconData? icon, String text) = switch (playback) {
      final playback?
          when playback.title.isNotEmpty &&
              playback.status == MprisPlaybackStatus.playing =>
        (
          Icons.play_arrow_rounded,
          [
            playback.title,
            if (playback.artists.isNotEmpty) playback.artists.first,
          ].join(' · '),
        ),
      _ => switch (_newest(notifications.active, notifications.history)) {
        final newest? => (
          Icons.notifications_none_rounded,
          '${newest.appName} · ${newest.summary}',
        ),
        _ => (null, ''),
      },
    };
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }
    final muted = color.withValues(alpha: 0.78);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: 14, color: muted),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: TextStyle(color: muted, fontSize: 12, height: 1),
          ),
        ),
      ],
    );
  }

  DesktopNotification? _newest(
    Map<int, DesktopNotification> active,
    List<DesktopNotificationRecord> history,
  ) {
    for (final record in history) {
      final notification = record.notification;
      if (active[notification.id] != null && notification.summary.isNotEmpty) {
        return notification;
      }
    }
    return null;
  }
}

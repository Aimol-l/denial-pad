import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bytes per second received over the last sample, for the status bar.
///
/// `/proc/net/dev` counts bytes per interface since boot; the shell turns two
/// samples a second apart into a rate. Loopback is skipped: it is Denial
/// talking to itself, not the network.
final downloadSpeedProvider = NotifierProvider<DownloadSpeed, int>(
  DownloadSpeed.new,
);

class DownloadSpeed extends Notifier<int> {
  Timer? _timer;
  Map<String, int> _previous = const <String, int>{};
  DateTime? _previousAt;

  @override
  int build() {
    _sample(first: true);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _sample());
    ref.onDispose(() => _timer?.cancel());
    return 0;
  }

  void _sample({bool first = false}) {
    final counters = _readCounters();
    final now = DateTime.now();
    final previous = _previous;
    final previousAt = _previousAt;
    _previous = counters;
    _previousAt = now;
    if (first || previousAt == null || counters.isEmpty) {
      return;
    }
    final seconds = now.difference(previousAt).inMicroseconds / 1000000.0;
    if (seconds <= 0) {
      return;
    }
    var bytes = 0;
    for (final entry in counters.entries) {
      final before = previous[entry.key];
      if (before != null && entry.value >= before) {
        bytes += entry.value - before;
      }
    }
    final rate = (bytes / seconds).round();
    if (rate != state) {
      state = rate;
    }
  }

  /// Received bytes per interface, skipping loopback and containers.
  Map<String, int> _readCounters() {
    try {
      final text = File('/proc/net/dev').readAsStringSync();
      final counters = <String, int>{};
      for (final line in text.split('\n').skip(2)) {
        final colon = line.indexOf(':');
        if (colon <= 0) {
          continue;
        }
        final name = line.substring(0, colon).trim();
        if (name == 'lo' ||
            name.startsWith('docker') ||
            name.startsWith('veth')) {
          continue;
        }
        final fields = line.substring(colon + 1).trim().split(RegExp(r'\s+'));
        if (fields.isEmpty) {
          continue;
        }
        final received = int.tryParse(fields.first);
        if (received != null) {
          counters[name] = received;
        }
      }
      return counters;
    } on Object {
      return const <String, int>{};
    }
  }
}

/// Memory in use as a percentage of the total, for the status bar.
final memoryPercentProvider = NotifierProvider<MemoryPercent, int>(
  MemoryPercent.new,
);

class MemoryPercent extends Notifier<int> {
  Timer? _timer;

  @override
  int build() {
    _sample();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _sample());
    ref.onDispose(() => _timer?.cancel());
    return 0;
  }

  void _sample() {
    try {
      final text = File('/proc/meminfo').readAsStringSync();
      int? total;
      int? available;
      for (final line in text.split('\n')) {
        final fields = line.split(RegExp(r'\s+'));
        if (fields.length < 2) {
          continue;
        }
        final value = int.tryParse(fields[1]);
        if (value == null) {
          continue;
        }
        if (fields[0] == 'MemTotal:') {
          total = value;
        } else if (fields[0] == 'MemAvailable:') {
          available = value;
        }
      }
      if (total == null || total <= 0 || available == null) {
        return;
      }
      final used = ((total - available) * 100 / total).round().clamp(0, 100);
      if (used != state) {
        state = used;
      }
    } on Object {
      return;
    }
  }
}

/// `0 KB/s`, `324 KB/s`, `1.2 MB/s`: one decimal from a megabyte up.
String formatDownloadRate(int bytesPerSecond) {
  if (bytesPerSecond < 1024) {
    return '0 KB/s';
  }
  if (bytesPerSecond < 1024 * 1024) {
    return '${(bytesPerSecond / 1024).round()} KB/s';
  }
  return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
}

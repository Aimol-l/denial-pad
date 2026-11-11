import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:denial_flutter_sdk/applications.dart';
import 'package:denial_flutter_sdk/platform.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_keyboard/denial_keyboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/floating_keyboard_state.dart';

/// Shows the floating keyboard while an application text field has focus.
///
/// This is the host adapter for `plugins/denial_keyboard`: it owns the
/// visibility rules, the panel geometry and the bridge to the compositor's
/// text-input path, and keeps the keyboard package free of shell knowledge.
class KeyboardLayer extends ConsumerStatefulWidget {
  const KeyboardLayer({super.key});

  @override
  ConsumerState<KeyboardLayer> createState() => _KeyboardLayerState();
}

class _KeyboardLayerState extends ConsumerState<KeyboardLayer> {
  StreamSubscription<DenialTextInputState>? _states;
  late final _BridgeBackend _backend;
  late final File _placementFile;
  bool _visible = false;

  /// Set when the user closes the panel by hand; cleared on the next focus.
  bool _dismissed = false;

  /// Panel size and position chosen by the user; null until the first drag or
  /// resize, when the default placement is used.
  ({double width, double height})? _size;
  ({double x, double y})? _position;
  Timer? _saveTimer;
  Rect? _published;

  @override
  void initState() {
    super.initState();
    final bridge = ref.read(denialBridgeProvider);
    _backend = _BridgeBackend(bridge);
    _states = bridge.textInputStates.listen(_onState);
    // The Flutter process is not guaranteed to inherit HOME from the session,
    // so resolve the config directory through the shell's runtime paths.
    _placementFile = File(
      '${ref.read(runtimePathsProvider).configHome}/denial/'
      'keyboard-placement.json',
    );
    unawaited(_restorePlacement());
  }

  void _onState(DenialTextInputState state) {
    if (!mounted) return;
    if (state.active && !_visible) {
      setState(() {
        _visible = true;
        _dismissed = false;
      });
    } else if (!state.active && _visible) {
      setState(() => _visible = false);
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _storePlacement();
    _states?.cancel();
    super.dispose();
  }

  Future<void> _restorePlacement() async {
    final file = _placementFile;
    try {
      if (!await file.exists()) return;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return;
      final size = json['size'];
      final position = json['position'];
      if (size is Map && position is Map) {
        final w = (size['w'] as num?)?.toDouble();
        final h = (size['h'] as num?)?.toDouble();
        final x = (position['x'] as num?)?.toDouble();
        final y = (position['y'] as num?)?.toDouble();
        if (w != null && h != null && x != null && y != null && mounted) {
          setState(() {
            _size = (width: w, height: h);
            _position = (x: x, y: y);
          });
        }
      }
    } on Object {
      // A damaged file falls back to the default placement.
    }
  }

  /// Saves shortly after the last move, so a drag does not rewrite the file on
  /// every frame and a missing pan-end callback cannot lose the placement.
  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), _storePlacement);
  }

  void _storePlacement() {
    final file = _placementFile;
    final size = _size;
    final position = _position;
    if (size == null || position == null) return;
    unawaited(() async {
      try {
        await file.parent.create(recursive: true);
        await file.writeAsString(
          jsonEncode({
            'size': {'w': size.width, 'h': size.height},
            'position': {'x': position.x, 'y': position.y},
          }),
        );
      } on Object {
        // Persistence is best effort.
      }
    }());
  }

  void _publishRect(Rect? rect) {
    if (_published == rect) return;
    _published = rect;
    final container = ProviderScope.containerOf(context, listen: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      container.read(floatingKeyboardRectProvider.notifier).set(rect);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible || _dismissed) {
      _publishRect(null);
      return const SizedBox.shrink();
    }
    final view = MediaQuery.sizeOf(context);
    final screen = (width: view.width, height: view.height);
    final defaultSize = clampPanelSize(
      screen,
      (width: view.width * 0.58, height: view.height * 0.30),
    );
    final size = _size ?? defaultSize;
    final position = clampPanelPosition(
      screen,
      (width: size.width, height: size.height),
      _position ??
          (
            x: (view.width - size.width) / 2,
            y: view.height - size.height - 20,
          ),
    );
    // A drag alone must persist a complete placement, so adopt the effective
    // defaults the first time instead of requiring a resize first.
    _size ??= size;
    _position ??= position;
    _publishRect(
      Rect.fromLTWH(position.x, position.y, size.width, size.height),
    );

    // Offsets are applied to the live fields, not to the values captured by
    // this build: pan updates can arrive faster than the panel rebuilds, and
    // recomputing from a stale base would drop most of the gesture.
    void move(Offset delta) {
      final currentSize = _size ?? size;
      final current = _position ?? position;
      final next = clampPanelPosition(
        screen,
        (width: currentSize.width, height: currentSize.height),
        (x: current.x + delta.dx, y: current.y + delta.dy),
      );
      setState(() => _position = next);
      _scheduleSave();
    }

    void resize(Offset delta) {
      final currentSize = _size ?? size;
      final next = clampPanelSize(
        screen,
        (width: currentSize.width + delta.dx, height: currentSize.height + delta.dy),
      );
      setState(() {
        _size = next;
        _position = _position ?? position;
      });
      _scheduleSave();
    }

    return Positioned(
      left: position.x,
      top: position.y,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) => move(details.delta),
        onPanEnd: (_) => _storePlacement(),
        child: Stack(
          children: [
            KeyboardPanel(
              backend: _backend,
              width: size.width,
              height: size.height,
              onClose: () => setState(() {
                _visible = false;
                _dismissed = true;
              }),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (details) => resize(details.delta),
                onPanEnd: (_) => _storePlacement(),
                child: const SizedBox(
                  width: 48,
                  height: 48,
                  child: Align(
                    alignment: Alignment.bottomRight,
                    child: Padding(
                      padding: EdgeInsets.all(6),
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border(
                              right: BorderSide(color: Color(0x66FFFFFF), width: 2),
                              bottom: BorderSide(color: Color(0x66FFFFFF), width: 2),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BridgeBackend implements KeyboardBackend {
  _BridgeBackend(this._bridge);

  final DenialBridge _bridge;

  @override
  void typeText(String text) => _bridge.sendKeyboardText(text);

  @override
  void pressKey(String name) => _bridge.sendKeyboardKey(name);

  @override
  void replaceText(String replaced, String text) =>
      _bridge.sendKeyboardReplace(replaced, text);
}

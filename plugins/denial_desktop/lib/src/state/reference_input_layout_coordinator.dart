import 'package:flutter/widgets.dart';

import 'package:denial_flutter_sdk/input.dart';

import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/platform.dart';

import 'phone_desk_input.dart';
import 'reference_shell_state.dart';
import 'reference_shell_metrics.dart';

/// Publishes the mobile shell's immutable native input-routing snapshot.
class ReferenceInputLayoutCoordinator {
  ReferenceInputLayoutCoordinator(this._bridge);

  final DenialBridge _bridge;
  int _inputLayoutEpoch = 0;

  /// Beside a desk the phone's layout goes to the composer, from the phone's
  /// origin in the scene.
  Offset _sceneOrigin = Offset.zero;
  PhoneDeskInputComposer? _composer;
  InputLayoutSnapshot? _lastInputLayoutSnapshot;

  void invalidate() {
    _lastInputLayoutSnapshot = null;
  }

  void publish({
    required ReferenceShellState state,
    required Size viewSize,
    required ShellInteractionSnapshot interactions,
    double topInset = 0.0,
    bool appsMoving = false,
    Offset sceneOrigin = Offset.zero,
    PhoneDeskInputComposer? composer,
    Rect? keyboardRect,
  }) {
    if (viewSize.width <= 0 || viewSize.height <= 0) {
      return;
    }
    _sceneOrigin = sceneOrigin;
    _composer = composer;

    final quickSettingsActive = state.quickSettingsEngaged;
    final edgePanelActive =
        state.edgePanelVisible || state.edgePanelDragProgress > 0.0;
    final edgePanelProgress = state.edgePanelDragProgress;
    final edgePanelRect = ReferenceShellMetrics.edgePanelRect(
      viewSize,
      edgePanelProgress,
    );
    if (state.lockLayerVisible) {
      final lockBackgroundWindow = state.primaryWindow;
      _publishInputLayout(
        viewSize: viewSize,
        shellRegions: <Rect>[Offset.zero & viewSize],
        windows: <InputWindowRegion>[
          if (lockBackgroundWindow != null)
            InputWindowRegion(
              window: lockBackgroundWindow,
              rect: Offset.zero & viewSize,
              sourceRect: Offset.zero & viewSize,
              z: 0,
              hitTest: false,
            ),
        ],
        keyboardCapture: true,
        exclusiveShellMode: true,
      );
      return;
    }

    // Denial's own overlay is modal: it takes the touches inside its card's
    // canvas, the shell those around it, and the app none.
    final overlay = state.systemOverlay;
    if (overlay != null) {
      final rect = ReferenceShellMetrics.systemOverlayRect(
        viewSize,
        overlay.geometry!.size,
        edgePanelProgress,
      );
      _publishInputLayout(
        viewSize: viewSize,
        shellRegions: <Rect>[
          Rect.fromLTRB(0, 0, viewSize.width, rect.top),
          Rect.fromLTRB(0, rect.bottom, viewSize.width, viewSize.height),
          Rect.fromLTRB(0, rect.top, rect.left, rect.bottom),
          Rect.fromLTRB(rect.right, rect.top, viewSize.width, rect.bottom),
        ].where((region) => !region.isEmpty).toList(growable: false),
        windows: <InputWindowRegion>[
          InputWindowRegion(
            window: overlay,
            rect: rect,
            sourceRect: Offset.zero & rect.size,
            z: 0,
            geometryLocked: true,
          ),
        ],
      );
      return;
    }

    // An app laid out around the keyboard stays in place, so its input
    // regions do too, and there is no lifted scene for the strip to pan.
    final appLifted = !state.primaryWindowHandlesKeyboard;
    final contentOffset = edgePanelActive && appLifted
        ? (edgePanelRect.height - state.edgePanelViewportScroll)
              .clamp(0.0, edgePanelRect.height)
              .toDouble()
        : 0.0;
    final inputBottom = edgePanelActive
        ? edgePanelRect.top.clamp(0.0, viewSize.height).toDouble()
        : viewSize.height;
    final inputWindow = state.inputWindow;
    final canvas = Offset.zero & viewSize;
    final shellOwnsCanvas =
        inputWindow == null ||
        state.overviewVisible ||
        // While the apps move no app takes a touch, as in Launcher3's
        // recents animation: the shell holds them until they rest.
        appsMoving ||
        state.launchTransitionActive ||
        quickSettingsActive ||
        interactions.capturesFullScene;
    // Two apps side by side: each card takes its own touches, the margins and
    // the gutter stay with the shell's divider. Only a full-shell presentation
    // (recents, the lock layer, a launch, the shade) may take the canvas from
    // them — the keyboard is an overlay, not a reason to drop a pane, or the
    // other pane would stop receiving touches and frames while typing.
    final split = state.onScreenSplit;
    final splitHidden =
        state.overviewVisible ||
        state.lockLayerVisible ||
        state.launchTransitionActive ||
        appsMoving ||
        quickSettingsActive;
    if (split != null && split.isComplete && !splitHidden) {
      final cards =
          splitPaneRects(
                viewSize.width,
                viewSize.height,
                split,
                // The cards in the split stage are drawn below the status bar,
                // whatever the scene hands the single-window path.
                topInset: ReferenceShellMetrics.appStatusInset(viewSize),
              )
              .map(
                (card) =>
                    Rect.fromLTWH(card.left, card.top, card.width, card.height),
              )
              .toList(growable: false);
      final windows = <InputWindowRegion>[];
      for (final (index, windowId) in [split.first, split.second].indexed) {
        final window = state.windowByObjectId(windowId);
        if (window == null) continue;
        windows.addAll(
          _inputRegionsForWindow(
            window: window,
            area: cards[index],
            clip: cards[index],
          ),
        );
      }
      final first = cards[0];
      final second = cards[1];
      // The floating divider lives on the seam; its band belongs to the shell
      // even though the panes below it belong to the clients.
      const seamBand = 28.0;
      final seam = split.vertical
          ? Rect.fromLTWH(
              0,
              first.bottom - seamBand / 2,
              viewSize.width,
              seamBand,
            )
          : Rect.fromLTWH(
              first.right - seamBand / 2,
              first.top,
              seamBand,
              first.height,
            );
      final shellRegions = <Rect>[
        Rect.fromLTRB(0, 0, viewSize.width, first.top),
        // The home swipe belongs to the shell even though a pane owns the
        // space around it: without this strip a pull up from the bottom of a
        // pane goes to the client, and recents never opens from a split.
        ReferenceShellMetrics.gestureRect(viewSize),
        Rect.fromLTRB(0, second.bottom, viewSize.width, viewSize.height),
        Rect.fromLTRB(0, first.top, first.left, first.bottom),
        Rect.fromLTRB(first.right, first.top, second.left, first.bottom),
        Rect.fromLTRB(second.right, first.top, viewSize.width, first.bottom),
        seam.intersect(Offset.zero & viewSize),
      ].where((region) => !region.isEmpty).toList(growable: false);
      _publishInputLayout(
        viewSize: viewSize,
        shellRegions: shellRegions,
        windows: windows,
        softwareKeyboardRegions: <Rect>[?keyboardRect],
        keyboardCapture: quickSettingsActive || interactions.capturesKeyboard,
        exclusiveShellMode: interactions.compositorExclusive,
      );
      return;
    }

    final scrollStripVisible =
        state.edgePanelVisible && (shellOwnsCanvas || appLifted);
    // A landscape view shows no status bar, so over an app its strip lets
    // touches through and claims only a pull down from the top edge.
    final statusEdge = !ReferenceShellMetrics.statusBarShown(viewSize);
    final shellRegions = <Rect>[
      if (shellOwnsCanvas)
        canvas
      else if (edgePanelActive) ...[
        if (!statusEdge) ReferenceShellMetrics.statusRect(viewSize),
        if (edgePanelRect.height > 0.0) edgePanelRect,
        if (scrollStripVisible)
          ReferenceShellMetrics.edgePanelScrollStripRect(viewSize),
      ] else ...[
        if (!statusEdge) ReferenceShellMetrics.statusRect(viewSize),
        ReferenceShellMetrics.gestureRect(viewSize),
      ],
      // Child regions are in scene coordinates.
      for (final region in interactions.childRegions)
        if (!region.shift(-_sceneOrigin).intersect(canvas).isEmpty)
          region.shift(-_sceneOrigin).intersect(canvas),
    ];

    // Back swipes and landscape pull-downs start over the app and are handed
    // to the shell's strips once they move inward. Elsewhere the shell owns
    // the whole canvas.
    final edgeSwipeRegions = shellRegions.contains(canvas)
        ? const <InputEdgeSwipeRegion>[]
        : <InputEdgeSwipeRegion>[
            ..._backGestureRegions(viewSize, inputBottom),
            if (statusEdge)
              InputEdgeSwipeRegion(
                rect: ReferenceShellMetrics.statusRect(viewSize),
                edge: InputEdge.top,
              ),
          ];

    final inputRegions = inputWindow == null
        ? const <InputWindowRegion>[]
        : _inputRegionsForWindow(
            window: inputWindow,
            area: Rect.fromLTWH(
              0,
              topInset,
              viewSize.width,
              (viewSize.height - topInset).clamp(0.0, viewSize.height),
            ),
            clip: Rect.fromLTRB(0, topInset, viewSize.width, inputBottom),
            contentOffset: contentOffset,
          );

    _publishInputLayout(
      viewSize: viewSize,
      shellRegions: shellRegions,
      windows: inputRegions,
      edgeSwipeRegions: edgeSwipeRegions,
      softwareKeyboardRegions: <Rect>[?keyboardRect],
      keyboardCapture: quickSettingsActive || interactions.capturesKeyboard,
      exclusiveShellMode: interactions.compositorExclusive,
    );
  }

  static List<InputEdgeSwipeRegion> _backGestureRegions(
    Size viewSize,
    double bottom,
  ) {
    final strips = ReferenceShellMetrics.backGestureRects(
      viewSize,
      bottom: bottom,
    );
    return <InputEdgeSwipeRegion>[
      if (!strips.left.isEmpty)
        InputEdgeSwipeRegion(rect: strips.left, edge: InputEdge.left),
      if (!strips.right.isEmpty)
        InputEdgeSwipeRegion(rect: strips.right, edge: InputEdge.right),
    ];
  }

  List<InputWindowRegion> _inputRegionsForWindow({
    required DenialWindow window,
    required Rect area,
    required Rect clip,
    double contentOffset = 0,
  }) {
    final frame = window.presentationCoordinateRect;
    final content = window.contentCoordinateRect;
    if (frame.isEmpty || content.isEmpty) {
      return const <InputWindowRegion>[];
    }
    // Match the texture's top-centred BoxFit.cover, including the interval
    // between an output configure and the client's replacement buffer.
    final widthScale = area.width / frame.width;
    final heightScale = area.height / frame.height;
    final scale = widthScale > heightScale ? widthScale : heightScale;
    final frameLeft = area.left + (area.width - frame.width * scale) / 2.0;
    final frameTop = area.top - contentOffset;
    final fullContentRect = Rect.fromLTWH(
      frameLeft,
      frameTop,
      frame.width * scale,
      frame.height * scale,
    );
    final clientRect = Rect.fromLTWH(
      frameLeft + (content.left - frame.left) * scale,
      frameTop + (content.top - frame.top) * scale,
      content.width * scale,
      content.height * scale,
    );
    final rect = clientRect.intersect(clip);
    if (rect.isEmpty) {
      return const <InputWindowRegion>[];
    }
    final sourceRect = Rect.fromLTWH(
      content.left + (rect.left - clientRect.left) / scale,
      content.top + (rect.top - clientRect.top) / scale,
      rect.width / scale,
      rect.height / scale,
    );
    final regions = <InputWindowRegion>[];
    for (final popup in window.popupRootsFrontToBack) {
      final popupRect = window.mapSurfaceRect(popup, fullContentRect);
      final clipped = popupRect.intersect(rect);
      if (clipped.isEmpty ||
          popupRect.width <= 0.0 ||
          popupRect.height <= 0.0) {
        continue;
      }
      final scaleX = popup.surfaceWidth / popupRect.width;
      final scaleY = popup.surfaceHeight / popupRect.height;
      regions.add(
        InputWindowRegion(
          window: window,
          surfaceId: popup.surfaceId,
          rect: clipped,
          sourceRect: Rect.fromLTWH(
            (clipped.left - popupRect.left) * scaleX,
            (clipped.top - popupRect.top) * scaleY,
            clipped.width * scaleX,
            clipped.height * scaleY,
          ),
          z: popup.compositionOrder + 1,
          geometryLocked: true,
        ),
      );
    }
    regions.add(
      InputWindowRegion(
        window: window,
        // Route through the toplevel root so native hit testing can select an
        // input-capable subsurface rather than the current primary texture.
        surfaceId: window.objectId,
        rect: rect,
        sourceRect: sourceRect,
        z: 0,
        geometryLocked: true,
      ),
    );
    return regions;
  }

  void _publishInputLayout({
    required Size viewSize,
    required List<Rect> shellRegions,
    required List<InputWindowRegion> windows,
    List<Rect> softwareKeyboardRegions = const <Rect>[],
    List<InputEdgeSwipeRegion> edgeSwipeRegions =
        const <InputEdgeSwipeRegion>[],
    bool keyboardCapture = false,
    bool exclusiveShellMode = false,
  }) {
    if (viewSize.width <= 0 || viewSize.height <= 0) {
      return;
    }

    final visibleSurfaceIds = <int>{};
    DenialWindow? previousWindow;
    for (final region in windows) {
      // Popup regions share their toplevel's complete surface tree. Traverse
      // it once for adjacent regions instead of once per popup.
      if (!identical(region.window, previousWindow)) {
        visibleSurfaceIds.addAll(region.window.visibleSurfaceIds);
        previousWindow = region.window;
      }
    }
    final snapshot = InputLayoutSnapshot(
      epoch: _inputLayoutEpoch + 1,
      shellRegions: shellRegions,
      windows: windows,
      softwareKeyboardRegions: softwareKeyboardRegions,
      edgeSwipeRegions: edgeSwipeRegions,
      visibleSurfaceIds: visibleSurfaceIds.toList(growable: false),
      keyboardCapture: keyboardCapture,
      exclusiveShellMode: exclusiveShellMode,
      mobilePresentation: true,
    );
    if (_lastInputLayoutSnapshot?.hasSameRoutingAs(snapshot) ?? false) {
      return;
    }

    final composer = _composer;
    if (!(composer?.publishPhone(snapshot, _sceneOrigin) ??
        _bridge.publishInputLayout(snapshot))) {
      return;
    }
    _inputLayoutEpoch = snapshot.epoch;
    _lastInputLayoutSnapshot = snapshot;
  }
}

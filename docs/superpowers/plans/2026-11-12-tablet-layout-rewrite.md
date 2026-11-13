# 平板布局外壳重写 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让平板外壳复用桌面外壳的「几何由合成器持有」模型：窗口矩形来自合成器的 split 数学（含最小尺寸），外壳只按几何 1:1 绘制与映射输入，分屏不再缩放内容。

**Architecture:** 合成器新增 `mobile_layout` 纯模块，复用 `window_layout` 已有的 `split_geometry_on_axis_with_minimums`（一次实现，桌面与平板共用）。最小尺寸经 wire 发布给外壳；外壳在建立分屏前判定可行性（50:50 放不下就拒绝并提示），建立后窄条分割条只在可行比例区间内拖动。外壳删除 `BoxFit` 适配，输入区域直接由几何推导。

**Tech Stack:** Rust / Smithay（`cargo test`）、FlatBuffers（`protocol/denial.fbs` + `tools/generate-denial-wire`）、Dart / Flutter（`denial_flutter_sdk` + `denial_desktop`，纯 Dart 测试用 `dart test`）。

**Spec:** `docs/superpowers/specs/2026-11-12-tablet-layout-shell.md`（v0.3.0）

## Global Constraints

- 只改 mobile shell 路径；桌面布局与工作区行为不得回归（`cargo test` 现有 681 个测试全绿）。
- 方向由输出宽高比决定；状态栏 45 逻辑像素由合成器扣除，窗格在状态栏以下。
- 窗格之间**没有几何间隙**（`gap = 0`），两个客户端矩形相接。
- 默认比例 50:50；分割条可在 20–80% 内拖动，但必须满足两侧最小尺寸；±3% 吸附 50:50。
- 50:50 放不下任一侧的最小尺寸时**拒绝分屏**并提示「该应用最小需要 W×H」，不缩放内容。
- 外壳不得对窗口内容做 `BoxFit` 适配；绘制矩形 = `window.geometry`。
- 分屏内两侧强制 1.0 倍应用缩放，退出恢复各自设置。
- 成员关闭时另一侧直接全屏（分屏结束）。
- 调试日志由 `DENIAL_SPLIT_DEBUG=1` 控制，默认关闭。
- 提交信息使用 conventional commit；不 push。

## Review Focus

- 客户端声明最小尺寸后，**改变比例**（窄条拖动）必须在最小尺寸处停住，不能靠缩小内容“凑合”。
- 50:50 放不下时，**放置区/选择器**要给出可读原因，且拖放要回弹，不能建立半个分屏。
- 客户端**滞后一帧**提交尺寸时，界面不得闪回旧尺寸、也不得永久卡在旧尺寸。
- **旋转**后若新轴不满足最小尺寸，要按规范拒绝并回到单应用，不能留下溢出/黑边。
- 分屏中关闭一侧后，另一侧必须**立即全屏**，不能留下空窗格或选择器。

---

### Task 1: 共享 split 数学与 mobile 几何纯函数

**Files:**
- Modify: `compositor/src/bin/deniald/window_layout.rs`（`LayoutAxis`、`split_geometry_on_axis_with_minimums`、`resolved_split_axis` 提升为 `pub(super)`）
- Create: `compositor/src/bin/deniald/wayland_frontend/mobile_layout.rs`
- Create: `compositor/src/bin/deniald/wayland_frontend/mobile_layout/tests.rs`
- Modify: `compositor/src/bin/deniald/wayland_frontend.rs`（`mod mobile_layout;`）

**Interfaces:**
- Consumes: `crate::window_layout::{LayoutAxis, split_geometry_on_axis_with_minimums}`
- Produces:
  - `mobile_layout::pane_rects(full: Rectangle<i32, Logical>, vertical: bool, ratio: f64, first_min: Size<i32, Logical>, second_min: Size<i32, Logical>) -> [Rectangle<i32, Logical>; 2]`
  - `mobile_layout::fits(full: Rectangle<i32, Logical>, vertical: bool, first_min: Size<i32, Logical>, second_min: Size<i32, Logical>) -> bool`
  - `mobile_layout::ratio_bounds(full: Rectangle<i32, Logical>, vertical: bool, first_min: Size<i32, Logical>, second_min: Size<i32, Logical>) -> Option<(f64, f64)>`

- [ ] **Step 1: 写失败测试**

`compositor/src/bin/deniald/wayland_frontend/mobile_layout/tests.rs`：

```rust
use super::*;
use smithay::utils::{Logical, Rectangle, Size};

fn full() -> Rectangle<i32, Logical> {
    Rectangle::new((0, 45).into(), (1600, 955).into())
}

fn min(width: i32, height: i32) -> Size<i32, Logical> {
    Size::from((width, height))
}

#[test]
fn an_unconstrained_pair_splits_the_screen_in_half() {
    let [first, second] = pane_rects(full(), false, 0.5, min(1, 1), min(1, 1));
    assert_eq!(first, Rectangle::new((0, 45).into(), (800, 955).into()));
    assert_eq!(second, Rectangle::new((800, 45).into(), (800, 955).into()));
}

#[test]
fn the_ratio_never_undersizes_either_client() {
    let [first, second] = pane_rects(full(), false, 0.3, min(900, 1), min(600, 1));
    assert_eq!(first.size.w, 900);
    assert_eq!(second.size.w, 700);
}

#[test]
fn a_pair_that_cannot_fit_is_refused() {
    assert!(fits(full(), false, min(900, 1), min(800, 1)) == false);
    assert!(fits(full(), false, min(900, 1), min(700, 1)) == true);
}

#[test]
fn ratio_bounds_report_the_draggable_interval() {
    let (low, high) = ratio_bounds(full(), false, min(700, 1), min(600, 1)).unwrap();
    assert!((low - 0.4375).abs() < 1e-6, "{low}");
    assert!((high - 0.625).abs() < 1e-6, "{high}");
    assert_eq!(ratio_bounds(full(), false, min(900, 1), min(800, 1)), None);
}

#[test]
fn portrait_uses_the_short_side() {
    let tall = Rectangle::new((0, 45).into(), (800, 1200).into());
    let [first, second] = pane_rects(tall, true, 0.5, min(1, 1), min(1, 1));
    assert_eq!(first.size.h, 600);
    assert_eq!(second.loc.y, 45 + 600);
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
cd compositor && CARGO_TARGET_DIR=$HOME/.cache/denial/pc-build/rust \
  cargo test --locked --features flutter --bin deniald mobile_layout
```
Expected: 编译失败（`pane_rects` 未定义）。

- [ ] **Step 3: 实现（复用桌面 split 数学，不复制）**

`compositor/src/bin/deniald/wayland_frontend/mobile_layout.rs`：

```rust
//! The two panes a phone screen is split into.
//!
//! The rectangles themselves come from the desktop layout's split math so the
//! tablet and the desk cannot drift apart: same axis rules, same minimum-size
//! clamping, same rounding.

use smithay::utils::{Logical, Rectangle, Size};

use crate::window_layout::{LayoutAxis, split_geometry_on_axis_with_minimums};

pub(super) fn pane_rects(
    full: Rectangle<i32, Logical>,
    vertical: bool,
    ratio: f64,
    first_min: Size<i32, Logical>,
    second_min: Size<i32, Logical>,
) -> [Rectangle<i32, Logical>; 2] {
    let axis = if vertical {
        LayoutAxis::Vertical
    } else {
        LayoutAxis::Horizontal
    };
    let (first, second) =
        split_geometry_on_axis_with_minimums(full, 0, ratio, first_min, second_min, axis);
    [first, second]
}

/// Whether a 50:50 split can host both clients at their minimum size.
pub(super) fn fits(
    full: Rectangle<i32, Logical>,
    vertical: bool,
    first_min: Size<i32, Logical>,
    second_min: Size<i32, Logical>,
) -> bool {
    ratio_bounds(full, vertical, first_min, second_min).is_some()
}

/// The ratio interval that keeps both clients at or above their minimum size,
/// intersected with the draggable range.
pub(super) fn ratio_bounds(
    full: Rectangle<i32, Logical>,
    vertical: bool,
    first_min: Size<i32, Logical>,
    second_min: Size<i32, Logical>,
) -> Option<(f64, f64)> {
    let extent = if vertical { full.size.h } else { full.size.w }.max(2) as f64;
    let first = if vertical { first_min.h } else { first_min.w }.max(1) as f64;
    let second = if vertical { second_min.h } else { second_min.w }.max(1) as f64;
    if first + second > extent {
        return None;
    }
    let low = (first / extent).max(0.2);
    let high = (1.0 - second / extent).min(0.8);
    (low <= high).then_some((low, high))
}

#[cfg(test)]
#[path = "mobile_layout/tests.rs"]
mod tests;
```

`window_layout.rs` 把三项改为 `pub(super)`（同 crate 可见）：`enum LayoutAxis`、`fn resolved_split_axis`、`fn split_geometry_on_axis_with_minimums`。

`wayland_frontend.rs` 增加 `mod mobile_layout;`。

- [ ] **Step 4: 运行测试确认通过**

```bash
cd compositor && CARGO_TARGET_DIR=$HOME/.cache/denial/pc-build/rust \
  cargo test --locked --features flutter --bin deniald mobile_layout
```
Expected: `5 passed`，且全量 `cargo test` 仍为 `681 + 5`。

- [ ] **Step 5: 提交**

```bash
git add compositor/src/bin/deniald/window_layout.rs \
  compositor/src/bin/deniald/wayland_frontend.rs \
  compositor/src/bin/deniald/wayland_frontend/mobile_layout.rs \
  compositor/src/bin/deniald/wayland_frontend/mobile_layout/tests.rs
git commit -m "refactor(layout): share split math with the phone panes"
```

---

### Task 2: 手机几何改用共享数学并夹紧比例

**Files:**
- Modify: `compositor/src/bin/deniald/wayland_frontend/mobile_split.rs`（删除自带的 `split_rects`/`SPLIT_*` 常量，改调 `mobile_layout::pane_rects`）
- Modify: `compositor/src/bin/deniald/wayland_frontend/insets.rs`（`mobile_window_geometry` 的分屏分支）
- Modify: `compositor/src/bin/deniald/wayland_frontend/mobile_split/tests.rs`

**Interfaces:**
- Consumes: `mobile_layout::{pane_rects, fits, ratio_bounds}`
- Produces: `MobileSplit::pane(&self, window_id: u64, full: Rectangle<i32, Logical>, first_min: Size<i32, Logical>, second_min: Size<i32, Logical>) -> Option<Rectangle<i32, Logical>>`

- [ ] **Step 1: 更新失败测试**

`mobile_split/tests.rs` 里针对 `split_rects` 的用例改为：

```rust
#[test]
fn panes_tile_the_screen_with_no_gap() {
    let [left, right] = split_rects(full(), false, 0.5, min(1, 1), min(1, 1));
    assert_eq!(left.size.w + right.size.w, full().size.w);
    assert_eq!(left.loc.x + left.size.w, right.loc.x);
}
```

- [ ] **Step 2: 运行确认失败**

```bash
cd compositor && CARGO_TARGET_DIR=$HOME/.cache/denial/pc-build/rust \
  cargo test --locked --features flutter --bin deniald mobile_split
```
Expected: 编译失败（`split_rects` 签名不符）。

- [ ] **Step 3: 实现**

`mobile_split.rs`：

```rust
pub(super) fn split_rects(
    full: Rectangle<i32, Logical>,
    vertical: bool,
    ratio: f32,
    first_min: Size<i32, Logical>,
    second_min: Size<i32, Logical>,
) -> [Rectangle<i32, Logical>; 2] {
    super::mobile_layout::pane_rects(full, vertical, f64::from(ratio), first_min, second_min)
}
```

`insets.rs` 的 `mobile_window_geometry` 分屏分支传入两个客户端的最小尺寸：

```rust
let minimums = self.mobile_split_minimums();
if let Some(split) = self.mobile_split
    && let Some(window_id) = self.surface_id(&root)
    && let Some(pane) = split.pane(window_id, geometry, minimums.0, minimums.1)
{
    return Some(pane);
}
```

`mobile_split_minimums()` 读 `ManagedWindow::new(window).facts().minimum_size`（桌面已在用，无需新接口）；未找到时退回 `Size::from((1, 1))`。

- [ ] **Step 4: 运行确认通过**

```bash
cd compositor && DENIAL_FCITX_TEST_BUS=1 CARGO_TARGET_DIR=$HOME/.cache/denial/pc-build/rust \
  dbus-run-session -- cargo test --locked --features flutter --bin deniald
```
Expected: 全绿（681 + 新增用例），包含既有的 `window_geometry_intent_tests`（重试次数/取整容忍的行为在这里锁定）。

- [ ] **Step 5: 提交**

```bash
git add compositor/src/bin/deniald/wayland_frontend/mobile_split.rs \
  compositor/src/bin/deniald/wayland_frontend/mobile_split/tests.rs \
  compositor/src/bin/deniald/wayland_frontend/insets.rs
git commit -m "feat(split): clamp phone panes to the clients' minimum sizes"
```

---

### Task 3: 把最小尺寸发布给外壳

**Files:**
- Modify: `protocol/denial.fbs`（`WindowDescription` 增加 `min_width: float;` `min_height: float;`）
- Modify: `protocol/generated/rust/denial_generated.rs`、`protocol/generated/dart/lib/denial_denial.wire_generated.dart`（生成）
- Modify: `compositor/src/bin/deniald/wire.rs`（`WindowDescription` 字段）
- Modify: `compositor/src/bin/deniald/wire/encode.rs`
- Modify: `compositor/src/bin/deniald/wayland_frontend/surface_pipeline.rs`（填值）
- Modify: `packages/denial_flutter_sdk/lib/src/platform/denial_wire.dart`（读字段）
- Modify: `packages/denial_flutter_sdk/lib/src/models/denial_window.dart`（`minWidth`/`minHeight`）
- Test: `compositor/src/bin/deniald/wire/tests.rs`、`packages/denial_flutter_sdk/test/window_minimum_test.dart`

**Interfaces:**
- Produces: `DenialWindow.minWidth` / `minHeight`（double，逻辑像素，已含应用缩放）；wire 字段 `min_width`/`min_height`。

- [ ] **Step 1: 写失败测试**

`packages/denial_flutter_sdk/test/window_minimum_test.dart`：

```dart
import 'package:denial_flutter_sdk/models.dart';
import 'package:test/test.dart';

void main() {
  test('a window reports the minimum size its client declared', () {
    final window = denialWindowFixture(minWidth: 638.0, minHeight: 120.0);
    expect(window.minWidth, 638.0);
    expect(window.minHeight, 120.0);
  });
}
```

夹具放在 `packages/denial_flutter_sdk/test/support/window_fixture.dart`：

```dart
import 'package:denial_flutter_sdk/models.dart';

DenialWindow denialWindowFixture({
  double minWidth = 1,
  double minHeight = 1,
}) => DenialWindow(
  objectId: 1,
  objectKind: 'window',
  surfaceId: 1,
  windowId: 1,
  textureId: 1,
  title: 'fixture',
  appId: 'test.app',
  width: 800,
  height: 600,
  surfaceX: 0,
  surfaceY: 0,
  surfaceWidth: 800,
  surfaceHeight: 600,
  textureSourceX: 0,
  textureSourceY: 0,
  textureSourceWidth: 800,
  textureSourceHeight: 600,
  geometryX: 0,
  geometryY: 0,
  geometryWidth: 800,
  geometryHeight: 600,
  monitorId: 0,
  workspaceId: 1,
  transientParentObjectId: null,
  minimized: false,
  fullscreen: false,
  maximized: false,
  transform: 0,
  scale120: 120,
  pinned: false,
  suppressAnimations: false,
  restoredAcrossFlutterRestart: false,
  serverSideDecorated: false,
  opacity: 1,
  statusColorArgb: null,
  contentX: 0,
  contentY: 0,
  contentWidth: 800,
  contentHeight: 600,
  surfaceLayers: const [],
  clientTexture: null,
  contentKind: DenialWindowContentKind.texture,
  opacityClass: DenialWindowOpacityClass.opaque,
  minWidth: minWidth,
  minHeight: minHeight,
);
```

构造参数以 `denial_window.dart` 现有字段为准；执行时若参数名有出入，以该文件为准补齐。

- [ ] **Step 2: 运行确认失败**

```bash
cd packages/denial_flutter_sdk && \
  ~/.cache/denial/pc-dependencies/flutter/bin/dart test test/window_minimum_test.dart
```
Expected: 编译失败（`minWidth` 未定义）。

- [ ] **Step 3: 生成 wire 并接线**

```bash
cd /home/aimol/Documents/Workspace/denial-pad
FLATC=$PWD/compositor/target/flatbuffers/src/flatc ./tools/generate-denial-wire
```

- `wire.rs`：`pub min_width: f64, pub min_height: f64,`
- `encode.rs`：`min_width: description.min_width, min_height: description.min_height,`
- `surface_pipeline.rs`：填 `f64::from(minimums.0.w)` / `.h`（`ManagedWindowFacts::minimum_size` 已是逻辑像素）。
- `denial_wire.dart`：读取 `description.minWidth` / `minHeight`（flatbuffers Dart 生成的 getter 名为 `minWidth`/`minHeight`）。
- `denial_window.dart`：新增 `final double minWidth; final double minHeight;` 并接入构造函数、`copyWith`、`==`/`hashCode`。

- [ ] **Step 4: 运行确认通过**

```bash
cd compositor && DENIAL_FCITX_TEST_BUS=1 CARGO_TARGET_DIR=$HOME/.cache/denial/pc-build/rust \
  dbus-run-session -- cargo test --locked --features flutter --bin deniald wire::
cd ../packages/denial_flutter_sdk && \
  ~/.cache/denial/pc-dependencies/flutter/bin/dart test test/window_minimum_test.dart
```
Expected: 两个测试都通过。

- [ ] **Step 5: 提交**

```bash
git add protocol compositor/src/bin/deniald/wire.rs compositor/src/bin/deniald/wire/encode.rs \
  compositor/src/bin/deniald/wayland_frontend/surface_pipeline.rs \
  packages/denial_flutter_sdk/lib packages/denial_flutter_sdk/test
git commit -m "feat(wire): publish each window's minimum size"
```

---

### Task 4: 外壳拒绝放不下的分屏

**Files:**
- Modify: `packages/denial_flutter_sdk/lib/src/models/split_pair.dart`（`splitFits` / `splitRatioBounds`）
- Test: `packages/denial_flutter_sdk/test/split_pair_test.dart`
- Modify: `plugins/denial_desktop/lib/src/state/reference_shell_controller.dart`（`beginSingleSplit`、`pickSplitSecond` 返回 `bool`）
- Modify: `plugins/denial_desktop/lib/src/widgets/overview/app_deck_layer.dart`（拒绝后回弹、文案）
- Modify: `plugins/denial_desktop/lib/src/widgets/overview/split_drop_zone.dart`（显示最小尺寸）
- Modify: `plugins/denial_desktop/lib/src/widgets/overview/split_picker.dart`（置灰 + 原因）

**Interfaces:**
- Consumes: `DenialWindow.minWidth/minHeight`
- Produces:
  - `bool splitFits({required double width, required double height, required double topInset, required SplitPair pair, required Size firstMin, required Size secondMin, required bool vertical})`
  - `({double min, double max})? splitRatioBounds({required double extent, required double firstMin, required double secondMin})`
  - `ReferenceShellController.beginSingleSplit(...) -> bool`（`false` 表示被拒绝）

- [ ] **Step 1: 写失败测试**

```dart
test('a split is refused when both minimums cannot fit', () {
  expect(
    splitRatioBounds(extent: 1600, firstMin: 900, secondMin: 800),
    isNull,
  );
  final bounds = splitRatioBounds(extent: 1600, firstMin: 700, secondMin: 600)!;
  expect(bounds.min, closeTo(0.4375, 1e-9));
  expect(bounds.max, closeTo(0.625, 1e-9));
});
```

- [ ] **Step 2: 运行确认失败**

```bash
cd packages/denial_flutter_sdk && \
  ~/.cache/denial/pc-dependencies/flutter/bin/dart test test/split_pair_test.dart
```

- [ ] **Step 3: 实现**

```dart
bool splitFits({
  required double width,
  required double height,
  required double topInset,
  required SplitPair pair,
  required Size firstMin,
  required Size secondMin,
  required bool vertical,
}) {
  final extent = vertical ? height - topInset : width;
  final first = vertical ? firstMin.height : firstMin.width;
  final second = vertical ? secondMin.height : secondMin.width;
  return splitRatioBounds(extent: extent, firstMin: first, secondMin: second) !=
      null;
}

({double min, double max})? splitRatioBounds({
  required double extent,
  required double firstMin,
  required double secondMin,
  double minRatio = 0.2,
  double maxRatio = 0.8,
}) {
  final span = extent <= 0 ? 1.0 : extent;
  final first = firstMin.clamp(1.0, span / 2 + span);
  final second = secondMin.clamp(1.0, span / 2 + span);
  if (first + second > span) return null;
  final low = (first / span).clamp(minRatio, maxRatio);
  final high = (1 - second / span).clamp(minRatio, maxRatio);
  return low <= high ? (min: low, max: high) : null;
}
```

控制器：`beginSingleSplit` 在建立前用 `splitRatioBounds(extent: 屏幕短边, firstMin: ..., secondMin: ...)` 判定，`null` 时返回 `false` 且不改状态；`pickSplitSecond` 同样，在 `pair.filled` 之前判定另一侧。

放置区：被拒绝时该侧不亮、文案改为「该应用最小需要 W×H」；`AppDeckLayer._pickupEnd` 在 `onSplitSide` 返回 `false` 时把卡片弹回。

选择器：候选卡片 `Opacity(0.4)` + 副标题原因，`onTap` 为 null。

- [ ] **Step 4: 运行确认通过**

```bash
cd packages/denial_flutter_sdk && \
  ~/.cache/denial/pc-dependencies/flutter/bin/dart test test/split_pair_test.dart
cd ../../plugins/denial_desktop && \
  PATH=~/.cache/denial/pc-dependencies/flutter/bin:$PATH flutter analyze lib
```
Expected: 测试通过、静态检查无问题。

- [ ] **Step 5: 设备验证**

1. Firefox 应用缩放设为 1.5 倍（设置里改），recents 里把它拖到左侧：**应被拒绝**并显示「该应用最小需要 957×932」。
2. 缩放改回 1.0 后重复：应正常进入分屏。

- [ ] **Step 6: 提交**

```bash
git add packages/denial_flutter_sdk/lib/src/models/split_pair.dart \
  packages/denial_flutter_sdk/test/split_pair_test.dart \
  plugins/denial_desktop/lib/src/state/reference_shell_controller.dart \
  plugins/denial_desktop/lib/src/widgets/overview/app_deck_layer.dart \
  plugins/denial_desktop/lib/src/widgets/overview/split_drop_zone.dart \
  plugins/denial_desktop/lib/src/widgets/overview/split_picker.dart
git commit -m "feat(split): refuse a split the clients cannot fit"
```

---

### Task 5: 1:1 渲染、几何输入与调试开关

**Files:**
- Modify: `plugins/denial_desktop/lib/src/features/mobile/mobile_split_stage.dart`（去掉 `fit: BoxFit.contain`）
- Create: `plugins/denial_desktop/lib/src/state/split_debug.dart`
- Modify: `plugins/denial_desktop/lib/src/state/reference_input_layout_coordinator.dart`（确认只用几何）

**Interfaces:**
- Produces: `void splitDebug(String message)`（`DENIAL_SPLIT_DEBUG=1` 时 `debugPrint`）。

- [ ] **Step 1: 写失败测试（纯函数）**

在 `packages/denial_flutter_sdk/test/split_pair_test.dart`：

```dart
test('panes fill the screen exactly once the ratio is applied', () {
  const pair = SplitPair(first: 1, second: 2, vertical: false, ratio: 0.5);
  final [left, right] = splitPaneRects(1600, 1000, pair, topInset: 45);
  expect(left.width + right.width, 1600);
  expect(left.left + left.width, right.left);
});
```

- [ ] **Step 2: 运行（应已通过，锁住行为）**

```bash
cd packages/denial_flutter_sdk && \
  ~/.cache/denial/pc-dependencies/flutter/bin/dart test test/split_pair_test.dart
```

- [ ] **Step 3: 实现**

`mobile_split_stage.dart`：`WindowContentRect(window: window, active: active)`（删掉 `fit` 参数）。

`split_debug.dart`：

```dart
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';

final bool _enabled = Platform.environment['DENIAL_SPLIT_DEBUG'] == '1';

void splitDebug(String message) {
  if (_enabled) debugPrint('split: $message');
}
```

在 stage 的 `pane()` 里记录一次尺寸（`window.geometryWidth/Height` 与 pane 矩形），在 `updateSplitRatio` 里记录夹紧结果。

- [ ] **Step 4: 设备验证**

1. 全屏打开 Firefox/终端/文本编辑器：文字为原始大小，点击位置准确。
2. `DENIAL_SPLIT_DEBUG=1` 启动（临时 `systemctl edit` 或 `denial-session` 环境），分屏后日志出现每个窗格的几何/最小尺寸。

- [ ] **Step 5: 提交**

```bash
git add plugins/denial_desktop/lib/src/features/mobile/mobile_split_stage.dart \
  plugins/denial_desktop/lib/src/state/split_debug.dart \
  plugins/denial_desktop/lib/src/state/reference_input_layout_coordinator.dart \
  packages/denial_flutter_sdk/test/split_pair_test.dart
git commit -m "feat(split): draw panes at their geometry and log the numbers"
```

---

### Task 6: 窄条分割条

**Files:**
- Create: `plugins/denial_desktop/lib/src/widgets/overview/split_divider.dart`
- Modify: `plugins/denial_desktop/lib/src/features/mobile/mobile_split_stage.dart`
- Modify: `plugins/denial_desktop/lib/src/state/reference_shell_controller.dart`（`updateSplitRatio` 夹紧）
- Test: `packages/denial_flutter_sdk/test/split_pair_test.dart`（`splitFractions` 吸附已有用例，补边界）

**Interfaces:**
- Consumes: `splitRatioBounds`
- Produces: `SplitDivider({required SplitPair pair, required List<Rect> panes, required double minRatio, required double maxRatio, required ValueChanged<double> onRatio, required VoidCallback onReset})`

- [ ] **Step 1: 写失败测试**

```dart
test('a dragged ratio snaps back into the feasible band', () {
  final bounds = splitRatioBounds(extent: 1600, firstMin: 700, secondMin: 600)!;
  expect(splitFractions((bounds.min - 0.1).clamp(0.0, 1.0)).first, bounds.min);
});
```

- [ ] **Step 2: 运行确认失败**

```bash
cd packages/denial_flutter_sdk && \
  ~/.cache/denial/pc-dependencies/flutter/bin/dart test test/split_pair_test.dart
```

- [ ] **Step 3: 实现**

```dart
class SplitDivider extends StatefulWidget {
  const SplitDivider({
    super.key,
    required this.vertical,
    required this.line,
    required this.hitWidth,
    required this.ratio,
    required this.minRatio,
    required this.maxRatio,
    required this.onRatio,
    required this.onReset,
  });
  // ...
}
```

- 视觉：`1.5px` 的 `Color(0x336D5BD0)` 线，贯穿交叉轴；
- 命中：`Positioned` 宽度 28（竖屏高度 28），`MouseRegion(cursor: resizable)`；
- 拖动：`onHorizontalDragUpdate/onVerticalDragUpdate` → `ratio = (local / extent).clamp(minRatio, maxRatio)` → `onRatio`；
- 吸附：靠近 0.5 的 ±3% 用 `splitFractions`（已有）；
- 气泡：拖动时在把手上方显示 `62 : 38`（`IgnorePointer`，仅视觉）；
- 双击：`onReset`。

`updateSplitRatio` 用 bounds 夹紧后再写入状态与合成器。

- [ ] **Step 4: 运行 + 设备验证**

```bash
cd packages/denial_flutter_sdk && \
  ~/.cache/denial/pc-dependencies/flutter/bin/dart test test/split_pair_test.dart
```
设备：分屏后拖动窄条，观察两侧 1:1 缩放；拖到最小尺寸处停住；双击回到 50:50；旋转后窄条方向正确。

- [ ] **Step 5: 提交**

```bash
git add plugins/denial_desktop/lib/src/widgets/overview/split_divider.dart \
  plugins/denial_desktop/lib/src/features/mobile/mobile_split_stage.dart \
  plugins/denial_desktop/lib/src/state/reference_shell_controller.dart \
  packages/denial_flutter_sdk/test/split_pair_test.dart
git commit -m "feat(split): a narrow divider clamped to both minimums"
```

---

### Task 7: 成员关闭后另一侧全屏

**Files:**
- Modify: `plugins/denial_desktop/lib/src/state/reference_shell_controller.dart`（窗口列表变化时处理）
- Modify: `plugins/denial_desktop/lib/src/state/reference_shell_state.dart`（若需要 `splitSurvivor`）
- Test: `packages/denial_flutter_sdk/test/split_pair_test.dart`（纯函数 `pairSurvivor`）

**Interfaces:**
- Produces: `int pairSurvivor(SplitPair pair, int closedWindowId)` → 0 表示没有幸存者。

- [ ] **Step 1: 写失败测试**

```dart
test('closing one side leaves the other as the survivor', () {
  const pair = SplitPair(first: 3, second: 5, vertical: false);
  expect(pairSurvivor(pair, 3), 5);
  expect(pairSurvivor(pair, 5), 3);
  expect(pairSurvivor(pair, 9), 0);
});
```

- [ ] **Step 2: 运行确认失败**

- [ ] **Step 3: 实现**

```dart
int pairSurvivor(SplitPair pair, int closedWindowId) {
  if (closedWindowId == pair.first) return pair.second;
  if (closedWindowId == pair.second) return pair.first;
  return 0;
}
```

控制器在 `_reconcileWindowSnapshot`（或窗口关闭路径）里：若 `splitPair` 的成员不再存在 → `endSplit()`，并把幸存者设为前台（`focusWindow`）。

- [ ] **Step 4: 设备验证**

分屏后从一侧应用的标题栏关闭它（或让它自行退出）：另一侧应立刻占满整屏，无空窗格、无选择器。

- [ ] **Step 5: 提交**

```bash
git add plugins/denial_desktop/lib/src/state/reference_shell_controller.dart \
  plugins/denial_desktop/lib/src/state/reference_shell_state.dart \
  packages/denial_flutter_sdk/lib/src/models/split_pair.dart \
  packages/denial_flutter_sdk/test/split_pair_test.dart
git commit -m "feat(split): the survivor takes the screen when a pane closes"
```

---

### Task 8: 旋转与外部激活复验

**Files:**
- Modify: `plugins/denial_desktop/lib/src/features/mobile/mobile_split_stage.dart`（`syncSplitAxis` 后重新判定可行）
- Modify: `plugins/denial_desktop/lib/src/state/reference_shell_controller.dart`（`syncSplitAxis` 不满足则 `endSplit`；`_handleNativeWindowActivated` 替换前判定可行）

- [ ] **Step 1: 写失败测试**（纯函数）

```dart
test('a rotated split that cannot fit is refused', () {
  const pair = SplitPair(first: 3, second: 5, vertical: true);
  expect(
    splitFits(
      width: 800,
      height: 1000,
      topInset: 45,
      pair: pair,
      firstMin: const Size(700, 100),
      secondMin: const Size(700, 100),
      vertical: true,
    ),
    isFalse,
  );
});
```

- [ ] **Step 2: 运行确认失败**

- [ ] **Step 3: 实现**：`syncSplitAxis` 在轴变化后用新的 extent 计算 bounds，`null` → `endSplit()` 并把前台设为激活侧；外部激活替换前同样判定，不满足则忽略替换（保持原分屏）。

- [ ] **Step 4: 设备验证**：分屏中旋转 6 次（横→竖→横…）：无黑边、无重复 configure（`DENIAL_SPLIT_DEBUG` 观察一次/旋转）、放不下时回到单应用并提示。

- [ ] **Step 5: 提交**

```bash
git add plugins/denial_desktop/lib/src/features/mobile/mobile_split_stage.dart \
  plugins/denial_desktop/lib/src/state/reference_shell_controller.dart \
  packages/denial_flutter_sdk/test/split_pair_test.dart
git commit -m "feat(split): keep rotation and external activation inside the minimums"
```

---

### Task 9: 文档与整体验收

**Files:**
- Modify: `docs/SPLIT_SCREEN.md`（把 v3 的“卡片/间隙”叙述改为“直接半屏 + 窄条”，并标注 v4）
- Modify: `docs/superpowers/plans/2026-11-11-split-screen.md`（追加本次重写的阶段与状态）
- Modify: `docs/superpowers/specs/2026-11-12-tablet-layout-shell.md`（Status → Realized，Change Log 追加）

- [ ] **Step 1: 按 spec 的 Test Steps 逐条跑一遍**（1–12），记录通过/失败。
- [ ] **Step 2: 更新三份文档并注明实测结果。**
- [ ] **Step 3: 提交**

```bash
git add docs
git commit -m "docs(split): the tablet panes are the layout tree now"
```

---

## 自检

- 规范覆盖：FR-1/2（T2）、FR-3（T2、T6）、FR-4/5（T1、T4）、FR-6（T5）、FR-7/8（T4）、FR-9（现有 + T4）、FR-10（T6）、FR-11（T6/T9）、FR-12/13（T5/T8）、FR-14（T9）、FR-15（T2 的重发策略）、FR-16（T7）、FR-17（T4 提示文案）、FR-18（无改动）、FR-19（T6 样式）、FR-20（T5）。
- 接口一致性：`pane_rects`/`fits`/`ratio_bounds` 在 T1 定义，T2/T4/T6 使用同一组名字与参数顺序。
- 已知未覆盖：`DENIAL_SPLIT_DEBUG` 的启动方式（T5 只说明“临时 systemd 环境”），执行时需确认现有启动脚本支持注入环境变量。

---

## 执行记录（2026-11-12 夜 → 11-13 凌晨）

Tasks 1–8 已实现并提交（`3b41438` … `d12c3f3`），Task 9 验收部分通过。

**已验证**
- 分屏几何、最小尺寸夹紧、窄条分割条（28px 命中带归外壳）、点击映射、激活侧同步；
- 后选应用聚焦后按窗格尺寸重绘；
- 被拒绝的分屏不再自动退出（按用户要求删除）。

**未解决（明天从这里开始）**
- 分屏中非激活窗格会冻结：用 `/tmp/ticker.sh`（每 0.2s 打印时间）复现，点另一侧后时间戳停止。
- 已排除采样集合：外壳发布 `visible={10,8}`，合成器 `sampled={10,8}` 都对。
- 方向：让分屏成员的 **buffer 提交把场景标脏**（或发布帧序号），外壳据此重绘两个窗格；桌面就是每次提交都 `scene_sync.mark_dirty()`。
- 验收仍未跑：旋转、成员关闭后全屏、键盘只推激活侧。

## 执行记录（2026-11-13 白天）

**双窗格冻结（P0）已修**
- 根因：移动端「失焦即 `minimizeWindow()`」把分屏里非激活的一侧当成后台应用挂起，合成器 `window_frozen()` 丢弃它的提交，画面停在最后一帧。
- 修法：`_minimizeLeftApp` 对分屏成员直接返回（`pair.contains`），`set_mobile_split` 时对两侧 `minimized_changed(false)`。
- 验证：终端每 0.2s 打印时间，点另一侧后时间戳继续推进（10:09:57 → 10:10:00；10:24:35 → 10:24:40）。提交 `825512a`。

**竖屏（1600×2560，`transform=DSI-1,90`）验收**
- 长按 recents 卡片拖到**上方 40%** → 选择器出现在下半屏 → 选 Console → 上下分屏成立，两窗格各 1244px，接缝在 1316（状态栏 72px 之后正好 50:50），两侧 1:1 刷新。
- 分割条：拖到 1000 → 接缝 1001；夹紧在 20% / 80%（气泡 `20 : 80`、`80 : 20`）；拖到 1290（±3%）→ 吸附回 1316；双击 → 复位 1316。
- 成员关闭 → 另一侧全屏（横屏 `bb1.png`）。
- **修了一个竖屏专属 bug**：分割条控件铺满整屏、按 `screenHeight × ratio` 定位，而窗格只铺状态栏以下，接缝差 36px，手指按在接缝上够不到控件、拖动被送给窗格。现在控件挂在「两窗格并集」区域里（`splitAreaFor`），横屏行为不变。提交 `a58ab6d`。
- 竖屏触摸注入用 `/tmp/pinput.py`（`tap`/`drag`，映射 `PX=1599*(1600-x)/1600, PY=2559*(1-y/2560)`），`/tmp/pdouble.py` 双击，`/tmp/pdrag.py` 按住拖动（截气泡）。

**仍缺**
- 旋转（分屏中横竖切换）：移动端设置里只有「当前方向」只读信息，没有运行时改 transform 的入口；只能改 `outputs.conf` + 重启，而重启会丢掉分屏状态。`syncSplitAxis` 这条路径本轮无法实机验证。
- 已知观察：分屏进行中从快捷设置打开「设置」，新应用直接**替换了激活侧窗格**（Text Editor 被换掉），而不是新开全屏或结束分屏。需要用户确认期望行为。
- P2 未动：点标题栏弹键盘、「全部应用」行为、退出入口、比例持久化。

**改：分屏中打开别的应用 → 新应用全屏，分屏驻留在后台（用户定的 Android 做法）**
- 旧行为：外壳没请求的窗口（通知、设置等）会**替换掉不用的那一侧窗格**。
- 中间试过「结束分屏」，用户否决：那样 recents 回不到分屏。
- 现行为：`state.splitParked`。非成员应用激活时（唯一出口是 `_activateWindowInShell` → `_parkSplitFor`）：
  1. 位置留给新应用全屏，`_platform.endSplit()` 释放窗格几何；
  2. 两个成员 `minimizeWindow()` 回家后台，但 `splitPair`（含 axial/ratio/active）留在状态里；
  3. recents 里这对应用仍是**一张合并卡**（`_deckIdOf`/`_collapsedOrder` 早就有这套）；
  4. 点这张卡 → `openFromRecents` → `focusWindow` → `_restoreParkedSplitFor`：`splitParked=false` + `splitWindowsByIds` 重建窗格，两个应用都恢复绘制。
- 没选完第二个应用的半成品分屏没有保留价值，仍按旧逻辑结束。
- 成员在驻留期间被关闭：只清分屏，**不**把幸存者拉到前台。
- 旋转时若分屏在驻留：只更新 pair 的 axis，不动客户端几何。
- 实机验证（横屏）：Text Editor + Console 分屏 → 外部启动 Nautilus → Files 全屏、recents 只剩「Files + 一张分屏卡」→ 点分屏卡 → 两窗格回来且 ticker 继续走（11:17:28 → 11:17:34）→ 再点 Files 卡 → Files 全屏、分屏再次驻留 → recents 仍是两张卡（往返稳定）。
- 未实机覆盖：应用列表（launcher）启动这条 `launchRequest` 分支（同样调 `_parkSplitFor`，只做了静态检查）。

## P2-1：点标题栏弹键盘（2026-11-13 下午）

**根因（两层）**
- 外壳 `keyboard_layer.dart`：客户端应用原本是 `wants = touched || pending`——应用里有活跃编辑器时，窗口内**任何一次触摸**都弹面板。Text Editor 的正文、Firefox 地址栏、终端输入行都算活跃编辑器，点标题栏自然弹。
- 合成器 `text_input.rs`：`commit` 把「提交里带光标矩形」当作编辑器对这次触摸的回应，而客户端每次提交都会重复同一个光标，于是重复上报也被当成「点了输入框」。

**改法**
- 新增纯函数 `softwareKeyboardWanted()`（`packages/denial_flutter_sdk/lib/keyboard_policy.dart`）：
  - 客户端应用：只有编辑器对触摸作出反应（`activated`，即光标移动 / 启用编辑器）或「触摸先于应用启用编辑器」（`pendingTouch`，点进去的那一下）才弹；
  - 外壳自己的输入框：不变（点外壳即点输入框），仅手动关闭时安静。
- 合成器：engagement 要求**光标真的移动**（`caret_moved`），重复光标不再算。
- 测试：SDK 5 条（含「标题栏式触摸不弹」）+ Rust 2 条（`a_touch_that_leaves_the_caret_alone_does_not_open_the_panel` 改动前为红）。Rust **690 passed**，SDK **17 passed**，`flutter analyze lib` 无问题。

**实机验证（2026-11-13 19:35–19:55，平板 2560×1600，全部通过）**
| 场景 | 结果 |
|---|---|
| 文本编辑器：键盘收起时点标题栏 | 不弹 ✓ |
| 文本编辑器：点正文 | 弹，光标落在点击处 ✓ |
| 文本编辑器：回桌面/最近任务再回来，点标题栏 | 不弹 ✓ |
| 终端（kgx）：点窗口内 | 弹（回归正常）✓ |
| Firefox：点地址栏 | 弹 ✓ |
| Firefox：点标签栏/工具栏空白、网页正文 | 不弹 ✓ |
| 外壳设置页搜索框 | 弹（回归正常）✓ |
| 分屏两侧：点标题栏 | 不弹；点正文才弹 ✓ |

未再需要用 `deniald::ime` 临时日志取证：实机行为已符合预期，补丁留在
`.superpowers/sdd/2026-11-12-tablet-layout-rewrite/ime-diagnostics.md` 备查。

**已知取舍**：客户端只在「光标真的移动 / 启用编辑器」时算点了输入框，所以在**同一个**已聚焦输入框里
点“光标本来就在的位置”不会重新弹面板（要先点别处再点回来）。Android 会重弹；本轮接受这个差异，
真要修得靠客户端重发编辑状态。

## 体验修复（2026-11-13 20:10）

**1. 上划进 recents 时键盘收得太晚**
- 根因：`keyboard_layer.dart` 只监听 `overviewVisible`（recents 落定后才为 true），所以键盘陪着动画一起收。
- 改法：监听 `deck.presenting`（`_moving || _held || open > 0`，手势一开始就为 true），一上划就隐藏面板；`overviewVisible`/`homeTransitionActive` 的监听保留作兜底。
- 证据：`kk0`（键盘在）→ `kk1`（上划中途，键盘已消失、应用正在淡出）→ `kk2`（recents）。

**2. 竖屏分屏里上划进不了 recents**
- 根因：分屏分支的输入布局只发布「状态栏一栏 + 两侧留白 + 缝隙」，**没有发布底部上划手势条**。合成器里 shell 区域优先（`input.rs::input_route`：命中 shell 区域直接归 Flutter），条子缺失时手势条位置被窗格的 window 区域占住，事件直接给客户端——实测竖屏下半屏上划被 Files 当成打开搜索框，还弹了键盘。横屏之所以“看起来能用”，是因为当时从屏幕正中（x=1280，正好是缝隙的 28px 命中带）上划，那条属于外壳。
- 改法：分屏分支把 `ReferenceShellMetrics.gestureRect(viewSize)`（底部 176×60 的居中手势条）一并发布为 shell 区域，横竖屏一致。
- 实机验证（竖屏 1600×2560，终端 + 文件分屏）：在下半屏上划 → recents 正常打开。

用户确认两条均修复。

**3. 上划（回桌面）会解散分屏 —— 2026-11-13 20:45**
- 根因：`goHome()` 里还留着分屏早期的 `if (state.splitPair != null) endSplit();`（注释写着“Home is a single-app place for now”）。上一轮做了分屏驻留，但回桌面这条路径没跟上。
- 改法：抽 `_parkSplit()`（决定“驻留还是结束”），`_parkSplitFor(window)` 复用它；`goHome()` 改为 `_parkSplit()`。飞回图标的 app 取 `_deckIdOf(...)`，所以分屏是**一张卡**整体飞回，而不是飞一侧。
- 实机验证（竖屏 1600×2560，文本编辑器 + 终端）：
  1. 分屏上划 → recents 里是**一张包含两个窗格的分屏卡**（`rz2`）；
  2. 点这张卡 → 分屏原样恢复（`rz3`）；
  3. 快速上甩 → 回桌面（`rz4`），分屏驻留；
  4. 桌面再上划 → recents 里分屏卡还在（`sa1`），点开仍是完整分屏（`sa2`）。

**关于触摸注入**：设备这次是「未旋转的竖屏」（`outputs.conf` 无 transform），触摸映射是恒等（raw = logical），之前按 `transform=90` 推导的 `/tmp/pinput.py` 坐标系已失效；本轮改用 `/tmp/ptouch.py`（tap/drag/flick，恒等映射）。另外从桌面起步的上划只有从**最底边**（y≈2557）开始才命中手势条，从 dock 上方（y≈2540）会被 dock 吃掉。

**4. recents 里上划回不到桌面 —— 2026-11-13 21:40**
- 根因：`BottomGestureHandle._resolvePan` 的 recents 分支只处理**下划**（`closeOverview()`，回到应用），上划直接落到 `resetGestureDrag()`——**什么也不做**。用户在 recents 里上划想回桌面，怎么划都没反应。分屏驻留之后 recents 更常出现（一张分屏卡），这个空洞暴露得更明显。
- 改法：recents 里上划（超过 `_closeDistance` 或甩速超过 `_flickVelocity`）→ `goHome()`；`goHome()` 会 `_parkSplit()`，所以分屏随之外驻留、recents 里仍是一张卡。
- 验证（用伪造的 `net.hadess.SensorProxy` 精确复现旋转）：分屏 → 转竖屏 → 转回横屏 → 上划（recents，一张双窗格卡）→ 再上划（桌面）→ 上划（卡还在）→ 点卡（分屏恢复）。

**测试基建：伪造加速度计**
平板的方向来自 D-Bus `net.hadess.SensorProxy`（iio-sensor-proxy）。`sudo systemctl stop iio-sensor-proxy` 后运行一个同名 D-Bus 服务（`/tmp/fakeorient.py`），读 `/tmp/orient` 并广播 `PropertiesChanged`，就能随时把输出旋到 `normal`/`left-up`，无需真的转动设备。测完要 `sudo systemctl start iio-sensor-proxy` 并删除 `/tmp/orient`。

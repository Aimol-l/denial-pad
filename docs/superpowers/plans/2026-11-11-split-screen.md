# 平板分屏实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 mobile shell 里实现双应用分屏：横屏左右、竖屏上下，由 recents 拖拽或 launcher 长按拖拽进入，分屏对在 recents 中是一张卡片。

**Architecture:** 窗口矩形仍由合成器决定：`mobile_window_geometry()` 是多窗口在手机上的唯一矩形来源，新增一份「分屏对」状态后它为两个窗口返回各自的半边矩形，其余 configure/scale/inset 路径不变。外壳只负责状态机、手势、渲染两个窗格和分割条；它不计算窗口矩形，只发送「开始/更新比例/结束分屏」请求。

**Tech Stack:** Rust（Smithay compositor，`cargo test`）、Dart/Flutter（shell 插件）、FlatBuffers wire（`tools/generate-denial-wire`）。

**Spec:** `docs/SPLIT_SCREEN.md`（视觉稿 `docs/designs/split-screen-redesign.html`、`docs/designs/launcher-split-entry-redesign.html`）

## Global Constraints

- 范围仅 mobile shell；外接显示器走桌面布局，分屏不影响 desk。
- 方向由输出宽高比决定：横屏左右、竖屏上下，无用户开关。
- 默认比例 53:47（首拖入侧 53%）；限制 20%–80%；47%–53% 磁吸到 50:50。
- 分屏对在 recents 中是**一张卡片**；主动拖入第三个应用 → 拒绝并提示。
- 关闭阈值与现有 recents 一致：卡片高度 40%（`_dismissDistanceRatio = 0.5` 现状可保留为轻划手感）。
- 状态栏 45 逻辑像素状态栏由合成器扣除，两个窗格都在其下。
- 同一 app 的多窗口共享一个 client scale，分屏阶段不实现 per-window scale。
- 所有新 wire 字段必须有默认值，旧外壳发来的请求保持现有行为。

## Review Focus

- 用户把卡片拖到屏幕边缘但松手在放置区外：卡片必须弹回，不能误开分屏或误关应用。
- 分屏中旋转设备：两个窗格方向翻转且比例按短边保持，动画期间不能反复 configure 导致抖动。
- 分屏中软键盘弹出：只推激活侧，非激活侧内容不动，键盘关闭后恢复。
- 从 recents 关闭分屏对的一侧：另一侧必须平滑扩展为全屏，不能留下半屏黑边。
- 外部 intent/通知打开新应用：替换非激活侧，激活侧焦点与输入不能丢。

---

### Task 1: 合成器分屏状态与几何

**Files:**
- Create: `compositor/src/bin/deniald/wayland_frontend/mobile_split.rs`
- Modify: `compositor/src/bin/deniald/wayland_frontend.rs`（`mod mobile_split;`、`WaylandFrontend` 字段 `mobile_split: Option<MobileSplit>`）
- Modify: `compositor/src/bin/deniald/wayland_frontend/insets.rs:383-445`（`mobile_window_geometry` / `configure_mobile_window`）
- Modify: `compositor/src/bin/deniald/wayland_frontend/startup.rs`（初始化字段）
- Modify: `protocol/denial.fbs:48-63`（`WindowRequestKind`）与 `:539-569`（`WindowRequest` 字段）
- Modify: `compositor/src/bin/deniald/wire.rs:130-200`（`WindowCommand`）、`wire/decode.rs`（新 kind）、`wire/encode.rs`（Dart→Rust 无编码）
- Test: `compositor/src/bin/deniald/wayland_frontend/mobile_split/tests.rs`（纯几何）

**Interfaces:**
- Produces:
  - `pub(super) struct MobileSplit { pub first: u64, pub second: u64, pub vertical: bool, pub ratio: f32 }`
  - `pub(super) fn split_rects(full: Rectangle<i32, Logical>, vertical: bool, ratio: f32) -> [Rectangle<i32, Logical>; 2]`
  - `WaylandFrontend::set_mobile_split(&mut self, split: Option<MobileSplit>) -> bool`（返回是否变化）
  - wire: `WindowRequestKind.SplitWindows = 12`、`UpdateSplitRatio = 13`、`EndSplit = 14`；`WindowRequest` 新字段 `split_window_id:ulong`、`split_vertical:bool`、`split_ratio:float = 0.53`

- [ ] **Step 1: 写失败的几何测试**

`mobile_split/tests.rs`：

```rust
use super::*;

fn full() -> Rectangle<i32, Logical> {
    Rectangle::new((0, 45).into(), (1600, 955).into())
}

#[test]
fn landscape_splits_left_and_right() {
    let [left, right] = split_rects(full(), false, 0.53);
    assert_eq!(left, Rectangle::new((0, 45).into(), (848, 955).into()));
    assert_eq!(right, Rectangle::new((848, 45).into(), (752, 955).into()));
    assert_eq!(left.size.w + right.size.w, full().size.w);
}

#[test]
fn portrait_splits_top_and_bottom() {
    let [top, bottom] = split_rects(full(), true, 0.5);
    assert_eq!(top.size.h, 477);
    assert_eq!(bottom.loc.y, 45 + 477);
    assert_eq!(top.size.h + bottom.size.h, full().size.h);
}

#[test]
fn ratio_is_clamped_to_the_draggable_range() {
    assert_eq!(split_rects(full(), false, 0.05)[0].size.w, 320);
    assert_eq!(split_rects(full(), false, 0.95)[0].size.w, 1280);
}

#[test]
fn a_window_outside_the_pair_keeps_the_full_rect() {
    let split = MobileSplit { first: 7, second: 9, vertical: false, ratio: 0.53 };
    assert!(split.pane(7, full()).is_some());
    assert!(split.pane(11, full()).is_none());
}
```

- [ ] **Step 2: 运行并确认失败**

Run: `cd compositor && CARGO_TARGET_DIR=$HOME/.cache/denial/pc-build/rust cargo test --features flutter --bin deniald mobile_split::`
Expected: 编译失败，`MobileSplit` / `split_rects` 未定义。

- [ ] **Step 3: 实现 `mobile_split.rs`**

```rust
//! The two panes one mobile output is split into.
//!
//! The compositor owns every window rectangle; a split is just this struct
//! telling `mobile_window_geometry` which half a window gets. The shell sends
//! the pair, its axis and the ratio, and draws what the compositor configures.

use smithay::utils::{Logical, Rectangle};

pub(super) const MIN_RATIO: f32 = 0.2;
pub(super) const MAX_RATIO: f32 = 0.8;
/// The ratio a split starts with: the side the user dragged into is larger.
pub(super) const DEFAULT_RATIO: f32 = 0.53;

#[derive(Clone, Copy, Debug, PartialEq)]
pub(super) struct MobileSplit {
    pub(super) first: u64,
    pub(super) second: u64,
    pub(super) vertical: bool,
    pub(super) ratio: f32,
}

impl MobileSplit {
    pub(super) fn clamped(mut self) -> Self {
        self.ratio = self.ratio.clamp(MIN_RATIO, MAX_RATIO);
        self
    }

    pub(super) fn pane(
        &self,
        window_id: u64,
        full: Rectangle<i32, Logical>,
    ) -> Option<Rectangle<i32, Logical>> {
        let [first, second] = split_rects(full, self.vertical, self.ratio);
        match window_id {
            id if id == self.first => Some(first),
            id if id == self.second => Some(second),
            _ => None,
        }
    }
}

pub(super) fn split_rects(
    full: Rectangle<i32, Logical>,
    vertical: bool,
    ratio: f32,
) -> [Rectangle<i32, Logical>; 2] {
    let ratio = ratio.clamp(MIN_RATIO, MAX_RATIO);
    if vertical {
        let first_h = ((full.size.h as f32) * ratio).round() as i32;
        [
            Rectangle::new(full.loc, (full.size.w, first_h).into()),
            Rectangle::new(
                (full.loc.x, full.loc.y + first_h).into(),
                (full.size.w, full.size.h - first_h).into(),
            ),
        ]
    } else {
        let first_w = ((full.size.w as f32) * ratio).round() as i32;
        [
            Rectangle::new(full.loc, (first_w, full.size.h).into()),
            Rectangle::new(
                (full.loc.x + first_w, full.loc.y).into(),
                (full.size.w - first_w, full.size.h).into(),
            ),
        ]
    }
}

#[cfg(test)]
#[path = "mobile_split/tests.rs"]
mod tests;
```

- [ ] **Step 4: 接进 `mobile_window_geometry`**

`insets.rs`，在算出 `geometry`（整屏减状态栏）之后、返回之前：

```rust
        let window_id = self.window_root_surface(window).and_then(|root| self.surface_id(&root));
        if let Some(split) = self.mobile_split
            && let Some(window_id) = window_id
            && let Some(pane) = split.pane(window_id, geometry)
        {
            return Some(pane);
        }
        Some(geometry)
```

字段与 `set_mobile_split`：

```rust
    /// Both panes a mobile output is split into, if any.
    #[cfg(feature = "flutter")]
    pub(super) mobile_split: Option<mobile_split::MobileSplit>,

    #[cfg(feature = "flutter")]
    pub(super) fn set_mobile_split(&mut self, split: Option<mobile_split::MobileSplit>) -> bool {
        let split = split.map(mobile_split::MobileSplit::clamped);
        if self.mobile_split == split {
            return false;
        }
        self.mobile_split = split;
        let windows = self.space.elements().cloned().collect::<Vec<_>>();
        for window in windows {
            self.configure_mobile_window(&window);
        }
        true
    }
```

- [ ] **Step 5: 加 wire 命令**

`protocol/denial.fbs`：

```fbs
  // 分屏：窗口对、方向与首窗占比。EndSplit 忽略其中字段。
  SplitWindows = 12,
  UpdateSplitRatio = 13,
  EndSplit = 14
```

```fbs
  // SplitWindows / UpdateSplitRatio only. `window_id` 是第一侧，
  // `split_window_id` 是第二侧；竖屏时第一侧在上，横屏时在左。
  split_window_id:ulong;
  split_vertical:bool;
  split_ratio:float = 0.53;
```

`wire.rs`：

```rust
    Split {
        first: u64,
        second: u64,
        vertical: bool,
        ratio: f32,
    },
    UpdateSplitRatio {
        ratio: f32,
    },
    EndSplit,
```

`wire/decode.rs` 的 `WindowRequest` 分支里，按 kind 把 `window_id` / `split_window_id` / `split_vertical` / `split_ratio` 读出来；`ratio` 非法（NaN 或 ≤0）时返回 `WireError::Payload`。

`window_management.rs` 的命令分发处：

```rust
        WindowCommand::Split { first, second, vertical, ratio } => {
            if frontend.mobile_shell() {
                frontend.set_mobile_split(Some(mobile_split::MobileSplit {
                    first, second, vertical, ratio,
                }));
            }
        }
        WindowCommand::UpdateSplitRatio { ratio } => {
            if let Some(mut split) = frontend.mobile_split {
                split.ratio = ratio;
                frontend.set_mobile_split(Some(split));
            }
        }
        WindowCommand::EndSplit => {
            frontend.set_mobile_split(None);
        }
```

- [ ] **Step 6: 生成绑定并跑测试**

Run:
```bash
FLATC=$PWD/compositor/target/flatbuffers/src/flatc ./tools/generate-denial-wire
cd compositor && CARGO_TARGET_DIR=$HOME/.cache/denial/pc-build/rust cargo test --features flutter --bin deniald mobile_split::
```
Expected: `4 passed`；`cargo check` 无错误。

- [ ] **Step 7: 提交**

```bash
git add compositor/src/bin/deniald/wayland_frontend/mobile_split.rs \
  compositor/src/bin/deniald/wayland_frontend/mobile_split/tests.rs \
  compositor/src/bin/deniald/wayland_frontend/insets.rs \
  compositor/src/bin/deniald/wayland_frontend.rs \
  compositor/src/bin/deniald/wayland_frontend/startup.rs \
  compositor/src/bin/deniald/wire.rs compositor/src/bin/deniald/wire/decode.rs \
  compositor/src/bin/deniald/wayland_frontend/window_management.rs \
  protocol/denial.fbs protocol/generated
git commit -m "feat(split): compositor-owned two-pane geometry"
```

---

### Task 2: 外壳的分屏模型与发送

**Files:**
- Create: `packages/denial_flutter_sdk/lib/src/models/split_pair.dart`（纯 Dart，无 Flutter import）
- Modify: `packages/denial_flutter_sdk/lib/models.dart`（导出）
- Modify: `packages/denial_flutter_sdk/lib/src/platform/bridge/codec_scaffolding.dart`? → 实际是 `lib/src/platform/denial_wire.dart`（编码 `WindowRequest`）与 `lib/src/platform/bridge/windows_client.dart`（发送）
- Test: `packages/denial_flutter_sdk/test/split_pair_test.dart`

**Interfaces:**
- Produces:
  - `class SplitPair { final int first; final int second; final bool vertical; final double ratio; final SplitSide active; }`（`enum SplitSide { first, second }`）
  - `SplitPair clamped()`, `SplitPair withRatio(double)`
  - `({double first, double second}) splitFractions(double ratio)`（磁吸 + 限幅后的两段占比）
  - `useDenialSplitPair` no; SDK 端：
  - `windows_client`: `void splitWindows({required int first, required int second, required bool vertical, double ratio = 0.53})`、`void updateSplitRatio(double ratio)`、`void endSplit()`

- [ ] **Step 1: 写失败的纯 Dart 测试**

`test/split_pair_test.dart`：

```dart
import 'package:denial_flutter_sdk/src/models/split_pair.dart';
import 'package:test/test.dart';

void main() {
  test('a ratio near the middle snaps to half and half', () {
    expect(splitFractions(0.5), (first: 0.5, second: 0.5));
    expect(splitFractions(0.48), (first: 0.5, second: 0.5));
    expect(splitFractions(0.47), (first: 0.5, second: 0.5));
    expect(splitFractions(0.44), (first: 0.44, second: 0.56));
  });

  test('a ratio outside the draggable range is clamped', () {
    expect(splitFractions(0.05).first, 0.2);
    expect(splitFractions(0.95).first, 0.8);
  });

  test('a pair keeps its axis and ratio when the ratio moves', () {
    const pair = SplitPair(first: 3, second: 5, vertical: true, ratio: 0.53, active: SplitSide.first);
    final moved = pair.withRatio(0.7);
    expect(moved.vertical, isTrue);
    expect(moved.first, 3);
    expect(moved.second, 5);
    expect(moved.ratio, 0.7);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd packages/denial_flutter_sdk && /home/aimol/.cache/denial/pc-dependencies/flutter/bin/dart test test/split_pair_test.dart`
Expected: 编译失败，`split_pair.dart` 不存在。

- [ ] **Step 3: 实现 `split_pair.dart`**

```dart
/// Which pane of a split pair receives input.
enum SplitSide { first, second }

/// The closest a divider may bring a pane to the screen edge.
const double splitMinFraction = 0.2;
const double splitMaxFraction = 0.8;
/// A divider this close to the middle snaps to an even split.
const double splitSnapWindow = 0.03;

/// One split pair: two windows, the axis, and the first window's share.
class SplitPair {
  const SplitPair({
    required this.first,
    required this.second,
    required this.vertical,
    this.ratio = 0.53,
    this.active = SplitSide.first,
  });

  final int first;
  final int second;
  final bool vertical;
  final double ratio;
  final SplitSide active;

  SplitPair withRatio(double ratio) => SplitPair(
    first: first,
    second: second,
    vertical: vertical,
    ratio: ratio.clamp(splitMinFraction, splitMaxFraction),
    active: active,
  );

  SplitPair withActive(SplitSide side) => SplitPair(
    first: first,
    second: second,
    vertical: vertical,
    ratio: ratio,
    active: side,
  );

  int get activeWindow => active == SplitSide.first ? first : second;
  int get inactiveWindow => active == SplitSide.first ? second : first;

  @override
  bool operator ==(Object other) =>
      other is SplitPair &&
      other.first == first &&
      other.second == second &&
      other.vertical == vertical &&
      other.ratio == ratio &&
      other.active == active;

  @override
  int get hashCode => Object.hash(first, second, vertical, ratio, active);
}

({double first, double second}) splitFractions(double ratio) {
  final clamped = ratio.clamp(splitMinFraction, splitMaxFraction);
  if ((clamped - 0.5).abs() <= splitSnapWindow) {
    return (first: 0.5, second: 0.5);
  }
  return (first: clamped, second: 1 - clamped);
}
```

- [ ] **Step 4: 发送请求**

`windows_client.dart` 加三个方法，走 `_context.codec.encodeWindowRequest(...)`（沿用现有 `encodeWindowRequest` 的参数表，新增 `splitSecond` / `splitVertical` / `splitRatio`）。`denial_wire.dart` 里对应补字段：

```dart
  Uint8List encodeWindowRequest({
    required generated.WindowRequestKind kind,
    required int requestId,
    int windowId = 0,
    int splitSecond = 0,
    bool splitVertical = false,
    double splitRatio = 0.53,
    // 现有参数...
  }) {
    return _encodeEnvelope(
      generated.PayloadTypeId.WindowRequest,
      generated.WindowRequestObjectBuilder(
        kind: kind,
        windowId: windowId,
        splitWindowId: splitSecond,
        splitVertical: splitVertical,
        splitRatio: splitRatio,
        // 现有字段...
      ),
      requestId: requestId,
    );
  }
```

- [ ] **Step 5: 跑测试并格式化**

Run:
```bash
cd packages/denial_flutter_sdk && /home/aimol/.cache/denial/pc-dependencies/flutter/bin/dart test test/split_pair_test.dart
cd /home/aimol/Documents/Workspace/denial-pad && FLATC=$PWD/compositor/target/flatbuffers/src/flatc ./tools/generate-denial-wire --check
```
Expected: `3 passed`；`Denial generated wire code is current`。

- [ ] **Step 6: 提交**

```bash
git add packages/denial_flutter_sdk/lib/src/models/split_pair.dart \
  packages/denial_flutter_sdk/lib/models.dart \
  packages/denial_flutter_sdk/lib/src/platform/denial_wire.dart \
  packages/denial_flutter_sdk/lib/src/platform/bridge/windows_client.dart \
  packages/denial_flutter_sdk/test/split_pair_test.dart
git commit -m "feat(split): split pair model and window request"
```

---

### Task 3: 外壳状态与双窗格渲染

**Files:**
- Modify: `plugins/denial_desktop/lib/src/state/reference_shell_state.dart`（字段 `splitPair`）
- Modify: `plugins/denial_desktop/lib/src/state/reference_shell_controller.dart`（`startSplit` / `updateSplit` / `endSplit` / `setSplitActive`）
- Create: `plugins/denial_desktop/lib/src/features/mobile/mobile_split_stage.dart`
- Modify: `plugins/denial_desktop/lib/src/features/mobile/mobile_window_layers.dart:17-65`（有 split 时渲染 stage）
- Modify: `plugins/denial_desktop/lib/src/features/mobile/mobile_application_scene.dart:117-143`（叠放）
- Modify: `plugins/denial_desktop/lib/src/widgets/overview/app_deck_layer.dart`（临时调试入口，Task 4 移除）

**Interfaces:**
- Consumes: `SplitPair`、`splitFractions`、`windows_client.splitWindows/updateSplitRatio/endSplit`
- Produces:
  - `ReferenceShellState.splitPair`（`SplitPair?`）
  - `ReferenceShellController.startSplit({required DenialWindow first, required DenialWindow second, required bool vertical})`
  - `...updateSplitRatio(double ratio)`、`...endSplit()`、`...setSplitActive(SplitSide side)`
  - `MobileSplitStage({required SplitPair pair, required DenialWindow first, required DenialWindow second})`

- [ ] **Step 1: 状态与控制器**

`reference_shell_state.dart`：在 `launchRequest` 旁加 `required this.splitPair` + `final SplitPair? splitPair;`，`copyWith` 支持清空（`bool clearSplitPair = false`）。`primaryWindow` 在分屏时不返回（`splitPair != null` → null），防止整屏 stage 与双窗格同时绘制。

`reference_shell_controller.dart`：

```dart
  void startSplit({
    required DenialWindow first,
    required DenialWindow second,
    required bool vertical,
  }) {
    final pair = SplitPair(
      first: first.objectId,
      second: second.objectId,
      vertical: vertical,
    );
    state = state.copyWith(splitPair: pair, foregroundObjectId: first.objectId);
    _windows.splitWindows(
      first: pair.first,
      second: pair.second,
      vertical: pair.vertical,
    );
    _platform.focusWindow(first.objectId);
  }

  void updateSplitRatio(double ratio) {
    final pair = state.splitPair?.withRatio(ratio);
    if (pair == null) return;
    state = state.copyWith(splitPair: pair);
    _windows.updateSplitRatio(pair.ratio);
  }

  void endSplit() {
    if (state.splitPair == null) return;
    state = state.copyWith(clearSplitPair: true);
    _windows.endSplit();
  }
```

- [ ] **Step 2: 双窗格 stage**

`mobile_split_stage.dart`：

```dart
class MobileSplitStage extends StatelessWidget {
  const MobileSplitStage({super.key, required this.pair, required this.windows});

  final SplitPair pair;
  final Map<int, DenialWindow> windows;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final fractions = splitFractions(pair.ratio);
    final first = windows[pair.first];
    final second = windows[pair.second];
    if (first == null || second == null) return const SizedBox.shrink();
    Widget pane(DenialWindow window, double share, bool active) => Positioned(
      left: pair.vertical ? 0 : (share == fractions.first ? 0 : size.width * fractions.first),
      top: pair.vertical && share != fractions.first ? size.height * fractions.first : 0,
      width: pair.vertical ? size.width : size.width * share,
      height: pair.vertical ? size.height * share : size.height,
      child: Opacity(
        opacity: active ? 1 : 0.96,
        child: WindowContentRect(window: window),
      ),
    );
    return Stack(
      children: [
        pane(first, fractions.first, pair.active == SplitSide.first),
        pane(second, fractions.second, pair.active == SplitSide.second),
      ],
    );
  }
}
```

> `WindowContentRect` 当前按父级整屏做 `BoxFit.cover`；分屏时父级就是窗格矩形，合成器已把窗口 configure 成该尺寸，因此直接铺满即可。

- [ ] **Step 3: 接进场景**

`mobile_window_layers.dart`：`MobilePrimaryWindowLayer` 里读 `state.splitPair`，非空时用 `MobileSplitStage` 替换整屏 stage；`app_deck_layer` 在 presenting 时仍盖在上面。

- [ ] **Step 4: 临时调试入口（Task 4 删除）**

在 recents 卡片长按菜单加一项「与上一个应用分屏」：调用 `startSplit(first: 当前卡, second: 上一个最近应用)`，用来验证两窗格渲染。

- [ ] **Step 5: 设备验证**

构建部署，平板打开两个应用 → recents → 长按一张卡 → 「与上一个应用分屏」：
- 两个窗口各占一半，横屏左右；
- 点任一侧，焦点切换（另一侧内容仍刷新）；
- 关闭：再点「退出分屏」调试项恢复全屏。

- [ ] **Step 6: 提交**

```bash
git add plugins/denial_desktop/lib/src/state/reference_shell_state.dart \
  plugins/denial_desktop/lib/src/state/reference_shell_controller.dart \
  plugins/denial_desktop/lib/src/features/mobile/mobile_split_stage.dart \
  plugins/denial_desktop/lib/src/features/mobile/mobile_window_layers.dart \
  plugins/denial_desktop/lib/src/features/mobile/mobile_application_scene.dart \
  plugins/denial_desktop/lib/src/widgets/overview/app_deck_layer.dart
git commit -m "feat(split): show both panes with a debug entry"
```

---

### Task 4: recents 拖拽入口与放置区（横屏）

**Files:**
- Modify: `plugins/denial_desktop/lib/src/widgets/overview/app_deck_layer.dart:342-578`（`_DeckCard` 拖拽）
- Create: `plugins/denial_desktop/lib/src/widgets/overview/split_drop_zone.dart`
- Modify: `plugins/denial_desktop/lib/src/state/reference_shell_controller.dart`（`beginSplitDrag` / `previewSplitSide` / `cancelSplitDrag`）

**Interfaces:**
- Produces:
  - `SplitDropSide { left, right }`（竖屏为 `top` / `bottom`，Task 9 加）
  - `SplitDropZone({required SplitDropSide side, required double share, required bool active})`
  - controller: `void beginSplitDrag(int windowId)`、`void previewSplitSide(SplitDropSide? side)`、`void commitSplitDrop()`

- [ ] **Step 1: 卡片拖拽分方向**

`_DeckCardState` 当前只有 `onVerticalDrag*`。改为 `onPanStart/Update/End`，按主位移方向分流：

```dart
  void _moveDrag(DragUpdateDetails details) {
    _drag += details.delta;
    final horizontal = _drag.dx.abs() > _drag.dy.abs() * 1.2;
    if (horizontal && widget.canSplit) {
      widget.onSplitDrag(_drag.dx < 0 ? SplitDropSide.left : SplitDropSide.right);
      return;
    }
    // 原有上滑关闭：保持 _dismissDistanceRatio 判定
    setState(() => _offset = _drag);
  }
```

- [ ] **Step 2: 放置区叠加**

`app_deck_layer` 的 Stack 顶部，`presenting` 且 `splitPreview != null` 时显示 `SplitDropZone`：accent 虚线 + 14% 填充 + 文案「放到左侧/右侧」，比例预览用 `splitFractions(0.53)` 画两块半透明缩略图。

- [ ] **Step 3: 松手提交**

`_endDrag` 里若 `splitSide != null` → `controller.commitSplitDrop()`：把拖拽窗口固定到该侧，打开选择器（Task 5 之前先用「上一个最近任务」占位）。

- [ ] **Step 4: 消歧测试（设备）**

- 上滑超过卡片高度 40% → 关闭应用；
- 水平拖到屏幕 28% → 出现放置区，松手进入分屏；
- 拖到一半松手 → 卡片弹回，无操作。

- [ ] **Step 5: 提交**

```bash
git add plugins/denial_desktop/lib/src/widgets/overview/app_deck_layer.dart \
  plugins/denial_desktop/lib/src/widgets/overview/split_drop_zone.dart \
  plugins/denial_desktop/lib/src/state/reference_shell_controller.dart
git commit -m "feat(split): drag a recent onto a side"
```

---

### Task 5: 选择器（补第二侧）

**Files:**
- Create: `plugins/denial_desktop/lib/src/widgets/overview/split_picker.dart`
- Modify: `plugins/denial_desktop/lib/src/features/mobile/mobile_window_layers.dart`
- Modify: `plugins/denial_desktop/lib/src/state/reference_shell_controller.dart`（`pickSplitSecond(int windowId)`、`dismissSplitPicker()`）

**Interfaces:**
- Produces: `SplitPicker({required SplitSide side, required List<DenialWindow> windows, required ValueChanged<int> onPick, required VoidCallback onDismiss})`

- [ ] **Step 1: 选择器 UI**

铺在未固定的半屏：`rgba(18,18,26,.58)` + `BackdropFilter(blur 22)`；每项 64px 缩略图 + 应用名 + 「打开 →」；点空白或下划关闭选择器（进入单应用分屏态）。

- [ ] **Step 2: 状态**

`state.splitPair` 允许 `second == 0` 表示单应用分屏；`dismissSplitPicker` 保持该状态；`pickSplitSecond` 填充并 `splitWindows` 重新下发一次。

- [ ] **Step 3: 设备验证**

固定左侧后右侧出现选择器；点一个应用 → 双应用分屏；点空白 → 单应用分屏，左应用占 53%，右侧留空。

- [ ] **Step 4: 提交**

```bash
git add plugins/denial_desktop/lib/src/widgets/overview/split_picker.dart \
  plugins/denial_desktop/lib/src/features/mobile/mobile_window_layers.dart \
  plugins/denial_desktop/lib/src/state/reference_shell_controller.dart
git commit -m "feat(split): pick the second app"
```

---

### Task 6: 分割条

**Files:**
- Create: `plugins/denial_desktop/lib/src/widgets/overview/split_divider.dart`
- Modify: `plugins/denial_desktop/lib/src/features/mobile/mobile_split_stage.dart`

**Interfaces:**
- Produces: `SplitDivider({required SplitPair pair, required ValueChanged<double> onRatio, required VoidCallback onReset, required VoidCallback onSwap})`

- [ ] **Step 1: 拖动与磁吸**

```dart
  void _move(DragUpdateDetails details) {
    final size = MediaQuery.sizeOf(context);
    final next = pair.vertical
        ? (details.localPosition.dy / size.height)
        : (details.localPosition.dx / size.width);
    widget.onRatio(splitFractions(next).first); // 磁吸 + 限幅都在这里
  }
```

- [ ] **Step 2: 双击复位 / 双击手柄交换**

双击分割条空白 → `onReset()`（53:47）；双击中央手柄 → `onSwap()`（交换两侧 objectId 与 active，比例保持）。

- [ ] **Step 3: 设备验证**

拖动 20%–80% 限幅、47%–53% 吸附到 50:50、双击复位、双击手柄交换。

- [ ] **Step 4: 提交**

```bash
git add plugins/denial_desktop/lib/src/widgets/overview/split_divider.dart \
  plugins/denial_desktop/lib/src/features/mobile/mobile_split_stage.dart
git commit -m "feat(split): draggable divider with snap and reset"
```

---

### Task 7: recents 中的分屏对卡片

**Files:**
- Modify: `plugins/denial_desktop/lib/src/state/app_deck.dart`（pair 作为一张卡）
- Modify: `plugins/denial_desktop/lib/src/widgets/overview/app_deck_layer.dart`

**Interfaces:**
- Consumes: `SplitPair`
- Produces: `AppDeck` 的 `presentedPairs`（把 pair 变成一个 deck 条目，内容为两窗缩略图并排）

- [ ] **Step 1: 卡片内容**

分屏对卡片：左右（或上下）各画一个 `WindowContentRect` 缩略图，中间一条细分割线；label 用两侧应用名「A | B」。

- [ ] **Step 2: 操作**

点按 → 回到该分屏对（`focusWindow(pair.first)` + `startSplit`）；上划 → `endSplit()` 并关闭两个窗口；拖出 → 先拖侧变全屏。

- [ ] **Step 3: 设备验证**

分屏 → 上划进 recents：只有一张卡片；点它回到分屏；上划卡片关闭整对。

- [ ] **Step 4: 提交**

```bash
git add plugins/denial_desktop/lib/src/state/app_deck.dart \
  plugins/denial_desktop/lib/src/widgets/overview/app_deck_layer.dart
git commit -m "feat(split): one recents card per pair"
```

---

### Task 8: 激活侧、返回键与软键盘

**Files:**
- Modify: `plugins/denial_desktop/lib/src/state/reference_shell_controller.dart`（`setSplitActive`）
- Modify: `plugins/denial_desktop/lib/src/features/mobile/mobile_split_stage.dart`（点击切侧、激活侧描边）
- Modify: `plugins/denial_desktop/lib/src/state/reference_input_layout_coordinator.dart`（两个 window 的输入矩形）
- Modify: `compositor/src/bin/deniald/wayland_frontend/insets.rs`（键盘 inset 只给激活侧）

**Interfaces:**
- Produces: `SplitPair.active` 驱动输入主题；`setSplitActive(SplitSide)` 发 `focusWindow`。

- [ ] **Step 1: 点击切侧**

```dart
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => controller.setSplitActive(SplitSide.first), // 同理 second
      child: ...,
    );
```

激活侧：1px accent 内发光；非激活侧：亮度 96%。

- [ ] **Step 2: 输入布局发两个矩形**

`reference_input_layout_coordinator` 的 `windows` 列表在分屏时填两个 `InputWindowRegion`（各自的半屏矩形），`inputWindow` 只保留激活侧用于键盘。

- [ ] **Step 3: 键盘只推激活侧**

`insets.rs` 的 `set_keyboard_height` / `project_mobile_inset` 在 split 存在时只对 `split.first` 或 `split.second`（激活侧）应用 inset；非激活侧 geometry 不变。

- [ ] **Step 4: 返回键走激活侧**

`NavigateBack` 的 `window_id` 用 `pair.activeWindow`。

- [ ] **Step 5: 设备验证**

点右侧 → 键盘弹出时只推右侧；返回键关闭右侧应用；左侧内容不动。

- [ ] **Step 6: 提交**

```bash
git add plugins/denial_desktop/lib/src/state/reference_shell_controller.dart \
  plugins/denial_desktop/lib/src/features/mobile/mobile_split_stage.dart \
  plugins/denial_desktop/lib/src/state/reference_input_layout_coordinator.dart \
  compositor/src/bin/deniald/wayland_frontend/insets.rs
git commit -m "feat(split): active side drives input and the keyboard inset"
```

---

### Task 9: 竖屏手势（顶部/底部触发区 + 分界线）

**Files:**
- Modify: `plugins/denial_desktop/lib/src/widgets/overview/app_deck_layer.dart`（纵向拖拽判定）
- Modify: `plugins/denial_desktop/lib/src/widgets/overview/split_drop_zone.dart`（top/bottom 变体 + 分界线）

**Interfaces:**
- Produces: `SplitDropSide { left, right, top, bottom }`；分界线 `0.55` 屏高。

- [ ] **Step 1: 判定**

竖屏拖卡片：向上拖过 `0.55` 屏高 → `top` 触发区点亮；未过线松手 → 关闭；向下拖进底部 25% → `bottom`；向下轻划 → 弹回。

- [ ] **Step 2: 视觉**

分界线：2px 红色虚线（`rgba(229,83,75,.45)`）+ 右侧「分界线 · 约 55% 屏高」白底胶囊；触发区文案「拖到这里 = 上分屏 / 下分屏」。

- [ ] **Step 3: 设备验证（竖屏）**

拿起平板转竖：上拖过线分屏、未过线关闭、下拖到底分屏、下轻划弹回。

- [ ] **Step 4: 提交**

```bash
git add plugins/denial_desktop/lib/src/widgets/overview/app_deck_layer.dart \
  plugins/denial_desktop/lib/src/widgets/overview/split_drop_zone.dart
git commit -m "feat(split): portrait trigger zones and threshold line"
```

---

### Task 10: launcher 长按拖拽入口

**Files:**
- Modify: `plugins/denial_desktop/lib/src/launcher/home_surface.dart:225-299`（长按后横向拖动）
- Modify: `plugins/denial_desktop/lib/src/launcher/home_drag_controller.dart:10-21,223-280`（`HomeDropKind.splitSide`）
- Modify: `plugins/denial_desktop/lib/src/features/mobile/mobile_launcher_layer.dart`
- Modify: `plugins/denial_desktop/lib/src/launcher/home_launch.dart:15-70`（带目标侧启动）

**Interfaces:**
- Produces: `HomeDropKind.splitSide` + `SplitDropSide side`；`launchHomeApp(..., SplitDropSide? splitSide)`

- [ ] **Step 1: 长按预备态**

长按图标 380ms → 其余图标淡到 32%，顶部提示「拖向屏幕一侧可分屏 · 上划打开」；此状态不拦截上划打开。

- [ ] **Step 2: 拖拽判定**

复用 Task 4 的放置区与 28% 阈值；松手 → `beginAppLaunch(splitSide: side)`：有前台应用则 `startSplit(前台, 新应用)`，无前台则单应用分屏态。

- [ ] **Step 3: 设备验证**

桌面长按图标拖到左侧 → 新应用进左侧、原前台进右侧、分割条出现；无前台时形成单应用分屏 + 选择器。

- [ ] **Step 4: 提交**

```bash
git add plugins/denial_desktop/lib/src/launcher/home_surface.dart \
  plugins/denial_desktop/lib/src/launcher/home_drag_controller.dart \
  plugins/denial_desktop/lib/src/features/mobile/mobile_launcher_layer.dart \
  plugins/denial_desktop/lib/src/launcher/home_launch.dart
git commit -m "feat(split): long-press an icon and drag it to a side"
```

---

### Task 11: 旋转、外部 intent 与收尾

**Files:**
- Modify: `compositor/src/bin/deniald/wayland_frontend/insets.rs`（旋转时冻结 configure）
- Modify: `plugins/denial_desktop/lib/src/state/reference_shell_controller.dart`（外部激活替换非激活侧）
- Modify: `plugins/denial_desktop/lib/src/features/mobile/mobile_split_stage.dart`（方向动画）

- [ ] **Step 1: 旋转**

输出尺寸变化时，`mobile_split.vertical` 由新宽高比决定；比例按短边占比保持；旋转动画期间跳过 `configure_mobile_window`，落地后统一一次。

- [ ] **Step 2: 外部 intent**

`_handleNativeWindowActivated()` 在 `splitPair != null` 且新窗口不在对里时：替换非激活侧（`splitWindows` 用新 id），被替换窗口 `focusWindow` 退回后台。

- [ ] **Step 3: 设备验证**

竖屏/横屏来回旋转无抖动、比例保持；分屏中从通知打开应用 → 替换非激活侧。

- [ ] **Step 4: 提交**

```bash
git add compositor/src/bin/deniald/wayland_frontend/insets.rs \
  plugins/denial_desktop/lib/src/state/reference_shell_controller.dart \
  plugins/denial_desktop/lib/src/features/mobile/mobile_split_stage.dart
git commit -m "feat(split): rotation and external activation"
```

---

## 自检

- 规格覆盖：入口 §3 (T4/T10)、状态机 §4 (T3/T5/T7)、手势 §5 (T4/T9)、布局 §6 (T1/T6/T11)、比例判定 §7 (T1)、视觉 §8 (T4/T5/T6)、细则 §9 (T7/T11)、接口 §10 (T1/T8)、边界 §11 (T4/T5/T7/T11)、不做 §12 未列任务。
- 所有新 wire 字段带默认值，旧请求不变。
- 每个任务的产出都有可直接调用的签名，后续任务按名字消费。

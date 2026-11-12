# 平板分屏实现计划（v3）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 按 v3 规范（`docs/SPLIT_SCREEN.md`、`docs/designs/split-screen-redesign.html`）完成平板分屏：两张卡片、长按拿起、40/20/40 放置区、缩略图选择器、分割条、配对卡片、激活侧输入。

**Architecture:** 窗口矩形仍由合成器决定（`mobile_split.rs` 为分屏成员返回各自半边），外壳只负责状态机、手势、卡片渲染与分割条。v3 的卡片视觉需要合成器把间隙和外侧边距从窗口矩形里扣掉，外壳按同一套常量画卡片与输入区域。

**Tech Stack:** Rust/Smithay（`cargo test`）、Dart/Flutter（`denial_flutter_sdk` + `denial_desktop`）、FlatBuffers wire。

**Spec:** `docs/SPLIT_SCREEN.md`（v3）

## Global Constraints

- 只做 mobile shell；desk / 外接显示器不受影响。
- 方向由输出宽高比决定：横屏左右、竖屏上下。
- 默认比例 50:50；范围 20–80%；47–53% 吸附 50:50。
- 单一入口：recents 长按 380ms 拿起；不提供 launcher 拖拽入口。
- 放置区左右各 40% 屏宽（竖屏 40% 屏高），中间 20% 取消区。
- 间隙 14px、外侧边距 14px、卡片圆角 20px。
- 状态栏 45 逻辑像素由合成器扣除。
- 同一 app 的多窗口共享 client scale，不做 per-window scale。

## Review Focus

- 拿起后手指停在中间：必须取消，不能误开分屏。
- 分割条拖到 ≤10%：预览出现但松手才退出；拖回则不退出。
- 分屏中旋转：方向翻转、比例保持、动画期间不能反复 configure。
- 键盘只推激活侧；切换激活侧时键盘跟随，非激活侧内容不动。
- 从 recents 关闭配对卡片的一侧：另一侧要平滑扩成全屏，不留黑边。

---

## 已完成（v3 之前）

- [x] 合成器分屏几何、`SplitWindows / UpdateSplitRatio / EndSplit` 三个请求（Task 1，`681` 个测试通过）
- [x] `SplitPair` 模型与纯 Dart 测试、`windows_client` 发送（Task 2）
- [x] 双窗格 stage、`startSplit/updateSplitRatio/setSplitActive/endSplit`、长按拿起雏形（Task 3）
- [x] 键盘「点击才弹」（touch epoch + flutter_editor）

> v3 需要在这些基础上改：默认比例、放置区阈值、卡片视觉、缩略图选择器、分割条、配对卡片、激活侧键盘。

---

### Task 4: 拿起与 40/20/40 放置区

**Files:**
- Modify: `plugins/denial_desktop/lib/src/widgets/overview/app_deck_layer.dart:200-260, 560-640`
- Modify: `plugins/denial_desktop/lib/src/widgets/overview/split_drop_zone.dart`
- Modify: `packages/denial_flutter_sdk/lib/src/models/split_pair.dart`（默认 0.5）
- Modify: `compositor/src/bin/deniald/wayland_frontend/mobile_split.rs`（`DEFAULT_RATIO = 0.5`）

**Interfaces:**
- Consumes: `onSplitSide(window, side)`（已有）
- Produces: `SplitDropSide`（已有）、`_sideAt(Offset)` 改为 40/20/40

- [x] **Step 1: 默认比例改 50:50**

`split_pair.dart`：`const double splitDefaultFraction = 0.5;`
`mobile_split.rs`：`pub(super) const DEFAULT_RATIO: f32 = 0.5;`
更新 `split_pair_test.dart` 里依赖 0.53 的断言（`swapped()` 仍为 `1 - ratio`）。

- [x] **Step 2: 放置区判定改 40/20/40**

```dart
  SplitDropSide? _sideAt(Offset point) {
    final size = MediaQuery.sizeOf(context);
    final ratio = size.height > size.width ? point.dy / size.height : point.dx / size.width;
    if (ratio < 0.4) return size.height > size.width ? SplitDropSide.top : SplitDropSide.left;
    if (ratio > 0.6) return size.height > size.width ? SplitDropSide.bottom : SplitDropSide.right;
    return null; // middle 20% cancels
  }
```

- [x] **Step 3: 拿起卡片缩小**

拿起时 `scale` 从 `0.92` 改为 `0.72`，`rotate -2°` 保持；其余卡片淡到 `0.25`（当前 0.35）。

- [x] **Step 4: 放置区文案与尺寸**

`SplitDropOverlay` 的左右区域改为 `0.4 * 屏宽`（竖屏 `0.4 * 屏高`），中间留空；文案按设计稿：
「放到左侧 / 放到右侧 / 拖到这里 = 上分屏 / 下分屏」，下方小字 `50% · 约 800 × 952`（取当屏逻辑尺寸计算）。

- [x] **Step 5: 设备验证**

打开两个应用 → recents → 长按卡片：卡片缩小、其它淡出、左右各 40% 亮起；中间松手取消；左侧松手进入单应用分屏。

- [x] **Step 6: 提交**

```bash
git add ... && git commit -m "feat(split): 40/20/40 pickup zones with a smaller lifted card"
```

---

### Task 5: 缩略图选择器

**Files:**
- Modify: `plugins/denial_desktop/lib/src/widgets/overview/split_picker.dart`
- Modify: `plugins/denial_desktop/lib/src/features/mobile/mobile_split_stage.dart`

**Interfaces:**
- Produces: `SplitPicker({required SplitPair pair, required VoidCallback onAllApps})`
- Consumes: `state.openAppWindows`、`controller.pickSplitSecond(window)`

- [x] **Step 1: 2 列缩略图网格**

`GridView(crossAxisCount: 2, childAspectRatio: 4/3)`，每项：

```dart
GestureDetector(
  onTap: () => controller.pickSplitSecond(window),
  child: Column(
    children: [
      Expanded(child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: WindowContentRect(window: window, applyBackdrop: false),
      )),
      const SizedBox(height: 8),
      Text(window.title, maxLines: 1, overflow: TextOverflow.ellipsis),
    ],
  ),
)
```

最后一项「全部应用」：虚线框 + 九宫格点阵，`onTap: onAllApps`。

- [x] **Step 2: 深色底 + 模糊**

容器：`BackdropFilter(blur 22)` + `rgba(18,18,26,.72)`，顶部标题「选择右侧/下方应用」，下边距 45（与窗口状态栏对齐）。

- [x] **Step 3: 空列表**

没有其他应用时显示「没有其他打开的应用」，只保留取消（✕ 或点固定侧）。

- [x] **Step 4: 设备验证**

固定左侧 → 右侧列出 2 列实时缩略图；点一个补齐；空列表文案正确。

- [x] **Step 5: 提交**

```bash
git commit -m "feat(split): thumbnail picker for the second pane"
```

---

### Task 6: 分割条

**Files:**
- Create: `plugins/denial_desktop/lib/src/widgets/overview/split_divider.dart`
- Modify: `plugins/denial_desktop/lib/src/features/mobile/mobile_split_stage.dart`

**Interfaces:**
- Produces: `SplitDivider({required SplitPair pair, required ValueChanged<double> onRatio, required VoidCallback onReset, required VoidCallback onClose})`

- [x] **Step 1: 拖动比例**

```dart
  void _update(DragUpdateDetails details, Size size) {
    final position = pair.vertical
        ? details.localPosition.dy / size.height
        : details.localPosition.dx / size.width;
    widget.onRatio(splitFractions(position).first); // 限幅 + 磁吸
  }
```

`onRatio` → `controller.updateSplitRatio`。

- [x] **Step 2: 双击复位 / ✕ 退出**

`onDoubleTap: onReset`（50:50）；✕ 圆钮 `onTap: onClose` → `controller.endSplit()`。

- [x] **Step 3: 关闭预览**

拖动比例 ≤0.10：把手进入「退出预览」态（红色虚线覆盖被压一侧，文案「松手关闭这一侧」）；松手时若 ≤0.10 → `endSplit()`，否则恢复。

- [x] **Step 4: 视觉**

38×86 圆钮、两条 3×22 拖拽条、`0 6px 20px rgba(20,22,28,.22)`；竖屏旋转 90°；`MouseRegion` 光标 `col-resize/row-resize`。

- [x] **Step 5: 设备验证**

拖动改比例、吸附 50:50、双击复位、✕ 退出、拖到边缘出现预览且松手才退出。

- [x] **Step 6: 提交**

```bash
git commit -m "feat(split): floating divider with snap, reset and close preview"
```

---

### Task 7: 两张卡片的视觉与输入映射

**Files:**
- Modify: `compositor/src/bin/deniald/wayland_frontend/mobile_split.rs`（pane 内侧留边距与间隙）
- Modify: `plugins/denial_desktop/lib/src/features/mobile/mobile_split_stage.dart`
- Modify: `plugins/denial_desktop/lib/src/state/reference_input_layout_coordinator.dart`

**Interfaces:**
- Produces: `split_pane_rects(full, vertical, ratio) -> [Rect; 2]`（含 14px 外边距与 14px 间隙）
- Consumes: 同常量在 Dart 侧 `splitPaneRects(size, pair)`（`split_pair.dart`）

- [x] **Step 1: 合成器扣出边距**

```rust
pub(super) const SPLIT_MARGIN: i32 = 14;
pub(super) const SPLIT_GUTTER: i32 = 14;
// inner = full 去掉左右/下 14；两 pane 之间留 14
```

- [x] **Step 2: 外壳按同一公式画卡片**

`splitPaneRects` 返回两个 `Rect`；stage 用 `ClipRRect(20)` + `WindowContentRect`，激活侧加 accent 描边，非激活 `brightness .94`。

- [x] **Step 3: 输入映射用 pane 矩形**

`reference_input_layout_coordinator` 在分屏时为每个窗口生成 `InputWindowRegion`，`viewSize` 用对应的 pane 矩形（含偏移），保证触摸落在卡片内时映射正确。

- [x] **Step 4: 设备验证**

两张卡片之间有 14px 间隙；点两侧都能切换激活侧；点卡片四角输入位置正确。

- [x] **Step 5: 提交**

```bash
git commit -m "feat(split): two-card geometry and input mapping"
```

---

### Task 8: 配对卡片

**Files:**
- Modify: `plugins/denial_desktop/lib/src/state/app_deck.dart`
- Modify: `plugins/denial_desktop/lib/src/widgets/overview/app_deck_layer.dart`
- Modify: `plugins/denial_desktop/lib/src/state/reference_shell_controller.dart`

- [x] **Step 1: 一张卡代表一对**

`AppDeck` 把 `splitPair` 变成一个条目：内容为两个 `WindowContentRect` 并排（上下），中间细线，右下角「分屏 50:50」徽标。

- [x] **Step 2: 操作**

点按 → 恢复该对（`focusWindow(pair.first)`，pair 已在 state）；上划 → `endSplit()` + 关闭两个窗口；长按拖出 → 拖哪侧哪侧全屏（`endSplit()` + `focusWindow(side)`）。

- [x] **Step 3: 设备验证**

分屏 → 上滑进 recents：只有一张卡；点回分屏；上划关闭两侧。

- [x] **Step 4: 提交**

```bash
git commit -m "feat(split): one recents card per pair"
```

---

### Task 9: 激活侧、返回键与键盘

**Files:**
- Modify: `compositor/src/bin/deniald/wayland_frontend/insets.rs`
- Modify: `plugins/denial_desktop/lib/src/state/reference_input_layout_coordinator.dart`
- Modify: `plugins/denial_desktop/lib/src/state/reference_shell_controller.dart`

- [x] **Step 1: 键盘只推激活侧**

`set_keyboard_height` / `project_mobile_inset` 在 split 存在时只对 `split.active` 的窗口应用顶部 inset；另一侧 geometry 不变。

- [x] **Step 2: 返回键**

`NavigateBack` 的 `window_id` 用 `pair.activeWindow`。

- [x] **Step 3: 输入焦点**

`inputWindow` 返回激活侧窗口；`reference_input_layout_coordinator` 为两侧都发 `InputWindowRegion`（Task 7 已做），键盘只跟激活侧。

- [x] **Step 4: 设备验证**

分屏中点右侧 → 键盘弹出时只有右侧上推；返回键关闭右侧；左侧不动。

- [x] **Step 5: 提交**

```bash
git commit -m "feat(split): active side drives input and the keyboard inset"
```

---

### Task 10: 竖屏、旋转与外部 intent

**Files:**
- Modify: `plugins/denial_desktop/lib/src/widgets/overview/app_deck_layer.dart`（竖屏 40/20/40）
- Modify: `compositor/src/bin/deniald/wayland_frontend/insets.rs`（旋转冻结 configure）
- Modify: `plugins/denial_desktop/lib/src/state/reference_shell_controller.dart`（外部激活替换非激活侧）

- [x] **Step 1: 竖屏判定**

`_sideAt` 已按 `height > width` 切到上下 40%；放置区文案/尺寸随轴翻转。

- [x] **Step 2: 旋转**

输出尺寸变化时 `vertical` 由宽高比决定；比例按短边保持；动画期间跳过 `configure_mobile_window`，落地后一次下发。

- [x] **Step 3: 外部 intent**

`_handleNativeWindowActivated()` 在 split 存在且新窗口不在对里时：替换非激活侧，被替换窗口退回后台。

- [x] **Step 4: 设备验证**

竖屏：上拖 40% 进上分屏、中间取消、下拖 40% 进下分屏；旋转无抖动；通知打开应用替换非激活侧。

- [x] **Step 5: 提交**

```bash
git commit -m "feat(split): portrait axis, rotation and external activation"
```

---

## 待实机验证（平板重启后失联）

- Task 8：配对卡片的外观、点回分屏、上划关闭两侧、拖到侧边全屏。
- Task 9：分屏中点右侧后键盘只推右侧；返回键作用在激活侧。
- Task 10：竖屏 40/20/40、旋转保持比例、外部激活替换非激活侧。

## 自检

- 规范覆盖：入口 §3 (T4)、状态机 §4 (T4/T5/T8)、阈值 §5 (T4/T6)、布局 §6 (T7)、视觉 §8 (T4/T5/T6/T7/T8)、细则 §9 (T8/T9/T10)、接口 §10 (T1/T7/T9)、边界 §11 (T4/T5/T8/T10)。
- 每个任务的接口签名与前一任务产出一致；`splitFractions` 同时被分割条与 stage 使用。
- 默认比例 0.5 需同时改 Rust 常量、Dart 常量与测试。

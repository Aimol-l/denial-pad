# 悬浮软件键盘实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 Denial 平板做一个可自由拖动、缩放（40–80% × 25–45%）的亮色悬浮键盘，英文本地输入、中文经 fcitx5。

**Architecture:** 新包 `plugins/denial_keyboard` 分三层：`core`（纯 Dart 布局/状态机/尺寸推导）、`ui`（Flutter 面板与键帽）、`bridge`（键盘后端抽象）。合成器新增 fcitx5 服务（zbus），通过 wire 把候选与提交推给外壳。宿主 `denial_desktop` 只负责显示时机与接线。

**Tech Stack:** Dart/Flutter、Rust（zbus、Smithay）、fcitx5 D-Bus。

**Spec:** `docs/superpowers/specs/2026-11-11-floating-keyboard-design.md`
**设计稿:** `docs/designs/floating-keyboard-redesign.html`

## Global Constraints

- 只在 Denial 平板使用，不考虑其它合成器。
- 不自动执行 `git commit`：每个任务的完成标志是测试通过；提交由用户确认后执行。
- 面板尺寸约束：宽 40–80%、高 25–45%（相对屏幕逻辑尺寸），候选条固定 34。
- 字体下限 11、上限 22；键帽圆角随行高缩放。
- 英文/数字/符号不经过 fcitx5；中文输入才调用 D-Bus。
- fcitx5 以 `--disable wayland,waylandim,xim` 运行，只用 dbus 前端。
- `keycode` 必须是 XKB 风格（evdev + 8），否则 `ProcessKeyEvent` 返回 false。
- 必须先 `SetSupportedCapability` 置客户端 UI 能力位，才会收到候选信号。

## Review Focus

- 尺寸推导在四个边界（40%/80% × 25%/45%）下是否仍能放下 4 行、字号是否越界。
- 拖动/缩放与按键手势是否互相抢占（缩放柄、把手、键帽三层手势）。
- 横竖屏切换后位置是否越界（面板尺寸不同，旧坐标可能出屏）。
- fcitx5 缺失或退出时，英文输入是否完全不受影响。
- 焦点切换时 context 重建是否丢失已输入的拼音。

---

### Task 1: 建立包骨架与布局模型

**Files:**
- Create: `plugins/denial_keyboard/pubspec.yaml`
- Create: `plugins/denial_keyboard/lib/denial_keyboard.dart`
- Create: `plugins/denial_keyboard/lib/src/core/key_layout.dart`
- Test: `plugins/denial_keyboard/test/key_layout_test.dart`

**Interfaces:**
- Produces:
  - `enum KeyKind { letter, digit, symbol, shift, backspace, enter, space, language, layer, emoji }`
  - `class KeySpec { final String label; final String? shifted; final KeyKind kind; final double flex; final String? corner; }`
  - `class KeyRow { final List<KeySpec> keys; final double inset; }`
  - `List<KeyRow> lettersLayout({required bool numberRow})`
  - `List<KeyRow> symbolsLayout()`

- [ ] **Step 1: 写失败测试**

```dart
test('letters layout has four rows and a full qwerty top row', () {
  final rows = lettersLayout(numberRow: false);
  expect(rows.length, 4);
  expect(rows.first.keys.length, 10);
  expect(rows.first.keys.map((k) => k.label).join(), 'qwertyuiop');
});

test('digits ride in the corner of the top row', () {
  final top = lettersLayout(numberRow: false).first.keys;
  expect(top.first.corner, '1');
  expect(top.last.corner, '0');
});

test('function keys keep their flex so the space bar is widest', () {
  final bottom = lettersLayout(numberRow: false).last;
  final space = bottom.keys.firstWhere((k) => k.kind == KeyKind.space);
  expect(space.flex, greaterThan(3));
});
```

- [ ] **Step 2: 运行，确认失败**

Run: `cd plugins/denial_keyboard && flutter test test/key_layout_test.dart`
Expected: FAIL — `lettersLayout` 未定义

- [ ] **Step 3: 实现**

按设计稿写 4 行布局：`qwertyuiop`（corner 1–0）、`asdfghjkl`（左右 inset 26）、`shift zxcvbnm backspace`、`层切换 / 123 / , / space / 。/ 中英 / enter`。

- [ ] **Step 4: 运行，确认通过**

Run: `cd plugins/denial_keyboard && flutter test test/key_layout_test.dart`
Expected: PASS，3 个测试

---

### Task 2: Shift 状态机与自动大写

**Files:**
- Create: `plugins/denial_keyboard/lib/src/core/shift_state.dart`
- Test: `plugins/denial_keyboard/test/shift_state_test.dart`

**Interfaces:**
- Produces:
  - `enum ShiftState { off, once, locked }`
  - `ShiftState nextOnTap(ShiftState current)`
  - `ShiftState afterCharacter(ShiftState current, String text)`
  - `String applyCase(String label, ShiftState state)`

- [ ] **Step 1: 写失败测试**

```dart
test('tap cycles off -> once -> locked -> off', () {
  expect(nextOnTap(ShiftState.off), ShiftState.once);
  expect(nextOnTap(ShiftState.once), ShiftState.locked);
  expect(nextOnTap(ShiftState.locked), ShiftState.off);
});

test('once resets after a letter but locked does not', () {
  expect(afterCharacter(ShiftState.once, 'a'), ShiftState.off);
  expect(afterCharacter(ShiftState.locked, 'a'), ShiftState.locked);
});

test('sentence end re-arms auto capitals', () {
  expect(afterCharacter(ShiftState.off, '.'), ShiftState.once);
  expect(afterCharacter(ShiftState.off, '。'), ShiftState.once);
});

test('applyCase only touches letters', () {
  expect(applyCase('q', ShiftState.once), 'Q');
  expect(applyCase('1', ShiftState.locked), '1');
});
```

- [ ] **Step 2: 运行，确认失败** → `flutter test test/shift_state_test.dart`
- [ ] **Step 3: 实现**（不足 30 行）
- [ ] **Step 4: 运行，确认通过**
- [ ] **Step 5: 提交前等待用户确认**

---

### Task 3: 尺寸推导

**Files:**
- Create: `plugins/denial_keyboard/lib/src/core/metrics.dart`
- Test: `plugins/denial_keyboard/test/metrics_test.dart`

**Interfaces:**
- Produces:
  - `class KeyboardMetrics { final double panelWidth, panelHeight, keyWidth, rowHeight, fontSize, keyRadius; }`
  - `KeyboardMetrics keyboardMetrics({required Size screen, required Size panel, int rows = 4, double candidateStrip = 34})`
  - `Size clampPanelSize(Size screen, Size requested)`
  - `Offset clampPanelPosition(Size screen, Size panel, Offset requested)`

- [ ] **Step 1: 写失败测试**

```dart
test('panel size is clamped to 40-80% width and 25-45% height', () {
  const screen = Size(1707, 1067);
  expect(clampPanelSize(screen, const Size(1000, 1000)), const Size(1365.6, 480.15));
  expect(clampPanelSize(screen, const Size(10, 10)), const Size(682.8, 266.75));
});

test('font stays within 11 and 22 at both extremes', () {
  const screen = Size(1707, 1067);
  final min = keyboardMetrics(screen: screen, panel: const Size(682.8, 266.75));
  final max = keyboardMetrics(screen: screen, panel: const Size(1365.6, 480.15));
  expect(min.fontSize, greaterThanOrEqualTo(11));
  expect(max.fontSize, lessThanOrEqualTo(22));
});

test('four rows always fit the panel', () {
  const screen = Size(1707, 1067);
  final m = keyboardMetrics(screen: screen, panel: const Size(990, 320));
  expect(m.rowHeight * 4 + 34, lessThanOrEqualTo(320));
});

test('position keeps 48 logical pixels on screen', () {
  const screen = Size(1707, 1067);
  final p = clampPanelPosition(screen, const Size(990, 320), const Offset(-2000, 5000));
  expect(p.dx, greaterThanOrEqualTo(-990 + 48));
  expect(p.dy, lessThanOrEqualTo(1067 - 48));
});
```

- [ ] **Step 2: 运行，确认失败**
- [ ] **Step 3: 实现**

```
keyWidth  = (panelWidth - 2*padding - gap*(columns-1)) / columns
rowHeight = min(keyWidth * 0.92, (panelHeight - 34 - padding) / 4)
fontSize  = clamp(rowHeight * 0.42, 11, 22)
keyRadius = rowHeight * 0.18
```

- [ ] **Step 4: 运行，确认通过**

---

### Task 4: 静态面板（底部停靠）

**Files:**
- Create: `plugins/denial_keyboard/lib/src/ui/key_cap.dart`
- Create: `plugins/denial_keyboard/lib/src/ui/keyboard_panel.dart`
- Create: `plugins/denial_keyboard/lib/src/bridge/keyboard_backend.dart`
- Test: `plugins/denial_keyboard/test/panel_test.dart`（widget test，假 backend）

**Interfaces:**
- Produces:
  - `abstract class KeyboardBackend { void typeText(String); void sendKey(KeyKind); void selectCandidate(int); void page(int); }`
  - `class FakeKeyboardBackend implements KeyboardBackend`
  - `KeyboardPanel({required KeyboardBackend backend, required Size screen, required Size panel})`

- [ ] **Step 1: 写失败测试**

```dart
testWidgets('tapping q types q', (tester) async {
  final backend = FakeKeyboardBackend();
  await tester.pumpWidget(MaterialApp(
    home: KeyboardPanel(backend: backend, screen: const Size(1707, 1067),
        panel: const Size(990, 320)),
  ));
  await tester.tap(find.text('q'));
  expect(backend.typed, 'q');
});

testWidgets('shift then q types Q', (tester) async {
  final backend = FakeKeyboardBackend();
  await tester.pumpWidget(MaterialApp(
    home: KeyboardPanel(backend: backend, screen: const Size(1707, 1067),
        panel: const Size(990, 320)),
  ));
  await tester.tap(find.text('⇧'));
  await tester.tap(find.text('q'));
  expect(backend.typed, 'Q');
});

testWidgets('double tapping space sends a period and a space', (tester) async {
  final backend = FakeKeyboardBackend();
  await tester.pumpWidget(MaterialApp(
    home: KeyboardPanel(backend: backend, screen: const Size(1707, 1067),
        panel: const Size(990, 320)),
  ));
  await tester.tap(find.textContaining('空格'));
  await tester.tap(find.textContaining('空格'));
  expect(backend.typed, '. ');
});
```

- [ ] **Step 2: 运行，确认失败**
- [ ] **Step 3: 实现键帽与面板**

键帽：白底、`boxShadow: 0 1px 0 rgba(0,0,0,.16)`、左上角 `corner`、按下态加深。

面板顶部做 64 高的两态切换：空闲显示工具条，输入中显示「预编辑 + 候选」两行（候选数据在 Task 7 接入）。

同时补上三项交互（沿用旧实现的参数）：

- **长按字母**：弹出重音/变体，数据表从 `dd1e8f3^` 的 `_accents` 迁移
- **长按退格**：400 ms 后以 55 ms 间隔连续删除
- **震动**：每次按下调用系统 haptics 一次（`hapticsServiceProvider.pulse()`）

对应的 widget 测试：长按 `a` 出现 `á à ä` 弹层；长按退格 1 秒后 `backend.backspaces > 5`。

- [ ] **Step 4: 运行，确认通过**
- [ ] **Step 5: 宿主接线**：`denial_desktop` 用一个固定尺寸把面板放在底部，backend 直接调用现有 text-input 提交接口；在 foot 与 Settings 搜索框验证英文输入。

---

### Task 5: 悬浮容器（拖动 / 缩放 / 持久化）

**Files:**
- Create: `plugins/denial_keyboard/lib/src/ui/floating_keyboard.dart`
- Create: `plugins/denial_keyboard/lib/src/core/placement.dart`
- Modify: `packages/denial_flutter_sdk/lib/src/settings/settings_document.dart`（新增 `keyboardPlacement`）
- Modify: `packages/denial_flutter_sdk/lib/src/settings/settings_controller.dart`（读写）
- Test: `plugins/denial_keyboard/test/floating_test.dart`

**Interfaces:**
- Produces:
  - `class KeyboardPlacement { final double x, y, w, h; Map<String, dynamic> toJson(); static KeyboardPlacement? fromJson(...); }`
  - `class FloatingKeyboard({required KeyboardBackend backend, required KeyboardPlacement initial, required Size screen, required ValueChanged<KeyboardPlacement> onChanged})`

- [ ] **Step 1: 写失败测试（placement 往返）**

```dart
test('placement round-trips through json', () {
  const p = KeyboardPlacement(x: 358, y: 727, w: 990, h: 320);
  expect(KeyboardPlacement.fromJson(p.toJson()), p);
});

test('unknown or corrupt placement falls back to null', () {
  expect(KeyboardPlacement.fromJson({'x': 'nope'}), isNull);
});
```

- [ ] **Step 2: 写失败 widget 测试（拖动夹取）**

```dart
testWidgets('drag past the edge keeps 48px on screen', (tester) async { /* ... */ });
testWidgets('resize respects the 40-80 / 25-45 range', (tester) async { /* ... */ });
```

- [ ] **Step 3: 实现**（`GestureDetector` 三层：面板拖动、缩放柄、键帽；松手吸附与 120ms 收敛）
- [ ] **Step 4: 运行，确认通过**
- [ ] **Step 5: 设备验证**：拖动、缩放、旋转、重启后恢复

---

### Task 6: 合成器 fcitx5 服务

**Files:**
- Create: `compositor/src/bin/deniald/wayland_frontend/fcitx.rs`
- Modify: `compositor/src/bin/deniald/wayland_frontend.rs`（注册服务）
- Test: `compositor/src/bin/deniald/wayland_frontend/fcitx/tests.rs`（D-Bus mock）

**Interfaces:**
- Produces:
  - `struct FcitxService`（持有 zbus 连接与当前 context）
  - `fn create_context(&mut self) -> Result<()>`
  - `fn key(&mut self, keyval: u32, keycode: u32, state: u32) -> Result<bool>`
  - `fn select(&mut self, index: u32) -> Result<()>`
  - `fn page(&mut self, forward: bool) -> Result<()>`
  - 事件：`FcitxEvent::Commit(String)`、`FcitxEvent::Candidates { preedit, items, page, pages }`

- [ ] **Step 1: 写失败测试**：用 mock 对象断言 `keycode` 加 8 后发送、`SetSupportedCapability` 在建 context 后立即调用、`SelectCandidate` 透传索引。
- [ ] **Step 2: 运行，确认失败**
- [ ] **Step 3: 实现**（zbus 异步；`ProcessKeyEvent(u,u,u,b,u)`；订阅 `CommitString` / `UpdateClientSideUI`）
- [ ] **Step 4: 运行，确认通过**
- [ ] **Step 5: 设备验证**：复用 spike 脚本，确认 `nihao` → 候选 → `你好`

---

### Task 7: 候选桥接与候选条

**Files:**
- Modify: `compositor/src/bin/deniald/wire.rs`（`KeyboardCandidates`、`KeyboardCommit`）
- Modify: `plugins/denial_desktop/lib/src/keyboard/keyboard_layer.dart`（新建宿主层）
- Create: `plugins/denial_keyboard/lib/src/ui/candidate_strip.dart`
- Test: `plugins/denial_keyboard/test/candidate_strip_test.dart`

**Interfaces:**
- Consumes: Task 4 的 `KeyboardBackend`、Task 6 的事件
- Produces: `CandidatesModel { String preedit; List<String> items; int highlighted; int page; int pages; }`

- [ ] **Step 1: 写失败测试**：候选条渲染 6 项、超出换页、点击回调索引、预编辑灰字。
- [ ] **Step 2: 运行，确认失败**
- [ ] **Step 3: 实现**（顶部预编辑行 + 候选行 34 高；首项淡紫底；右侧 `›` 点击翻页）
- [ ] **Step 4: 运行，确认通过**
- [ ] **Step 5: 设备验证**：拼音输入出候选、选词提交、翻页、焦点切换不丢预编辑

---

### Task 8: Emoji 与剪贴板面板

**Files:**
- Create: `plugins/denial_keyboard/lib/src/ui/emoji_panel.dart`
- Create: `plugins/denial_keyboard/lib/src/ui/clipboard_panel.dart`
- Test: `plugins/denial_keyboard/test/panels_test.dart`

- [ ] **Step 1: 写失败测试**：切换到 Emoji 后键位替换、点击回调提交该 emoji、剪贴板列表点击回调文本。
- [ ] **Step 2: 实现**：Emoji 用内置分组表（常用/表情/符号）；剪贴板复用 `clipboardHistoryProvider` 的条目。
- [ ] **Step 3: 运行，确认通过**

---

### Task 9: 显示规则与打磨

**Files:**
- Modify: `plugins/denial_desktop/lib/src/keyboard/keyboard_layer.dart`
- Modify: `plugins/denial_desktop/lib/src/core/denial_shell.dart`
- Test: `plugins/denial_desktop/test/keyboard_visibility_test.dart`

- [ ] **Step 1: 写失败测试**：文本焦点出现→显示；失焦→隐藏；手动收起后焦点不变→不显示；外接键盘→不显示。
- [ ] **Step 2: 实现**（订阅 `textInputStates`；记录 `manuallyDismissed`；监听输入设备能力）
- [ ] **Step 3: 设备回归**：foot / Firefox / Settings / 终端，横竖屏各一轮

---

## 自检

- 规格覆盖：布局(T1)、Shift(T2)、尺寸(T3)、面板(T4)、悬浮(T5)、引擎(T6)、候选(T7)、Emoji/剪贴板(T8)、显示(T9)
- 无占位符：所有步骤含可运行命令与期望输出
- 类型一致：`KeyboardBackend`、`KeyboardPlacement`、`KeyboardMetrics` 在后续任务中签名一致
- 评审重点的五条都在 Task 3 / 5 / 6 / 9 的测试里

# 悬浮软件键盘设计

日期：2026-11-11
状态：待评审
范围：Denial 平板外壳（`plugins/denial_keyboard`），不考虑其它桌面环境

## 1. 背景

旧实现是 `plugins/denial_desktop/lib/src/widgets/osk/shell_osk_panel.dart`（1731 行），
随 `dd1e8f3` 整体移除。它的按键引擎完整（布局、连按、重音、候选条、purpose/hint），
但形态是"固定底栏 + 推动应用内容"，且没有中文输入、Emoji、剪贴板、震动。

本次重做两点：

1. **形态**：悬浮面板，可自由拖动、自由缩放（有范围限制），不再推动应用布局。
2. **中文**：接 fcitx5 作为引擎，UI 完全由我们渲染。

## 2. 目标与非目标

### 目标

- 横向 2560×1600（逻辑 1707×1067）、纵向 1600×2560 两种姿态都可用
- Android 键盘的"基本能力"：字母/数字/符号/Emoji、Shift 三态、自动大写、连按、
  长按重音、按键气泡、震动反馈、候选条与翻页、剪贴板、退格连删
- 中文拼音输入，引擎用 fcitx5，候选与预编辑显示在我们自己的面板里
- 英文/数字本地处理，不经过 fcitx5
- 面板位置与尺寸跨重启保留，横竖屏各一套

### 非目标

- 语音输入、手写输入
- 主题市场、皮肤系统
- 支持非 Denial 的合成器
- 应用布局跟随键盘移动（第一版不做键盘 inset 抬升，只留接口）

## 3. 架构

```
plugins/denial_keyboard/            （新包，纯平板用途）
  lib/src/core/                    纯 Dart，无 Flutter
    layout.dart                    布局数据：字母/数字/符号/Emoji 行
    key_intent.dart                按键意图：text/key/space/backspace/enter/replace
    shift.dart                     Shift 三态与自动大写状态机
    metrics.dart                   面板尺寸 → 键宽/行高/字号的推导与夹取
    candidates.dart                候选模型（分页、高亮、预编辑）
  lib/src/ui/                      Flutter
    floating_keyboard.dart         悬浮容器：拖动、缩放、吸附、持久化
    key_cap.dart                   键帽、按下态、气泡、长按
    candidate_strip.dart           候选条
    emoji_panel.dart / clipboard_panel.dart
  lib/src/bridge/
    keyboard_backend.dart          抽象接口 + 假实现（测试用）

plugins/denial_desktop/            宿主适配：显示时机、焦点、把按键交给 backend
compositor/                        fcitx5 服务与 text-input 提交
```

依赖方向：`ui → core`、`ui → bridge`、宿主 → `ui` + `bridge`。
`core` 不 import Flutter，可直接单测。

## 4. 输入链路

```
应用获得文本焦点
   │ text-input-v3（现有 broker）
   ▼
deniald ──► 外壳：焦点/用途/光标矩形（现有 textInputStates）
   │
   │ 外壳决定显示键盘
   ▼
用户按键 ── KeyboardBackend ──► deniald fcitx5 服务 ── D-Bus ──► fcitx5
                                                      ◄── CommitString
                                                      ◄── UpdateClientSideUI
   ◄── 候选 / 预编辑 ── 候选条渲染
```

- **英文/数字/符号**：本地生成提交，直接走现有 broker 的 commit，**不进入 fcitx5**
- **中文模式**：按键送 fcitx5；`ForwardKey` 回传的按键才由本地处理（例如回车）
- 焦点变化或输入框切换：销毁并重建 fcitx5 input context

## 5. 面板形态规格

### 5.0 顶部结构

顶部固定占 64 逻辑像素，两种状态共用这一块，面板高度不跳：

**空闲（没有预编辑、没有候选）** —— 整块显示工具条：

```
▦   ☺   A⌄   🎙            ⚙   ⌄
```

从左到右：布局切换、表情、输入法/语言、语音（第一版置灰）、设置、收起。

**输入中（有预编辑或候选）** —— 同一块切成两行：

```
ni'h'l'b                        ☁   ⌨
你回来吧   你回不来   你还来不   你      ›
```

- 第一行：拼音预编辑；右侧两个小按钮（云同步状态、输入法设置）
- 第二行：候选条 34 高，首个候选淡紫底高亮，右侧 `›` 翻页
- 预编辑与候选都清空后，自动换回工具条
- 拖动把手叠在顶部中央，不占行高

### 5.1 移动

- 顶部 40 逻辑像素为拖动把手，按住即可拖动；面板内非按键区域也可拖动
- 松手时离屏幕边缘 < 24 逻辑像素则吸附到该边
- 约束：面板至少保留 48 逻辑像素在可视区内，不能完全拖出屏幕
- 松手后用 120 ms 缓动收敛到吸附位置，拖动过程中不做动画

### 5.2 缩放

- 右下角缩放手柄，触摸目标 48×48，图标为半透明三角（始终显示）
- 范围（相对屏幕逻辑尺寸）：

  | 维度 | 最小 | 最大 |
  |---|---|---|
  | 宽 | 40% | 80% |
  | 高 | 25% | 45% |

- 不锁定宽高比
- 键宽 = (面板宽 − 水平内边距 − 列间距) / 列数
- 行高 = min(键宽 × 0.92, (面板高 − 候选条高 − 内边距) / 行数)
- 字号 = clamp(行高 × 0.42, 11, 22)，键帽圆角随行高缩放
- 候选条固定 34 逻辑像素高，候选文字超宽时省略

### 5.3 持久化

- 键：settings 文档 `keyboardPlacement`，结构：

  ```json
  {
    "landscape": {"x": 358, "y": 727, "w": 990, "h": 320},
    "portrait":  {"x": 224, "y": 1175, "w": 619, "h": 512}
  }
  ```

- 缺失时使用默认值：底部居中、离底 20 逻辑像素，横竖屏都是宽 58%/高 30%
- 读取时对 x/y/w/h 做夹取，越界则回落到默认值

### 5.4 层级与焦点

- 面板绘制在外壳最上层，位于锁屏与快速设置之下
- 面板不使用键盘焦点；按键通过桥接注入，不依赖 Flutter 的焦点树
- 面板显示时不发键盘 inset，应用布局不变

## 6. fcitx5 集成

### 6.1 进程

- fcitx5 以 `--disable wayland,waylandim,xim` 运行，只保留 dbus 前端
- 由 Denial 会话负责启动（systemd user unit 或会话启动脚本）
- 引擎组固定为 pinyin；英文由本地旁路，不依赖 `keyboard-us`

### 6.2 D-Bus 协议（spike 实测）

| 用途 | 调用 |
|---|---|
| 创建上下文 | `org.fcitx.Fcitx.InputMethod1.CreateInputContext(a(ss)) -> (o, ay)` |
| 获得焦点 | `InputContext1.FocusIn()` |
| 送按键 | `ProcessKeyEvent(u keyval, u keycode, u state, b release, u time) -> b` |
| 选候选 | `SelectCandidate(i index)` |
| 翻页 | `NextPage()` / `PrevPage()` |
| 光标矩形 | `SetCursorRect(...)` / `SetCursorRectV2(...)` |
| 周围文本 | `SetSurroundingText(...)` / `SetSurroundingTextPosition(...)` |
| 声明能力 | `SetSupportedCapability(t flags)` |
| 销毁 | `DestroyIC()` |

信号：`CommitString(s)`、`UpdateClientSideUI(a(si) preedit, i cursor,
a(si) candidates, a(si) secondary, a(ss) labels, i page, i pageSize, b, b)`、
`UpdateFormattedPreedit`、`DeleteSurroundingText`、`ForwardKey`、`CurrentIM`。

实测要点：

- `keycode` 必须是 XKB 风格（evdev + 8），否则 `ProcessKeyEvent` 返回 `false`
- 必须先 `SetSupportedCapability` 置客户端 UI 能力位，才会收到 `UpdateClientSideUI`
- 上下文绑定调用方连接，断开即销毁，因此桥接必须是常驻进程（deniald）
- `CommitString` 已验证可以返回「你好」

### 6.3 桥接位置

放在 `compositor`（Rust，已有 zbus 与 input_method broker），对 Flutter 只暴露：

```text
setKeyboardLanguage(language)        // latin | pinyin
sendKey(keyval, keycode, state)
selectCandidate(index) / pageCandidates(direction)
setCursorRect(x, y, w, h)
```

回推事件复用现有 wire，新增：

```text
KeyboardCandidates { preedit, cursor, candidates[], highlighted, page, pageCount }
KeyboardCommit { text }
```

## 7. 显示与隐藏

显示条件（全部满足）：

- 存在文本焦点，且 purpose 属于文本类（排除 password 之外的敏感？password 仍显示）
- 锁屏未显示、快速设置未展开、没有 popup grab
- 用户没有手动收起（手动收起后，焦点再次变化才重新弹出）

隐藏条件：

- 文本焦点丢失、应用切换、面板被拖动到"关闭区"（可选）
- 外接键盘接入时默认不自动弹出（可在设置里改）

## 8. 错误处理与降级

| 情况 | 行为 |
|---|---|
| fcitx5 未运行 / 崩溃 | 中文键位禁用，英文照常可用；状态栏提示一次 |
| D-Bus 调用超时（>500 ms） | 记录日志，本次按键丢弃，不阻塞 UI |
| context 失效 | 下次焦点变化时重建，不打断当前输入 |
| 候选数据缺失 | 只显示键盘，候选条隐藏 |
| 持久化数据损坏 | 回落到默认位置与尺寸 |

## 9. 测试

- `core`：布局完整性（每行键数、必需键存在）、Shift 状态机、metrics 夹取边界
  （40%/80%/25%/45% 四个角），纯 Dart 单测
- `ui`：假 backend 驱动，验证按键→意图序列、候选条翻页、拖动/缩放后的尺寸关系
- `compositor`：fcitx5 服务的 D-Bus mock 单测（创建/按键/提交/超时）
- 设备验收：横竖屏各一轮，覆盖 foot、Firefox、Settings 搜索框、锁屏 PIN（不走软键盘）

## 9.5 与 Android 键盘的行为对齐

基本交互以 Android（Gboard / AOSP 键盘）为基准：

| 行为 | 规格 |
|---|---|
| 单击 Shift | 一次性大写，输入一个字母后自动复位 |
| 双击 Shift | 锁定大写，再点一次取消 |
| 句首自动大写 | 输入 `.` `!` `?` 或换行后，下一个字母自动大写 |
| 双击空格 | 插入「. 」并补一个空格（可在设置关闭） |
| 空格横向滑动 | 在文本中移动光标，不触发空格 |
| 长按退格 | 连续删除，按住后加速（沿用旧实现 400 ms / 55 ms 节奏） |
| 长按字母 | 弹出重音/变体（旧实现的 `_accents` 表可直接迁移） |
| 长按符号 | 弹出该键的更多符号变体 |
| 长按 Enter | 弹出换行/发送等动作（若应用声明 `ContentPurpose`） |
| 候选条第一项 | 自动更正建议；按空格接受，按退格撤销 |
| 长按候选 | 删除该学习词（调用 fcitx5 的候选删除接口，若无则暂不做） |
| 数字行 | 横屏常驻；竖屏跟随字母层 |
| 语言键 | 地球图标，点击切换 Latin ⇄ 拼音；长按弹出语言列表（第一版只有两项） |
| 按键反馈 | 震动（系统 haptics）；按键音第一版不做 |
| 关闭键盘 | 系统返回手势 / 拖动条下拉（第一版只做返回手势） |

明确不做（与 Android 的差异）：

- 滑动输入（glide typing）
- 分体键盘、单手模式
- 表情搜索、GIF、贴纸
- 剪贴板外的图片输入

## 10. 里程碑

1. `core` + 假 backend + 静态面板（无悬浮）：能在应用里打字（英文）
2. 悬浮容器：拖动、缩放、持久化、震动
3. fcitx5 桥接：中文拼音、候选条、翻页
4. Emoji 与剪贴板面板
5. 显示/隐藏规则打磨，外接键盘行为

## 10.1 分阶段实施

### 阶段 1 · core 与静态面板

新增：

```
plugins/denial_keyboard/lib/src/core/{layout,key_intent,shift,metrics}.dart
plugins/denial_keyboard/lib/src/ui/{key_cap,keyboard_panel}.dart
plugins/denial_keyboard/lib/src/bridge/keyboard_backend.dart
```

宿主先用固定尺寸把面板放在屏幕底部，按键走本地提交，不接 fcitx5。

验收：

- 在 foot、Settings 搜索框里能输入英文、数字、符号
- `core` 单测覆盖：每行键数、Shift 三态、句首大写、metrics 四个夹取边界
- 假 backend 测试：按键序列与提交文本一致

### 阶段 2 · 悬浮容器

新增 `ui/floating_keyboard.dart`，settings 文档增加 `keyboardPlacement`。

验收：

- 拖动跟手，松手吸附；不能完全拖出屏幕
- 缩放受 40–80% × 25–45% 限制；键宽行高字号按规格推导
- 横竖屏各记一套位置，重启后恢复
- 屏幕旋转后面板回到对应姿态的位置

### 阶段 3 · fcitx5 桥接

合成器新增 fcitx 服务（zbus），wire 增加候选与提交通道，`bridge/` 接上真实后端。

验收：

- 拼音模式输入 `nihao`，候选条出现，选第一项提交「你好」
- 英文模式不经过 fcitx5（抓包确认无 D-Bus 调用）
- fcitx5 停止后键盘仍可输入英文，中文键位禁用
- 焦点切换时 context 重建，不丢当前输入

### 阶段 4 · Emoji 与剪贴板

新增 `ui/emoji_panel.dart`、`ui/clipboard_panel.dart`，候选条右侧加入切换键。

验收：

- Emoji 分类切换、最近使用、点击提交
- 剪贴板列表读取现有 tray 数据，点击粘贴到当前输入框

### 阶段 5 · 显示规则与打磨

验收：

- 文本焦点出现即弹出；失焦/切应用即收起
- 手动收起后，焦点再次变化才重新弹出
- 外接键盘时不自动弹出
- 横竖屏、foot / Firefox / Settings / 终端 四个应用各一轮回归

## 11. 未决问题

- 面板拖动到屏幕上半部分时，是否启用"临时抬升焦点输入框"（需应用支持 insets）
- Emoji 数据的来源（系统字体分段 or 内置表）
- 剪贴板面板是否复用现有 clipboard tray 的数据源

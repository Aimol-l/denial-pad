# 应用商店聚合插件 denial_appstore — 设计规范

> 配套设计讨论：2026-11-11（brainstorming）
> 状态：设计已确认，待实现
> 范围：Denial 专属插件。GNOME 不在考虑范围（后续将移除）。

---

## 1. 目标与范围

做一个 Denial 专属的**应用管理聚合插件** `denial_appstore`，把平板上分散的应用来源收拢到一个入口：

| 后端 | 一期（MVP） | 二期 | 三期 |
|---|---|---|---|
| pacman（官方库 + 本地 AUR 仓库） | ✅ | | |
| 安卓（droidloom 的 Android 应用） | ✅ | | |
| flatpak | | ✅ | |
| 玲珑（linyaps） | | | ✅（待 Arch ARM 可行性验证） |

原则：

- **安装/卸载走各后端自己的命令行**，插件只做 UI 聚合与调度，不自建包管理
- **launcher 长按不提供管理动作**，所有管理收拢到本插件；settings 仅保留一个本地"卸载"快捷项（不碰仓库搜索）
- 插件不改变任何后端的包格式，不引入新的分发渠道

## 2. 术语

| 术语 | 含义 |
|---|---|
| 后端（backend） | 一个包管理来源，实现统一接口 |
| 应用（App） | UI 层的统一模型，一个桌面入口/一个包/一个 Android package |
| 包（package） | pacman 的包，可能与"应用"一对一、一对多或一对零 |
| 本地 AUR 仓库 | 平板上已有的预编译 AUR 包仓库（`[aur]`），对 pacman 透明 |

## 3. 信息架构

### 3.1 入口与形态

- launcher 中一个固定图标进入，打开为**全屏移动窗口**（mobile shell 策略，与分屏稿一致）
- **左侧 navigation rail**（非底部 tab）：横屏持握时拇指自然停在侧边，rail 更近且省竖向空间（对齐 Play 平板范式与玲珑商店布局）

rail 分三组：

| 组 | 项 |
|---|---|
| 内容分类 | 推荐 / 全部 / 排行 / 更新（带红色 badge） |
| 主题分类 | 办公 / 系统 / 开发 / 娱乐 |
| 底部管理 | 已装（带数量 badge）/ 设置 |

搜索框位于 rail 顶部（横跨左栏），与玲珑商店一致。

### 3.2 主要页面

| 页面 | 内容 |
|---|---|
| **推荐**（首页） | 顶部 banner 轮播（单卡 + 左右箭头 + 指示点）；Android APK 安装卡；"为你推荐"两列紧凑卡（图标 + 名称 + 描述 + 右侧 pill 按钮：安装/更新/已装） |
| **全部 / 主题分类** | 顶部分类胶囊 + 两列紧凑卡流，pacman 与 Android 结果混排、徽标区分 |
| **搜索** | **双栏**：左结果列表（按来源分组，含 Android"安装 APK"特殊项）+ 右实时详情（截图 + 描述 + KV），点左栏即换右栏，不跳出当前流 |
| **已装** | 统一列表：Android / pacman 应用分区；行内"可更新"徽标；命令行工具（Console）折叠；点入详情 |
| **更新** | 按来源分组；pacman 组"全部更新"一次提权；Android 组只给"选 APK"覆盖安装 |

### 3.3 主题与配色

- **所有交互 accent 元素**（按钮、rail 选中 pill、banner 按钮、更新徽标、搜索聚焦边框、对话框主按钮）取自 Denial settings 的**全局色调**（用户选色或"从壁纸取色"），立即生效，**商店内禁止硬编码主题色**
- **语义色不随主题变化**，因为它们编码信息而非交互状态：
  - 来源徽标：extra 官方库 `#1793d1` / 本地 AUR 仓库 `#d97706` / Android `#1f9d55`
  - 提权警示：琥珀 `#d97706` 系（对话框预告条）
  - 危险操作：红 `#c9483f` 系（卸载按钮、更新 badge 红点）

### 3.4 统一应用模型

```rust
struct App {
    id: String,              // 后端内唯一（pacman 包名 / Android package name）
    backend: BackendId,      // pacman / android（二期 flatpak / linyaps）
    name: String,
    icon: Option<PathBuf>,   // 后端提供的图标路径，可能为空
    version: String,
    kind: AppKind,           // Graphical / Console / Android
    installed: bool,
    description: Option<String>,
}

enum AppKind {
    Graphical,   // 有 .desktop 入口（或 Android 有 launcher activity）
    Console,     // pacman 纯命令行包：已装列表默认折叠，可用过滤器展开
    Android,     // droidloom 的 Android 应用
}
```

**pacman 的包→应用映射**：一个包可能对零个或多个 `.desktop`。规则：

- UI 列表按 `.desktop` 入口聚合展示；无桌面入口的包归入 `Console` 分类
- 详情页展示该包的全部桌面入口与包级信息（依赖、体积、安装原因）
- 卸载操作以**包**为单位（卸载包会移除其全部入口），UI 明示

## 4. 后端架构

### 4.1 目录结构

```
plugins/denial_appstore/
├── core/                 # Rust crate：后端逻辑与 CLI 封装
│   ├── backend.rs        # PackageBackend trait
│   ├── pacman.rs         # pacman 后端
│   └── android.rs        # 安卓后端
└── lib/
    ├── src/ui/           # Dart UI（浏览 / 已装 / 更新）
    └── src/state/        # 聚合状态、后端调度、缓存
```

与其他插件一致的 core/UI 分离结构（参考 `plugins/denial_keyboard`）。

### 4.2 trait 定义

```rust
trait PackageBackend {
    fn id(&self) -> BackendId;
    fn list_installed(&self) -> Result<Vec<App>>;
    fn search(&self, query: &str) -> Result<Vec<App>>;   // 安卓返回空
    fn install(&self, id: &str) -> Result<()>;           // 安卓：id 为 APK 路径
    fn remove(&self, id: &str) -> Result<()>;
    fn updates(&self) -> Result<Vec<Update>>;
}
```

### 4.3 调度与隔离

- 状态层并发调用各后端，**任一后端失败不阻塞其他后端**（浏览页按源分区，失败的源显示"该源暂不可用"占位）
- 刷新由用户下拉触发 + 进入页面时自动刷新；不做后台常驻轮询
- 已装列表走本地缓存（pacman 本地查询快；安卓 pm 查询快），浏览/更新走实时

## 5. pacman 后端（一期）

### 5.1 能力来源

- 官方库（core/extra/alarm）+ 本地 AUR 仓库（`[aur]`）：两者对 pacman 透明，`pacman -Ss` 统一搜索
- 结果中标注仓库名（`extra` / `aur`），让用户知道来源；**不单独实现 AUR 构建逻辑**（AUR 包以预编译仓库形式提供）

### 5.2 命令映射

| 操作 | 命令 | 提权 |
|---|---|---|
| 搜索 | `pacman -Ss <query>` | 否 |
| 已装列表 | `pacman -Q` + `.desktop` 扫描 | 否 |
| 包详情 | `pacman -Qi <pkg>` | 否 |
| 安装 | `pacman -S <pkg>` | **polkit** |
| 卸载 | `pacman -R <pkg>` | **polkit** |
| 系统更新 | `pacman -Syu` | **polkit** |

解析 stdout（`pacman -Ss` 的两行格式、`-Qi` 的键值格式）。**不使用 `--noconfirm`**，冲突/替代选择场景在详情里预先展示，不静默穿过。

### 5.3 图标

- 从 `/usr/share/applications/*.desktop` 的 `Icon=` 解析（主题名或绝对路径）
- 无图标的 `Console` 包用分类默认图标

## 6. 安卓后端（一期）

### 6.1 与 droidloom 的集成

平板上已有 `droidloom-adb-server.service`。安卓后端通过 adb 连接到 droidloom 的 Android 实例（设备地址形如 `10.177.0.2:5555`）。

> 实现时确认：优先复用 droidloom 的 adb server 服务；若其接口不适合被应用调用，则直接用系统 `adb`（`android-tools`）连接同一设备。二者选一，不重复造通道。

### 6.2 命令映射

| 操作 | 命令 | 提权 |
|---|---|---|
| 已装列表 | `adb shell pm list packages -3`（第三方） | 否 |
| 应用元数据 | `adb shell dumpsys package <pkg>` / `pm dump` | 否 |
| 图标 | 从 APK 提取或 `dumpsys` 提供 | 否 |
| 卸载 | `adb shell pm uninstall <pkg>` | 否 |
| 安装 | `adb install <本地 APK 路径>` | 否 |
| 更新 | 无（Android 无仓库，重新 install 覆盖） | — |

### 6.3 能力边界（UI 必须体现）

- 安卓后端**没有在线搜索/发现**：浏览页中安卓源固定展示为"选择 APK 文件"拖放区
- 已装列表中的安卓应用点入详情：卸载、清除数据（`pm clear`，可选）、APK 大小
- **一期不做**：APK 更新检查、权限管理页、Android 侧的应用数据浏览

### 6.4 安装流程

1. 用户在浏览页拖入/选择 APK 文件
2. 插件读取 APK 基本信息（包名、版本——用 `aapt`/`apkanalyzer` 或安装后回读）
3. 确认对话框展示包名与体积
4. `adb install -r`
5. 成功/失败反馈（解析 `adb install` 的失败原因，如签名冲突、ABI 不兼容）

## 7. 权限与提权

- pacman 的安装/卸载/更新需要 root，走 **polkit**（复用已在运行的 `denial-polkit-agent`）
- 确认对话框规则：涉及提权的操作，在用户点击确认**之前**就写明"将请求管理员权限"；不搞点了才弹
- flatpak/玲珑（后续）/安卓全部用户级，不提权
- 提权失败（用户取消/密码错误）：明确反馈，不静默重试

## 8. 错误处理

| 场景 | 行为 |
|---|---|
| 单个后端查询失败 | 该源显示"暂不可用"占位，其他源正常 |
| pacman 操作遇依赖冲突 | 展示冲突详情，提供"查看完整输出"，不自动解决 |
| 安卓安装失败 | 解析并展示原因（签名冲突 / ABI 不兼容 / 空间不足） |
| 后端 CLI 不存在 | 该源整体隐藏（如未装 flatpak 时不显示该源），不报错 |
| 卸载会移除多个桌面入口 | 确认对话框列出全部受影响入口 |

## 9. 测试策略

- core crate 单元测试：CLI 输出解析（用 fixtures 覆盖 `pacman -Ss/-Qi/-Q`、`pm list`、`adb install` 的典型与异常输出）
- 状态层测试：多后端并发、单后端失败的隔离、缓存刷新
- **不写需要真实提权/真实安装的集成测试到 CI**；在平板上手工验收（见下）

## 10. 验收标准

- [ ] launcher 进入插件，左 rail 三组导航可切换，全屏移动窗口无裁切
- [ ] 已装页：pacman 包（含 Console 折叠）与 Android 应用统一列表，来源徽标正确
- [ ] 搜索双栏：左栏点结果右栏实时切详情；Android 源为 APK 拖放区
- [ ] pacman 安装：确认对话框预告提权 → polkit → 安装成功 → 列表刷新
- [ ] pacman 卸载：确认对话框列出受影响桌面入口 → 提权 → 卸载成功
- [ ] Android 卸载：确认 → `pm uninstall` → 列表刷新
- [ ] Android 安装：选择 APK → 确认 → `adb install -r` → 成功反馈；失败时有原因
- [ ] 更新页：pacman 与安卓分组展示；pacman 批量更新走一次提权
- [ ] 单后端失败时其他源可用（可临时断开网络模拟）
- [ ] 后端 CLI 缺失时该源隐藏（如模拟未装 android-tools）
- [ ] settings 改全局色调后，商店所有 accent 元素（按钮 / rail 选中 pill / 更新徽标 / 聚焦边框）立即跟随；来源徽标三色与提权琥珀色不变

## 11. 实现分期

| 阶段 | 内容 | 出口标准 |
|---|---|---|
| 一期 | pacman + 安卓后端，三标签页，polkit 提权 | 第 10 节全部通过 |
| 二期 | flatpak 后端接入（trait 复用） | flatpak 源可搜/装/卸/更新 |
| 三期 | 玲珑后端接入（须先完成 Arch ARM 可行性验证） | 玲珑源可搜/装/卸 |

## 12. 明确不做

- launcher 长按的管理菜单（卸载/应用信息）——收拢到本插件
- 自建包管理 / 包格式转换
- AUR 现场编译（AUR 包以本地预编译仓库形式提供）
- Android 应用的在线更新检查与权限管理页
- 后台自动更新（仅手动刷新）

---

*规范版本 v1 · 2026-11-11 · 与 docs/SPLIT_SCREEN.md 同属 Denial 平板适配工程*

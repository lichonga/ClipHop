# ClipHop 设计文档

日期：2026-10-22
状态：已与用户确认

## 1. 背景与目标

系统剪贴板是单格存储：连续复制多次后，旧内容被新内容覆盖（典型场景：先复制账号、再复制密码，切到登录页时账号已取不回）。

ClipHop 是一个 macOS 后台小工具，目标：

- 持续截取系统剪贴板内容（文本 + 图片），保留最近 50 条历史
- 以小窗形式**常驻悬浮在所有应用之上**（类似 Snipaste），随当前应用使用
- 点击历史条目即把该条内容写回系统剪贴板，用户 ⌘V 完成粘贴，焦点始终留在原应用
- 窗口可拖动位置、可拖拽调整大小，位置/大小自动记忆
- 全局快捷键 ⌥Space 切换窗口显示/隐藏，不用时可收起

**核心约束**：窗口必须**非激活**（不抢焦点）。否则点击条目后 ⌘V 会发给 ClipHop 自己，粘贴流程断裂。这是本设计成败的关键点。

## 2. 已确认的需求决策

| 决策点 | 结论 |
|---|---|
| 窗口形态 | 常驻悬浮窗 + 全局快捷键（⌥Space）切换显示/隐藏 |
| 内容类型 | 文本 + 图片（PNG 数据） |
| 粘贴方式 | 点击仅写回剪贴板，用户自己 ⌘V（零系统权限） |
| 历史持久化 | 不持久化，纯内存，重启清空 |
| 窗口技术 | SwiftUI `Window` 场景 + NSWindow 修饰（见 §4；含回退方案） |

## 3. 架构总览

单 target 的 macOS SwiftUI 应用（部署目标 macOS 13+，xcodegen 管理 `project.yml`）：

```
ClipHop/
├─ ClipHopApp.swift          # App 入口：Window 场景 + NSApplicationDelegateAdaptor
├─ WindowConfigurator.swift  # NSWindow 修饰：置顶/非激活/桌面空间/细标题栏/autosave
├─ GlobalHotkey.swift        # Carbon RegisterEventHotKey 封装（⌥Space）
├─ ClipboardMonitor.swift    # 轮询剪贴板、去重、截断、restore（文本/图片）
├─ ClipboardItem.swift       # 数据模型（text / image 两种内容）
└─ ClipboardListView.swift   # 列表 UI（文本行/图片行、空状态、标题栏按钮）
```

`project.yml` 变更：`INFOPLIST_KEY_LSUIElement: YES`（无 Dock 图标，纯后台工具；也因此没有菜单栏，退出/清空入口放在窗口标题栏）。

## 4. 窗口行为

### 4.1 修饰方案（主方案）

`Window` 场景加载后拿到 `NSWindow`，施加：

- `level = .floating` — 始终置于普通应用窗口之上
- `styleMask.insert(.nonactivatingPanel)` — 点击窗口不激活 ClipHop，焦点留在原应用
- `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]` — 所有 Mission Control 桌面可见，全屏应用上也可浮出
- `titlebarAppearsTransparent = true` — 细标题栏，保留**原生**拖动与四边/四角拖拽缩放（"大小可拖动"零自写代码）
- `setFrameAutosaveName("ClipHopMainWindow")` — 位置/大小跨启动记忆
- `contentMinSize = 240×160`
- 应用启动时窗口直接显示（常驻默认态）

### 4.2 回退方案

若验证发现 SwiftUI `Window` 场景下 `.nonactivatingPanel` 位不可靠（点击条目仍激活应用），则将窗口部分改为 AppKit `NSPanel`（`nonactivatingPanel` 类面板 + `NSHostingView` 承载同一个 SwiftUI 视图），其余代码不变。**实现时第一步就验证该点**，避免后置返工。

### 4.3 显示/隐藏

- ⌥Space（`keyCode 49` + `optionKey`）：
  - 窗口可见 → `orderOut`
  - 窗口隐藏 → `makeKeyAndOrderFront` + `NSApp.activate`（从隐藏态呼出时需要激活才能接收后续键盘交互；呼出瞬间的激活不影响"点击条目不抢焦点"的约束，因为条目点击发生在窗口已可见之后）
- 隐藏后 `ClipboardMonitor` 保持运行，继续积累历史

## 5. 数据模型与剪贴板捕获

```swift
enum ClipboardContent: Equatable {
    case text(String)
    case image(Data)   // PNG
}

struct ClipboardItem: Identifiable, Equatable {
    let id: Int            // pasteboard changeCount，稳定唯一
    let content: ClipboardContent
    let date: Date
}
```

### 5.1 捕获规则（`ClipboardMonitor`）

- 沿用现有 0.5s Timer 轮询 + `changeCount` 变化判断
- 每次变化时的提取优先级：
  1. `string(forType: .string)` 非空 → 记 `.text`
  2. 否则读 `NSImage`（`readObjects(forClasses: [NSImage.self])`），转 PNG data 后记 `.image`
  3. PNG data 超过 **10MB** → 跳过该条（单条存储上限：防最坏情况 50 条 × 10MB ≈ 500MB 内存）
  4. 两者都没有 → 忽略
- 去重：同内容已在列表中 → 不重复插入（现有"移动到顶部"语义对"点击不改剪贴板"的流程无意义，保留首见位置即可；若首条相同则直接忽略）
- 上限 50 条，超出移除最旧
- **纯内存**，不写盘

### 5.2 restore（点击条目）

- `.text` → `pb.clearContents(); pb.setString(text, forType: .string)`
- `.image` → `pb.clearContents(); pb.setData(png, forType: .png)`
- 不调用任何激活/聚焦 API；写完即返回，焦点不动

### 5.3 测试性

"去重 + 插入 + 截断"抽为不依赖 `NSPasteboard` 的纯函数：

```swift
static func apply(_ new: ClipboardItem, to items: [ClipboardItem], max: Int) -> [ClipboardItem]
```

便于审查与单测。不单独建测试 target（最简路径）。

## 6. UI

```
┌ ClipHop              清空  退出 ─┐  ← 细标题栏（原生拖动区）
├─────────────────────────────────┤
│ [缩略图 48px]        2 分钟前   │  ← 图片行
├─────────────────────────────────┤
│ SELECT * FROM users             │  ← 文本行（最多 2 行）
│ …WHERE id = 1;      5 分钟前    │
├─────────────────────────────────┤
│ { "name": "ClipHop", …   昨天   │
└─────────────────────────────────┘
  四边/四角拖拽缩放（原生），最小 240×160
```

- 文本行：内容最多 2 行 + 相对时间（`Text(date, style: .relative)`）
- 图片行：48px 高缩略图（`NSImage` → `Image`）+ 相对时间
- 点击整行 = restore
- 标题栏右侧：`清空`（清历史）、`退出`（`NSApp.terminate`）
- 空状态：沿用现有提示文案
- 宽度默认 360（沿用现值），高度默认 320

## 7. 错误处理

全部"静默跳过"，不中断轮询、不弹窗：

- 读不到文本也读不到图片 → 忽略本次 change
- 图片编码/过大 → 跳过
- `restore` 写回失败（异常 pasteboard 状态）→ 忽略
- 全局快捷键注册失败 → 应用仍可用（窗口常驻，仅少了 ⌥Space）

## 8. 验证方式

1. `xcodebuild -scheme ClipHop build` 编译通过
2. 手动验证清单：
   - [ ] 步骤 1 验证：点击条目后原应用保持焦点（在另一应用输入框 ⌘V 能粘对）
   - [ ] 连续复制 3 条文本 → 列表按新→旧排列，重复内容不重复入列
   - [ ] 截图复制 → 列表出现图片缩略图行；点击后 ⌘V 粘出图片
   - [ ] 超大图片（>10MB PNG）复制 → 不入列表、不卡顿
   - [ ] ⌥Space 隐藏/呼出，隐藏期间继续积累历史
   - [ ] 拖动位置、拖边缩放；重启后位置/大小恢复
   - [ ] 窗口在所有桌面空间、全屏应用上方均可见
   - [ ] 标题栏「清空」「退出」可用

## 9. 非目标（YAGNI）

- 不持久化历史 / 加密存储
- 不支持文件列表、富文本（RTF/HTML）、链接卡片
- 不做自动模拟 ⌘V（需辅助功能权限，用户已选手动 ⌘V）
- 不做多 profile、搜索过滤、条目编辑
- 不提供快捷键自定义 UI（常量硬编码，改一行即可）

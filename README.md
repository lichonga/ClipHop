# ClipHop

macOS 剪贴板历史小工具：后台记录复制的文本，悬浮窗一键取回并自动粘贴。

## 功能

- 持续截取系统剪贴板文本（0.5s 轮询），最多保留最近 50 条，同内容去重
- 悬浮窗置顶显示（高于菜单栏层级，全屏应用上也可浮出），**不抢焦点**
- 点击条目（或 ↑↓ 选中后回车）：写回剪贴板并自动向原应用合成 ⌘V
- 全局快捷键 ⌘⇧V 呼出/隐藏，ESC 隐藏
- 菜单栏图标（剪贴板样式），菜单提供「显示/隐藏」和「退出 ClipHop」
- 纯内存存储，重启清空；无 Dock 图标、无应用菜单（LSUIElement）

## 使用

| 操作 | 效果 |
|---|---|
| ⌘⇧V | 呼出/隐藏面板（每次呼出显示在当前聚焦屏幕顶部居中） |
| ↑ / ↓ | 移动高亮 |
| ⏎ | 选中条目 → 写回剪贴板 + 自动 ⌘V 粘贴回原应用 |
| ESC | 隐藏面板 |
| 点击条目 | 同 ⏎ |
| 菜单栏图标 | 显示/隐藏、退出应用 |

## 权限

- **自动粘贴（⏎ 合成 ⌘V）：
- ⌘⇧V 热键（Carbon `RegisterEventHotKey`）不需要任何权限。

## 构建

```sh
xcodegen          # project.yml 有改动时才需要
xcodebuild -project ClipHop.xcodeproj -scheme ClipHop -destination 'platform=macOS' build
open ~/Library/Developer/Xcode/DerivedData/ClipHop-*/Build/Products/Debug/ClipHop.app
```

部署目标 macOS 13+，无第三方依赖。

## 项目结构

```
ClipHop/
├─ ClipHopApp.swift          # App 入口（Settings 占位场景，窗口由 AppDelegate 自建）
├─ AppDelegate.swift         # 面板管理、⌘⇧V 热键、菜单栏状态项、合成 ⌘V
├─ WindowConfigurator.swift  # NSPanel 修饰：置顶/非激活/全空间可见/隐藏红绿灯
├─ ClipboardMonitor.swift    # 0.5s 轮询剪贴板、去重、截断、restore
├─ ClipboardItem.swift       # 数据模型 + 去重/插入/截断纯函数（ClipboardItem.apply）
└─ ClipboardListView.swift   # 列表 UI + 键盘操作（↑↓/⏎/ESC）
```

## 已知限制

- 目前只捕获文本（图片类型在数据模型中保留，未启用捕获）
- 历史不持久化，重启清空
- 窗口位置不记忆，每次呼出都在当前屏幕顶部居中
- 面板隐藏时全局按键监听仍生效（呼出状态下的按键由全局监听接管，需辅助功能权限）

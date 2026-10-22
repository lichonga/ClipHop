# ClipHop 常驻悬浮剪贴板 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把现有 MenuBarExtra 剪贴板工具改造为常驻悬浮小窗（置顶、非激活不抢焦点、可拖拽缩放、⌥Space 呼出/隐藏），支持文本 + 图片历史。

**Architecture:** SwiftUI `Window` 场景 + 对底层 `NSWindow` 的修饰（`.floating` 层级、`.nonactivatingPanel` 位、`canJoinAllSpaces`）。**Task 2 末尾有焦点验证关卡**：若 SwiftUI Window 下点击条目仍激活本应用，按 Task 2 的 Fallback 分支改为 `NSPanel` + `NSHostingView`，其余任务不变。

**Tech Stack:** Swift 5 / SwiftUI / AppKit / Carbon `RegisterEventHotKey`（零系统权限）；xcodegen 管理工程；部署目标 macOS 13+。

**Spec:** `docs/superpowers/specs/2026-10-22-cliphop-design.md`

**与 spec 的一处有意偏差**：spec §6 把「清空/退出」放在标题栏，本计划沿用现有代码的视图底部按钮栏——功能等价、代码更少，且兼容 Task 2 的 NSPanel fallback 分支（NSHostingView 下 `.toolbar` 场景修饰不可用）。

## 环境约定（每个任务通用）

本机 `xcode-select -p` 指向 CommandLineTools，因此所有构建统一用 Xcode 全路径，避免 sudo：

```bash
export XCB=/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild
cd /Users/yangwei/test/ClipHop
```

构建命令（每步构建都用它，期望输出末尾 `** BUILD SUCCEEDED **`）：

```bash
$XCB -project ClipHop.xcodeproj -scheme ClipHop -configuration Debug build 2>&1 | tail -5
```

运行命令（手动验证时用）：

```bash
open ~/Library/Developer/Xcode/DerivedData/ClipHop-*/Build/Products/Debug/ClipHop.app
```

注意：新增/删除 `.swift` 文件后必须先 `xcodegen generate` 再构建（工程文件是 xcodegen 生成的显式文件列表）。

---

### Task 1: 数据模型 ClipboardItem + 纯函数 apply（TDD）

**Files:**
- Create: `ClipHop/ClipHop/ClipboardItem.swift`
- Modify: `ClipHop/ClipHop/ClipboardMonitor.swift`（删除旧 struct，最小适配编译）
- Modify: `ClipHop/ClipHop/ClipboardListView.swift`（改用 `plainText`，保持编译）

- [ ] **Step 1: 写失败的测试脚本**

```bash
mkdir -p /tmp/cliphop-test
cat > /tmp/cliphop-test/main.swift <<'EOF'
import Foundation

func check(_ cond: Bool, _ msg: String) {
    if cond { print("PASS: \(msg)") } else { print("FAIL: \(msg)"); exit(1) }
}
let a = ClipboardItem(id: 1, content: .text("a"), date: .now)
let b = ClipboardItem(id: 2, content: .text("b"), date: .now)

// 1. 新条目插入顶部
var r = ClipboardItem.apply(a, to: [b], max: 50)
check(r.map(\.id) == [1, 2], "新条目插入顶部")

// 2. 重复内容不插入、保留原位
r = ClipboardItem.apply(ClipboardItem(id: 3, content: .text("b"), date: .now), to: [a, b], max: 50)
check(r.map(\.id) == [1, 2], "重复内容不插入、保留原位")

// 3. 超上限移除最旧（51 条压入后截断，尾部 id=50 被移除）
let many = (1...51).map { ClipboardItem(id: $0, content: .text("t\($0)"), date: .now) }
r = ClipboardItem.apply(many[50], to: Array(many[0...49]), max: 50)
check(r.count == 50 && r.first!.id == 51 && r.last!.id == 49, "超上限截断为 50 条")

// 4. 文本与图片不互为重复
let img = ClipboardItem(id: 9, content: .image(Data([1, 2, 3])), date: .now)
r = ClipboardItem.apply(img, to: [a], max: 50)
check(r.count == 2, "文本/图片内容不冲突")

print("ALL PASS")
EOF
```

- [ ] **Step 2: 运行确认失败**

```bash
/usr/bin/swiftc /Users/yangwei/test/ClipHop/ClipHop/ClipboardItem.swift /tmp/cliphop-test/main.swift -o /tmp/cliphop-test/t && /tmp/cliphop-test/t
```

Expected: 编译失败，`no such module` / `cannot find type 'ClipboardItem' in scope`（文件尚不存在）。

- [ ] **Step 3: 实现模型文件**

Create `ClipHop/ClipHop/ClipboardItem.swift`：

```swift
import Foundation

enum ClipboardContent: Equatable {
    case text(String)
    case image(Data)   // PNG
}

struct ClipboardItem: Identifiable, Equatable {
    let id: Int            // pasteboard changeCount，稳定唯一
    let content: ClipboardContent
    let date: Date

    /// 视图便捷访问
    var plainText: String? {
        if case .text(let t) = content { return t }
        return nil
    }
    var imageData: Data? {
        if case .image(let d) = content { return d }
        return nil
    }

    /// 去重 + 插入顶部 + 截断。同内容已在列表中 → 保留原位置，原样返回。
    static func apply(_ new: ClipboardItem, to items: [ClipboardItem], max: Int) -> [ClipboardItem] {
        guard !items.contains(where: { $0.content == new.content }) else { return items }
        var result = [new] + items
        if result.count > max { result.removeLast(result.count - max) }
        return result
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
/usr/bin/swiftc /Users/yangwei/test/ClipHop/ClipHop/ClipboardItem.swift /tmp/cliphop-test/main.swift -o /tmp/cliphop-test/t && /tmp/cliphop-test/t
```

Expected: 4 行 `PASS:` + `ALL PASS`。

- [ ] **Step 5: 适配 ClipboardMonitor 保持编译**

修改 `ClipHop/ClipHop/ClipboardMonitor.swift`：
1. 删除文件顶部的旧 `struct ClipboardItem`（已移到新文件）
2. `poll()` 中去重/插入/截断三行替换为 `items = ClipboardItem.apply(...)`：

```swift
    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        guard let text = pb.string(forType: .string), !text.isEmpty else { return }
        items = ClipboardItem.apply(
            ClipboardItem(id: pb.changeCount, content: .text(text), date: .now),
            to: items, max: maxItems)
    }

    /// 把指定条目写回剪贴板，用户 ⌘V 即可粘贴
    func restore(_ item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.content {
        case .text(let text): pb.setString(text, forType: .string)
        case .image(let png): pb.setData(png, forType: .png)
        }
    }
```

（`clear()`、`start()`、`maxItems` 保持不变）

- [ ] **Step 6: 适配 ClipboardListView 保持编译**

`ClipHop/ClipHop/ClipboardListView.swift` 中 `Text(item.text)` 改为 `Text(item.plainText ?? "")`（Task 3 会重做行渲染）。

- [ ] **Step 7: 重新生成工程并构建**

```bash
xcodegen generate
$XCB -project ClipHop.xcodeproj -scheme ClipHop -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: Commit**

```bash
git add ClipHop project.yml ClipHop.xcodeproj
git commit -m "feat: 数据模型支持文本/图片，抽取纯函数 apply（去重/插入/截断）"
```

---

### Task 2: 悬浮窗口 + 焦点验证关卡（核心风险点）

**Files:**
- Create: `ClipHop/ClipHop/WindowConfigurator.swift`
- Create: `ClipHop/ClipHop/AppDelegate.swift`
- Modify: `ClipHop/ClipHop/ClipHopApp.swift`（MenuBarExtra → Window 场景）
- Modify: `project.yml`（LSUIElement）

- [ ] **Step 1: 写 WindowConfigurator**

Create `ClipHop/ClipHop/WindowConfigurator.swift`：

```swift
import AppKit

/// 把 SwiftUI Window 场景的 NSWindow 修饰成常驻悬浮、非激活面板
enum WindowConfigurator {
    static let autosaveName = "ClipHopMainWindow"

    static func configure(_ window: NSWindow) {
        window.level = .floating                                   // 置顶
        window.styleMask.insert(.nonactivatingPanel)               // 点击不激活本应用（Task 2 关卡验证）
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .managed]
        window.titlebarAppearsTransparent = true                   // 细标题栏，保留原生拖动/缩放
        window.setFrameAutosaveName(autosaveName)                  // 位置/大小记忆
        window.contentMinSize = NSSize(width: 240, height: 160)
    }
}
```

- [ ] **Step 2: 写 AppDelegate（Task 5 才注册快捷键，这里只留 toggle）**

Create `ClipHop/ClipHop/AppDelegate.swift`：

```swift
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // Task 5 会添加 hotkey 属性与 Carbon import

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Task 5 在此注册 ⌥Space 快捷键
    }

    /// ⌥Space：可见则隐藏；隐藏则呼出（呼出瞬间激活，不影响"点击条目不抢焦点"约束）
    func toggleWindow() {
        guard let window = NSApp.windows.first(where: { $0.frameAutosaveName == WindowConfigurator.autosaveName }) else { return }
        if window.isVisible {
            window.orderOut(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
```

- [ ] **Step 3: 改 App 入口为 Window 场景**

`ClipHop/ClipHop/ClipHopApp.swift` 整体替换为：

```swift
import SwiftUI

@main
struct ClipHopApp: App {
    @StateObject private var monitor = ClipboardMonitor()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("ClipHop", id: "main") {
            ClipboardListView(monitor: monitor)
                .frame(minWidth: 240, minHeight: 160)
                .background(WindowAccessor { window in
                    WindowConfigurator.configure(window)
                })
                .onAppear { monitor.start() }
        }
        .defaultSize(width: 360, height: 320)   // Scene 修饰符，必须在 Window { } 之外
        .windowResizability(.contentMinSize)
    }
}

/// 拿到 SwiftUI 场景背后的 NSWindow
struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window { onResolve(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
```

（`WindowAccessor` 放在本文件即可，不单独建文件。）

- [ ] **Step 4: project.yml 加 LSUIElement**

`project.yml` 的 `settings.base` 下加一行：

```yaml
        INFOPLIST_KEY_LSUIElement: "YES"
```

然后重新生成工程：

```bash
xcodegen generate
$XCB -project ClipHop.xcodeproj -scheme ClipHop -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: ⚠️ 焦点验证关卡（本计划成败点，必须先过再往下做）**

手动验证（约 1 分钟）：

```bash
pkill -x ClipHop; sleep 1
open ~/Library/Developer/Xcode/DerivedData/ClipHop-*/Build/Products/Debug/ClipHop.app
```

1. 打开 TextEdit 新建文档，点进正文
2. 随便复制一段文字（⌘C）→ ClipHop 悬浮窗应出现该条目（且置顶在 TextEdit 上方）
3. **在 ClipHop 窗里点击该条目**
4. 不切应用，直接在键盘敲 `abc`

**PASS 判定**：`abc` 出现在 TextEdit 里（说明点击条目后焦点没被 ClipHop 抢走）。
**FAIL 判定**：`abc` 没有出现 / TextEdit 失去焦点 / 需要 ⌘Tab 才能打字。

- [ ] **Step 6: 若 FAIL → 走 NSPanel Fallback（PASS 则跳过本步直接 Step 7）**

把窗口实现整体替换为 NSPanel（其余任务不受影响）：

1. `ClipHopApp.swift` 替换为：

```swift
import SwiftUI
import AppKit

@main
struct ClipHopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
```

2. `AppDelegate.swift` 替换为（monitor 移入 AppDelegate；toggle 用 panel）：

```swift
import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let monitor = ClipboardMonitor()
    var panel: NSPanel!
    // Task 5 会添加 hotkey 属性与 Carbon import

    func applicationDidFinishLaunching(_ notification: Notification) {
        let root = ClipboardListView(monitor: monitor)
            .frame(minWidth: 240, minHeight: 160)

        panel = NSPanel(
            contentRect: NSRect(x: 200, y: 200, width: 360, height: 320),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .managed]
        panel.titlebarAppearsTransparent = true
        panel.setFrameAutosaveName("ClipHopMainWindow")
        panel.contentMinSize = NSSize(width: 240, height: 160)
        panel.contentView = NSHostingView(rootView: root)
        panel.makeKeyAndOrderFront(nil)

        monitor.start()
        // Task 5 在此注册 ⌥Space 快捷键
    }

    func toggleWindow() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
```

3. 删除 `WindowConfigurator.swift`、`WindowAccessor`（不再需要）
4. 重新 `xcodegen generate` + 构建，**重跑 Step 5 验证**（NSPanel 的非激活是 AppKit 原生保证，预期 PASS）

- [ ] **Step 7: Commit（含关卡结论）**

```bash
git add ClipHop project.yml ClipHop.xcodeproj
git commit -m "feat: 常驻悬浮非激活窗口（Window 场景 + NSWindow 修饰）"
# 若走了 Fallback，message 改为 "feat: 常驻悬浮非激活窗口（NSPanel 方案）"
```

---

### Task 3: 视图图片行 + 布局

**Files:**
- Modify: `ClipHop/ClipHop/ClipboardListView.swift`

- [ ] **Step 1: 重写列表行渲染**

`ClipboardListView.swift` 中 `List` 部分替换为（底部"清空/退出"栏与空状态保留不动）：

```swift
                List(monitor.items) { item in
                    Button {
                        monitor.restore(item)
                    } label: {
                        HStack(spacing: 10) {
                            if let data = item.imageData, let nsImage = NSImage(data: data) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 48)
                                    .frame(maxWidth: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                if let text = item.plainText {
                                    Text(text)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }
                                Text(item.date, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                    .help("点击切换到此内容")
                }
                .listStyle(.inset)
```

同时删掉原来包在 `List` 外的 `.frame(height: 320)`（高度交给窗口尺寸）。

- [ ] **Step 2: 构建**

```bash
$XCB -project ClipHop.xcodeproj -scheme ClipHop -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add ClipHop/ClipHop/ClipboardListView.swift
git commit -m "feat: 列表支持图片缩略图行"
```

---

### Task 4: 剪贴板捕获支持图片

**Files:**
- Modify: `ClipHop/ClipHop/ClipboardMonitor.swift`

- [ ] **Step 1: 改捕获与 restore**

`poll()` 替换为下方版本，并在属性区**新增** `maxImageBytes`（下方代码块里列出的 `timer`/`lastChangeCount`/`maxItems` 只是上下文，已存在，勿重复添加）：

```swift
    private var timer: Timer?
    private var lastChangeCount: Int
    private let maxItems = 50
    private static let maxImageBytes = 10 * 1024 * 1024   // 单条上限：防最坏 50×10MB 内存

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        guard let item = Self.makeItem(changeCount: pb.changeCount, pb: pb) else { return }
        items = ClipboardItem.apply(item, to: items, max: maxItems)
    }

    /// 提取优先级：文本 > 图片(PNG)；图片超 10MB 或都取不到 → nil
    static func makeItem(changeCount: Int, pb: NSPasteboard) -> ClipboardItem? {
        if let text = pb.string(forType: .string), !text.isEmpty {
            return ClipboardItem(id: changeCount, content: .text(text), date: .now)
        }
        if let image = pb.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage,
           let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]),
           png.count <= maxImageBytes {
            return ClipboardItem(id: changeCount, content: .image(png), date: .now)
        }
        return nil
    }
```

`restore()` 用 Task 1 Step 5 已写好的文本/图片双分支版本（若当前还是旧版，替换为 Step 5 中的代码）。

- [ ] **Step 2: 构建**

```bash
$XCB -project ClipHop.xcodeproj -scheme ClipHop -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 手动验证图片流**

```bash
pkill -x ClipHop; sleep 1
open ~/Library/Developer/Xcode/DerivedData/ClipHop-*/Build/Products/Debug/ClipHop.app
```

1. 用截图工具截一张图（⌘⇧4）→ 列表顶部出现图片缩略图行
2. 在 TextEdit 点进正文 → 点 ClipHop 里该图片条目 → ⌘V → TextEdit 里粘出图片
3. 图片点击后焦点仍留在 TextEdit（连续操作不中断）

- [ ] **Step 4: Commit**

```bash
git add ClipHop/ClipHop/ClipboardMonitor.swift
git commit -m "feat: 剪贴板捕获支持图片（PNG，10MB 上限），文本优先"
```

---

### Task 5: 全局快捷键 ⌥Space

**Files:**
- Create: `ClipHop/ClipHop/GlobalHotkey.swift`
- Modify: `ClipHop/ClipHop/AppDelegate.swift`

- [ ] **Step 1: 实现 Carbon 全局快捷键封装**

Create `ClipHop/ClipHop/GlobalHotkey.swift`：

```swift
import AppKit
import Carbon.HIToolbox

/// 全局快捷键（Carbon RegisterEventHotKey，零系统权限）
/// 注意：C 回调以 unretained 方式持有 self，本对象生命周期 = 应用生命周期，勿提前释放。
final class GlobalHotkey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let onFire: () -> Void

    /// - Parameters:
    ///   - keyCode: Carbon 虚拟键码（49 = Space，US 布局）
    ///   - modifiers: 如 UInt32(optionKey)
    init?(keyCode: UInt32, modifiers: UInt32, onFire: @escaping () -> Void) {
        self.onFire = onFire

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue().onFire()
            return noErr
        }, 1, &spec, selfPtr, &handlerRef) == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: 0x43_4C_48_50, id: 1)   // 'CLHP'
        guard RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                  GetApplicationEventTarget(), 0, &hotKeyRef) == noErr else {
            RemoveEventHandler(handlerRef)
            handlerRef = nil
            return nil
        }
    }
}
```

- [ ] **Step 2: AppDelegate 注册**

`AppDelegate.swift` 改两处（`optionKey` 是 Carbon 常量 0x0800，必须 import 才能解析；**不能**用 `NSEvent.ModifierFlags.option.rawValue`，那是 0x80000，传错了 ⌥Space 会静默不触发）：

1. 文件头 `import AppKit` 下加 `import Carbon.HIToolbox`
2. `class AppDelegate` 内加 `var hotkey: GlobalHotkey?` 属性
3. 在 `// Task 5 在此注册 ⌥Space 快捷键` 注释处**插入**注册代码（注意：若走了 Task 2 的 NSPanel fallback，该方法里还有创建 panel 的代码，只插入、不要整方法替换）：

```swift
    var hotkey: GlobalHotkey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        hotkey = GlobalHotkey(keyCode: 49, modifiers: UInt32(optionKey)) { [weak self] in
            self?.toggleWindow()
        }
    }
```

- [ ] **Step 3: 重新生成工程 + 构建**

```bash
xcodegen generate
$XCB -project ClipHop.xcodeproj -scheme ClipHop -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: 手动验证快捷键**

```bash
pkill -x ClipHop; sleep 1
open ~/Library/Developer/Xcode/DerivedData/ClipHop-*/Build/Products/Debug/ClipHop.app
```

1. 切到任意其他应用 → 按 ⌥Space → 窗口消失
2. 再按 ⌥Space → 窗口在原位置出现
3. 隐藏期间复制 3 条文本 → 呼出后 3 条都在

- [ ] **Step 5: Commit**

```bash
git add ClipHop project.yml ClipHop.xcodeproj
git commit -m "feat: ⌥Space 全局快捷键切换窗口显示/隐藏（Carbon，零权限）"
```

---

### Task 6: 完整验收

**Files:** 无新改动（跑 spec §8 验证清单，发现问题就地修复并补 commit）

- [ ] **Step 1: 重启应用跑全量清单**

```bash
pkill -x ClipHop; sleep 1
rm -f ~/Library/Saved\ Application\ State/*ClipHop* 2>/dev/null
open ~/Library/Developer/Xcode/DerivedData/ClipHop-*/Build/Products/Debug/ClipHop.app
```

按 spec §8 逐项勾选：

- [ ] 点击条目后原应用保持焦点，⌘V 粘对内容
- [ ] 连续复制 3 条文本 → 按新→旧排列；重复内容不重复入列
- [ ] 截图复制 → 图片缩略图行；点击后 ⌘V 粘出图片
- [ ] 超大图片（>10MB PNG）复制 → 不入列表、不卡顿
- [ ] ⌥Space 隐藏/呼出；隐藏期间继续积累历史
- [ ] 拖动位置、拖四边/四角缩放；重启后位置/大小恢复（setFrameAutosaveName）
- [ ] 所有 Mission Control 桌面、全屏应用上方均可见
- [ ] 「清空」清空历史；「退出」退出应用
- [ ] 应用无 Dock 图标（LSUIElement 生效）

- [ ] **Step 2: 修复发现的问题并 commit**

```bash
git add -A
git commit -m "fix: 验收发现的问题"   # 若无问题则跳过
```

- [ ] **Step 3: 收尾**

`pkill -x ClipHop`，确认 `git log --oneline` 有 6 个左右的任务级 commit。

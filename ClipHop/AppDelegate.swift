import AppKit
import SwiftUI
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 供 View 层直接引用，绕开 `NSApp.delegate as? AppDelegate`（实测该 cast 返回 nil）
    static weak var shared: AppDelegate?
    let monitor = ClipboardMonitor()
    var panel: NSPanel!
    private var hotKeyRef: EventHotKeyRef?
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        monitor.start()
        panel = WindowConfigurator.makePanel(content: ClipboardListView(monitor: monitor))
        registerHotKey()
        setupStatusBar()
        requestAccessibilityIfNeeded()
    }

    /// 菜单栏图标 + 下拉菜单（LSUIElement 下这是唯一的退出入口）
    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "clipboard",
                                           accessibilityDescription: "ClipHop")
        let menu = NSMenu()
        let toggle = NSMenuItem(title: "显示/隐藏", action: #selector(toggleWindow), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 ClipHop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
        statusItem.menu = menu
    }

    /// 回车粘贴（⌘V 合成到原应用）与全局按键监听都依赖辅助功能权限，首次运行弹授权框
    private func requestAccessibilityIfNeeded() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// 窗口隐藏/关闭后应用继续常驻（配合 LSUIElement 后台运行）
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// ⌘⇧V：可见则隐藏；隐藏则呼出（面板非激活，不影响"点击条目不抢焦点"约束）
    @objc func toggleWindow() {
        NSLog("ClipHop: toggleWindow called")
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            // 每次呼出都摆到当前聚焦屏幕的顶部居中（不记忆位置，全屏下也没处拖）
            if let screen = NSScreen.main {
                let size = panel.frame.size
                panel.setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2,
                                             y: screen.frame.maxY - size.height - 120))
            }
            NSLog("ClipHop: before makeKey, frontmost=%@ panelKey=%d",
                  NSWorkspace.shared.frontmostApplication?.localizedName ?? "nil",
                  panel.isKeyWindow ? 1 : 0)
            panel.makeKeyAndOrderFront(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.panel.orderFrontRegardless()
            }
            NSLog("ClipHop: shown, visible=%d keyWindow=%d frontmost=%@ frame=%@ level=%d behavior=%lu screens=[%@] mainScreen=%@",
                  panel.isVisible ? 1 : 0, panel.isKeyWindow ? 1 : 0,
                  NSWorkspace.shared.frontmostApplication?.localizedName ?? "nil",
                  NSStringFromRect(panel.frame), panel.level.rawValue,
                  panel.collectionBehavior.rawValue,
                  NSScreen.screens.map { NSStringFromRect($0.frame) }.joined(separator: ", "),
                  NSScreen.main.map { NSStringFromRect($0.frame) } ?? "nil")
        }
    }

    /// ⌘⇧V 全局热键（Carbon RegisterEventHotKey，无需辅助功能权限）
    private func registerHotKey() {
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x434c5048) // 'CLPH'
        hotKeyID.id = 1

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            DispatchQueue.main.async {
                let delegate = Unmanaged<AppDelegate>.fromOpaque(UnsafeRawPointer(userData!)).takeUnretainedValue()
                delegate.toggleWindow()
            }
            return noErr
        }, 1, &eventSpec, selfPtr, nil)

        let status = RegisterEventHotKey(UInt32(kVK_ANSI_V), // 'V'
                                         UInt32(cmdKey | shiftKey),
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &hotKeyRef)
        NSLog("ClipHop: RegisterEventHotKey status=%d", status)
    }

    /// 隐藏面板并合成 ⌘V，把刚写入剪贴板的内容粘贴回原本焦点所在的应用（需辅助功能权限）
    func pasteIntoPreviousApp() {
        NSLog("ClipHop: pasteIntoPreviousApp entered")
        panel?.orderOut(nil)
        // 使用点检查：ad-hoc 签名下每次重新编译都会使已授予的辅助功能权限失效，
        // 只在启动时弹一次授权框会在失权后静默失败——这里失权时重新弹系统授权框并中止粘贴
        guard AXIsProcessTrusted() else {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
            NSLog("ClipHop: skip Cmd-V, accessibility not trusted (re-prompted)")
            return
        }
        // 等焦点先落回原应用再发 ⌘V，太早会发给还没完成切换的窗口
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSLog("ClipHop: about to post Cmd-V, frontmost=%@ panelKey=%d",
                  NSWorkspace.shared.frontmostApplication?.localizedName ?? "nil",
                  self.panel.isKeyWindow ? 1 : 0)
            let source = CGEventSource(stateID: .combinedSessionState)
            let down = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // 'V'
            down?.flags = .maskCommand
            let up = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
            up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
            NSLog("ClipHop: posted synthesized Cmd-V")
        }
    }
}

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

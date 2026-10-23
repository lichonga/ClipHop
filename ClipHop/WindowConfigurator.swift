import AppKit
import SwiftUI

/// 直接创建自管的 NSPanel，绕开 SwiftUI Window 场景对 collectionBehavior 的覆写
enum WindowConfigurator {
    static func makePanel(content: some View) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 320),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.isFloatingPanel = true
        // 高于 .mainMenu(24)；canJoinAllSpaces + fullScreenAuxiliary 才能浮在全屏应用之上
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        // 去掉左上角红绿灯按钮（标题栏保留，可拖动）
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false      // 点击/呼出即成为 key 窗口，可收键盘
        panel.contentMinSize = NSSize(width: 240, height: 160)
        panel.contentView = NSHostingView(rootView: content)
        return panel
    }
}

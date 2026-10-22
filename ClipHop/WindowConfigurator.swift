import AppKit

/// 把 SwiftUI Window 场景的 NSWindow 修饰成常驻悬浮、非激活面板
enum WindowConfigurator {
    static let autosaveName = "ClipHopMainWindow"

    static func configure(_ window: NSWindow) {
        window.level = .floating                                   // 置顶
        window.styleMask.insert(.nonactivatingPanel)               // 点击不激活本应用（Step 5 关卡验证）
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .managed]
        window.titlebarAppearsTransparent = true                   // 细标题栏，保留原生拖动/缩放
        window.setFrameAutosaveName(autosaveName)                  // 位置/大小记忆
        window.contentMinSize = NSSize(width: 240, height: 160)
    }
}

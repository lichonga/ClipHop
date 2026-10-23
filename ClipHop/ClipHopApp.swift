import SwiftUI

@main
struct ClipHopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 占位场景：主面板由 AppDelegate 自建 NSPanel（SwiftUI Window 场景会覆写
        // collectionBehavior，导致窗口无法浮在全屏应用之上）
        Settings {
            EmptyView()
        }
    }
}

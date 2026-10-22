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

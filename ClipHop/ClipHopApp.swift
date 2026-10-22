import SwiftUI

@main
struct ClipHopApp: App {
    @StateObject private var monitor = ClipboardMonitor()

    var body: some Scene {
        MenuBarExtra {
            ClipboardListView(monitor: monitor)
                .frame(width: 360)
                .onAppear { monitor.start() }
        } label: {
            Image(systemName: "doc.on.clipboard")
        }
        .menuBarExtraStyle(.window)
    }
}

import SwiftUI

struct ClipboardListView: View {
    @ObservedObject var monitor: ClipboardMonitor

    /// 当前高亮行：0..<items.count
    @State private var selectedIndex = 0
    @State private var localKeyMonitor: Any?
    @State private var globalKeyMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            if monitor.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clipboard")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("暂无剪切板记录")
                        .foregroundStyle(.secondary)
                    Text("复制内容后会显示在这里，点击条目即可切回")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(width: 360, height: 180)
            } else {
                List {
                    ForEach(Array(monitor.items.enumerated()), id: \.element.id) { index, item in
                        Button {
                            paste(item)
                        } label: {
                            Text(item.plainText ?? "")
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(index == selectedIndex ? Color.blue.opacity(0.25) : Color.clear)
                        .help("点击切换到此内容")
                    }
                }
                .listStyle(.inset)
                .frame(height: 320)
            }
        }
        .onChange(of: monitor.items.count) { newCount in
            if newCount == 0 { selectedIndex = 0 }
            else if selectedIndex >= newCount { selectedIndex = newCount - 1 }
        }
        .onAppear {
            // 面板是非激活窗口：local 监听覆盖"面板为 key"时的按键，
            // global 监听覆盖刚用 ⌘⇧V 呼出、还没点击面板时的按键（需辅助功能权限）
            localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                handleKey(event, source: "local") ? nil : event
            }
            globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
                // 只在面板呼出时拦截，面板隐藏时按键原样留给前台应用
                guard Self.mainWindow?.isVisible == true else { return }
                _ = handleKey(event, source: "global")
            }
        }
        .onDisappear {
            if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
            if let globalKeyMonitor { NSEvent.removeMonitor(globalKeyMonitor) }
            localKeyMonitor = nil
            globalKeyMonitor = nil
        }
    }

    static var mainWindow: NSWindow? { AppDelegate.shared?.panel }

    /// 恢复条目到剪贴板，并自动把内容粘贴回原本焦点所在的应用
    private func paste(_ item: ClipboardItem) {
        monitor.restore(item)
        AppDelegate.shared?.pasteIntoPreviousApp()
    }

    /// ↑↓ 移动高亮，回车粘贴，ESC 关闭窗口；返回 true 表示已消费该按键
    private func handleKey(_ event: NSEvent, source: String) -> Bool {
        if event.keyCode == 53 { // ESC（空列表时也生效）
            NSApplication.shared.keyWindow?.orderOut(nil)
            return true
        }
        let totalRows = monitor.items.count
        guard totalRows > 0 else { return false }
        switch event.keyCode {
        case 126: // ↑
            selectedIndex = max(0, selectedIndex - 1)
            return true
        case 125: // ↓
            selectedIndex = min(totalRows - 1, selectedIndex + 1)
            return true
        case 36, 76: // 回车 / 小键盘回车
            paste(monitor.items[selectedIndex])
            return true
        default:
            return false
        }
    }
}

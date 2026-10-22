import SwiftUI

struct ClipboardListView: View {
    @ObservedObject var monitor: ClipboardMonitor

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
                List(monitor.items) { item in
                    Button {
                        monitor.restore(item)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.text)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text(item.date, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                    .help("点击切换到此内容")
                }
                .listStyle(.inset)
                .frame(height: 320)
            }

            Divider()

            HStack {
                Button("清空") {
                    monitor.clear()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Button("退出 ClipHop") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }
}

import AppKit
import Combine

struct ClipboardItem: Identifiable, Equatable {
    let id: Int        // 取自 pasteboard changeCount，稳定唯一
    let text: String
    let date: Date
}

@MainActor
final class ClipboardMonitor: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []

    private var timer: Timer?
    private var lastChangeCount: Int
    private let maxItems = 50

    init() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        guard let text = pb.string(forType: .string), !text.isEmpty else { return }

        // 去重：同内容不重复入列，已存在的移到顶部
        if items.first?.text == text { return }
        items.removeAll { $0.text == text }
        items.insert(ClipboardItem(id: pb.changeCount, text: text, date: .now), at: 0)
        if items.count > maxItems {
            items.removeLast(items.count - maxItems)
        }
    }

    /// 把指定条目写回剪贴板，用户 ⌘V 即可粘贴
    func restore(_ item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(item.text, forType: .string)
    }

    func clear() {
        items.removeAll()
    }
}

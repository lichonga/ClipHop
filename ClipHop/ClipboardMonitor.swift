import AppKit
import Combine

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
        items = ClipboardItem.apply(
            ClipboardItem(id: pb.changeCount, content: .text(text), date: .now),
            to: items, max: maxItems)
    }

    /// 把指定条目写回剪贴板，用户 ⌘V 即可粘贴
    func restore(_ item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.content {
        case .text(let text): pb.setString(text, forType: .string)
        case .image(let png): pb.setData(png, forType: .png)
        }
    }
}

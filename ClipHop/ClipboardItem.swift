import Foundation

enum ClipboardContent: Equatable {
    case text(String)
    case image(Data)   // PNG
}

struct ClipboardItem: Identifiable, Equatable {
    let id: Int            // pasteboard changeCount，稳定唯一
    let content: ClipboardContent
    let date: Date

    /// 视图便捷访问
    var plainText: String? {
        if case .text(let t) = content { return t }
        return nil
    }
    var imageData: Data? {
        if case .image(let d) = content { return d }
        return nil
    }

    /// 去重 + 插入顶部 + 截断。同内容已在列表中 → 保留原位置，原样返回。
    static func apply(_ new: ClipboardItem, to items: [ClipboardItem], max: Int) -> [ClipboardItem] {
        guard !items.contains(where: { $0.content == new.content }) else { return items }
        var result = [new] + items
        if result.count > max { result.removeLast(result.count - max) }
        return result
    }
}

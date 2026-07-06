import Foundation

/// A rendered heading paired with its Markdown source line — the anchors
/// the editor uses to scroll the preview to the section under the caret
/// (Fase 5). The renderer emits them in document order.
public struct PreviewAnchor: Equatable, Sendable {
    /// 1-based line of the heading in the Markdown source.
    public let sourceLine: Int
    /// UTF-16 offset of the rendered heading in the preview string.
    public let location: Int

    public init(sourceLine: Int, location: Int) {
        self.sourceLine = sourceLine
        self.location = location
    }
}

public enum PreviewSync {

    /// Rendered position for a caret on `sourceLine`: the nearest heading
    /// at or above it. Before the first heading — or with no headings —
    /// the top of the document.
    public static func location(forSourceLine line: Int, anchors: [PreviewAnchor]) -> Int {
        var result = 0
        for anchor in anchors {
            if anchor.sourceLine <= line { result = anchor.location } else { break }
        }
        return result
    }
}

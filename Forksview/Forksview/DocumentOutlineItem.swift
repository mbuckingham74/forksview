import Foundation

/// App-owned outline item derived from Markdown source via cmark.
/// Identity is UTF-16 source location to distinguish duplicate headings.
struct DocumentOutlineItem: Identifiable, Equatable, Sendable {
    /// Heading level 1...6
    let level: Int
    /// Human-readable plain heading text (trimmed)
    let title: String
    /// UTF-16 range covering the heading source block (ATX line or Setext content+underline)
    let sourceRange: NSRange

    var id: Int { sourceRange.location }
}

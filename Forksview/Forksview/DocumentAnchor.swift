import Foundation

/// Semantic anchor for position preservation, remediated in Milestone 7 to use real outline parser.
/// Prefers source location + nearest heading over raw pixels.
struct DocumentAnchor: Equatable, Sendable {
    /// UTF-16 offset into document.text (NSTextView uses UTF-16 ranges).
    let offset: Int
    /// Nearest preceding Markdown heading string (plain title), if any.
    let heading: String?
    /// Heading level 1...6 if preceding heading exists.
    let level: Int?
    /// 1-based line number for the offset, useful for outline work.
    let line: Int

    /// Derive an anchor from a source offset and full Markdown text using the real parser.
    static func anchor(for offset: Int, in text: String) -> DocumentAnchor {
        let clamped = max(0, min(offset, (text as NSString).length))
        let nsText = text as NSString
        let prefix = nsText.substring(to: clamped)
        // Count lines via \n; handles CRLF by counting \n only, but for line number we just count \n.
        let line = prefix.components(separatedBy: "\n").count
        let outline = DocumentOutlineParser.outline(from: text)
        let nearest = DocumentOutlineParser.nearestHeading(for: clamped, in: outline)
        return DocumentAnchor(
            offset: clamped,
            heading: nearest?.title,
            level: nearest?.level,
            line: line
        )
    }

    /// Factory from an outline item for navigation requests. Keeps UTF-16 offset authoritative.
    init(from item: DocumentOutlineItem, line: Int? = nil) {
        self.offset = item.sourceRange.location
        self.heading = item.title
        self.level = item.level
        if let line {
            self.line = line
        } else {
            // Approximate line from offset if not provided; compute via \n count.
            // This path is not used for navigation but keeps line available.
            self.line = 1
        }
    }

    init(offset: Int, heading: String?, level: Int?, line: Int) {
        self.offset = offset
        self.heading = heading
        self.level = level
        self.line = line
    }

    // Legacy initializer for tests that construct directly with heading only
    init(offset: Int, heading: String?, line: Int) {
        self.offset = offset
        self.heading = heading
        self.level = nil
        self.line = line
    }
}

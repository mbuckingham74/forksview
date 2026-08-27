import Foundation

/// Minimal semantic anchor for Milestone 5 position preservation.
/// Prefers source location + nearest heading over raw pixels.
///
/// This is intentionally small: full outline-navigation waits for Milestone 7.
/// If robust heading mapping requires parser/outline infrastructure, this
/// is the transitional representation and reading scroll-to-heading is documented
/// as a remaining limitation (see DocumentRootView).
struct DocumentAnchor: Equatable, Sendable {
    /// UTF-16 offset into document.text (NSTextView uses UTF-16 ranges).
    let offset: Int
    /// Nearest preceding Markdown heading string, if any.
    let heading: String?
    /// 1-based line number for the offset, useful for future outline work.
    let line: Int

    /// Derive an anchor from a source offset and full Markdown text.
    /// Heading detection is lightweight: search backwards for a line starting with `#`.
    static func anchor(for offset: Int, in text: String) -> DocumentAnchor {
        let clamped = max(0, min(offset, (text as NSString).length))
        // Convert UTF16 offset to String.Index for line calculation, but keep simple.
        let nsText = text as NSString
        let prefix = nsText.substring(to: clamped)
        // Line number = count of \n in prefix + 1
        let line = prefix.components(separatedBy: "\n").count
        let heading = nearestHeading(in: text, beforeUTF16Offset: clamped)
        return DocumentAnchor(offset: clamped, heading: heading, line: line)
    }

    private static func nearestHeading(in text: String, beforeUTF16Offset offset: Int) -> String? {
        let nsText = text as NSString
        let clamped = max(0, min(offset, nsText.length))
        let prefix = nsText.substring(to: clamped)
        let lineIndex = max(0, prefix.components(separatedBy: "\n").count - 1)
        let allLines = text.components(separatedBy: "\n")
        let upper = min(lineIndex, allLines.count - 1)
        for idx in stride(from: upper, through: 0, by: -1) {
            let raw = allLines[idx]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("#") else { continue }
            var hashCount = 0
            for ch in trimmed {
                if ch == "#" { hashCount += 1 } else { break }
            }
            guard (1...6).contains(hashCount) else { continue }
            let afterHashes = trimmed.dropFirst(hashCount)
            guard afterHashes.first == " " || afterHashes.first == "\t" else { continue }
            let headingText = afterHashes.trimmingCharacters(in: .whitespacesAndNewlines)
            if !headingText.isEmpty {
                return headingText
            }
        }
        return nil
    }
}

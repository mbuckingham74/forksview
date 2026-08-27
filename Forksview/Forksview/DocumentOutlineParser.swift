import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// Pure outline parser using cmark/GFM. No document mutation, no UI ownership.
enum DocumentOutlineParser {
    /// Derive outline items from Markdown source in source order.
    static func outline(from text: String) -> [DocumentOutlineItem] {
        // Ensure GFM extensions are registered once per parse.
        cmark_gfm_core_extensions_ensure_registered()

        let parser = cmark_parser_new(CMARK_OPT_DEFAULT)
        defer { cmark_parser_free(parser) }

        // Same GFM extensions as MarkdownUI renderer.
        let extensionNames: [String] = {
            if #available(macOS 13.0, *) {
                return ["autolink", "strikethrough", "tagfilter", "tasklist", "table"]
            } else {
                return ["autolink", "strikethrough", "tagfilter", "tasklist"]
            }
        }()
        for name in extensionNames {
            if let ext = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, ext)
            }
        }

        // Feed the entire source as UTF-8 byte count, same as cmark parser.
        // Using utf8 count matches MarkdownUI's approach.
        let utf8Count = text.utf8.count
        text.withCString { cStr in
            // Need raw pointer and length; cmark_parser_feed expects const char* and size_t
            cmark_parser_feed(parser, cStr, utf8Count)
        }

        guard let document = cmark_parser_finish(parser) else { return [] }
        defer { cmark_node_free(document) }

        // Walk tree and collect heading nodes in source order.
        var items: [DocumentOutlineItem] = []
        // Precompute line offsets for NSRange conversion
        let lineOffsets = computeLineStartOffsets(in: text)

        // Traverse via iterative DFS using cmark node iterator.
        let iterator = cmark_iter_new(document)
        defer { cmark_iter_free(iterator) }

        var event = cmark_iter_next(iterator)
        while event != CMARK_EVENT_DONE {
            if event == CMARK_EVENT_ENTER {
                guard let node = cmark_iter_get_node(iterator) else {
                    event = cmark_iter_next(iterator)
                    continue
                }
                let type = cmark_node_get_type(node)
                if type == CMARK_NODE_HEADING {
                    let level = Int(cmark_node_get_heading_level(node))
                    guard (1...6).contains(level) else {
                        event = cmark_iter_next(iterator)
                        continue
                    }
                    // Derive plain title by traversing children inline nodes
                    let title = plainText(for: node).trimmingCharacters(in: .whitespacesAndNewlines)
                    if title.isEmpty {
                        event = cmark_iter_next(iterator)
                        continue
                    }
                    // Source lines -> NSRange via line boundaries
                    let startLine = Int(cmark_node_get_start_line(node))
                    let endLine = Int(cmark_node_get_end_line(node))
                    if let range = nsRangeForLines(startLine: startLine, endLine: endLine, lineOffsets: lineOffsets, text: text) {
                        let item = DocumentOutlineItem(level: level, title: title, sourceRange: range)
                        items.append(item)
                    }
                }
            }
            event = cmark_iter_next(iterator)
        }

        return items
    }

    // MARK: - Plain text extraction

    /// Recursively collect plain text from heading node's inline children.
    private static func plainText(for headingNode: UnsafeMutablePointer<cmark_node>) -> String {
        var result = ""
        var child = cmark_node_first_child(headingNode)
        while let c = child {
            result += plainTextRecursive(node: c)
            child = cmark_node_next(c)
        }
        return result
    }

    private static func plainTextRecursive(node: UnsafeMutablePointer<cmark_node>) -> String {
        let type = cmark_node_get_type(node)
        // Leaf nodes with literal
        switch type {
        case CMARK_NODE_TEXT:
            if let ptr = cmark_node_get_literal(node) {
                return String(cString: ptr)
            }
            return ""
        case CMARK_NODE_CODE:
            if let ptr = cmark_node_get_literal(node) {
                return String(cString: ptr)
            }
            return ""
        case CMARK_NODE_HTML_INLINE:
            // HTML inline within heading is rarely human readable; treat as literal stripped?
            // For Milestone 7, we can ignore or include literal. Prefer empty to avoid polluting title.
            return ""
        case CMARK_NODE_LINEBREAK, CMARK_NODE_SOFTBREAK:
            return " "
        default:
            break
        }

        // Container nodes: recurse into children, handling specific types
        // These include EMPH, STRONG, STRIKETHROUGH, LINK, IMAGE, etc.
        // For LINK and IMAGE, their children contain the displayed text / alt text.
        // Image without alt but with literal? cmark may store alt as children.
        var text = ""
        var child = cmark_node_first_child(node)
        while let c = child {
            // For IMAGE, we want alt text (children). If no children but literal?, fallback.
            // For LINK, similar.
            text += plainTextRecursive(node: c)
            child = cmark_node_next(c)
        }
        // Special handling: if container had no children but type is e.g., IMAGE with no alt,
        // cmark may not have children. In that case return empty (omit).
        // Strikethrough, emph, strong already handled via children.
        return text
    }

    // MARK: - Line to NSRange conversion

    /// Compute UTF-16 offsets for each line start in text, handling \n and \r\n
    static func computeLineStartOffsets(in text: String) -> [Int] {
        let ns = text as NSString
        let length = ns.length
        var offsets: [Int] = [0]
        var i = 0
        while i < length {
            let ch = ns.character(at: i)
            if ch == 13 { // \r
                // Check for \r\n
                if i + 1 < length && ns.character(at: i + 1) == 10 {
                    i += 2
                } else {
                    i += 1
                }
                if i < length {
                    offsets.append(i)
                } else {
                    // Trailing newline creates an extra empty line start beyond length, but we don't need it for heading ranges.
                    // Still append to simplify?
                    offsets.append(i)
                }
            } else if ch == 10 { // \n
                i += 1
                if i <= length {
                    offsets.append(i)
                }
            } else {
                i += 1
            }
        }
        return offsets
    }

    /// Convert cmark startLine/endLine (1-based) to NSRange covering full heading block lines.
    /// Uses lineOffsets to avoid column trust. Excludes trailing newline after endLine where practical.
    static func nsRangeForLines(startLine: Int, endLine: Int, lineOffsets: [Int], text: String) -> NSRange? {
        guard startLine >= 1, endLine >= startLine else { return nil }
        let ns = text as NSString
        let totalLength = ns.length
        // lineOffsets is 0-based index for line 1 at offset 0
        // Need to handle case where requested line exceeds our offsets (e.g., empty trailing lines)
        // Clamp to valid.
        let startIdx = startLine - 1
        let endIdx = endLine - 1
        guard startIdx < lineOffsets.count else { return nil }

        let startOffset = lineOffsets[startIdx]

        // End offset: start of line after endLine, or end of text if no such line.
        // To exclude following newline, we want end = (next line start - newline length) OR totalLength if endLine is last line.
        let nextLineIdx = endIdx + 1
        let endOffset: Int
        if nextLineIdx < lineOffsets.count {
            // The line after endLine starts at lineOffsets[nextLineIdx]
            // Need to find the actual line end before its newline.
            // That is lineOffsets[nextLineIdx] minus the newline bytes (1 for \n, 2 for \r\n, 1 for \r)
            // Instead of inferring from offsets difference, look at the text between endLine's start and next line start.
            // The substring from lineOffsets[endIdx] to lineOffsets[nextLineIdx] includes the newline(s).
            // So the heading block without trailing newline is up to just before the newline.
            // We can compute by scanning backwards from lineOffsets[nextLineIdx] - 1 for newline characters.
            // Simpler: determine line ending length by checking characters before nextLineStart.
            let nextStart = lineOffsets[nextLineIdx]
            // Check 2-char \r\n
            if nextStart >= 2 {
                let prev2 = ns.character(at: nextStart - 2)
                let prev1 = ns.character(at: nextStart - 1)
                if prev2 == 13 && prev1 == 10 {
                    endOffset = nextStart - 2
                } else if prev1 == 10 || prev1 == 13 {
                    endOffset = nextStart - 1
                } else {
                    endOffset = nextStart
                }
            } else if nextStart >= 1 {
                let prev1 = ns.character(at: nextStart - 1)
                if prev1 == 10 || prev1 == 13 {
                    endOffset = nextStart - 1
                } else {
                    endOffset = nextStart
                }
            } else {
                endOffset = nextStart
            }
        } else {
            // No next line: heading is at EOF, use total length (but trim trailing \r/\n if present? For range we include full last line content without duplicating newline)
            // If text ends with newline, the last line is empty beyond endLine? Actually if endLine is last content line, and text ends with newline, then lineOffsets would have extra entry for trailing empty line.
            // But if endIdx is within offsets and nextLineIdx == count, then we're at last line and there is no newline after? Need to check if text ends with newline.
            // For safety, use totalLength but trim a trailing newline if the last character is newline and we are supposed to exclude it.
            // Spec says exclude following newline where practical, so for last line at EOF without newline, keep as is.
            // For last line that ends with newline (text ends with \n), the line content without newline is up to before that newline. But our totalLength includes that newline, so we should trim it.
            // Check if text ends with \r\n or \n or \r and endLine is last line before EOF.
            if totalLength > 0 {
                let lastChar = ns.character(at: totalLength - 1)
                if lastChar == 10 { // \n
                    if totalLength >= 2 && ns.character(at: totalLength - 2) == 13 {
                        // \r\n at end
                        // Need to ensure this newline belongs to endLine and not an extra empty line after.
                        // If endLine's start is before this newline, then trim.
                        // We can check if lineOffsets.last == totalLength (means empty line after final newline)
                        // Or just trim one newline sequence.
                        if lineOffsets.last == totalLength {
                            // There's an empty trailing line after heading, so heading's line already ended before last newline handling?
                            // Actually if text is "## Foo\n", lineOffsets = [0, 7] where 7 == totalLength. For endLine=1, nextLineIdx=1 < count, so we wouldn't be in this branch.
                            // So reaching here means endLine is beyond? Just use totalLength.
                            endOffset = totalLength
                        } else {
                            // No extra line, trim
                            if totalLength >= 2 && ns.character(at: totalLength - 2) == 13 {
                                endOffset = totalLength - 2
                            } else {
                                endOffset = totalLength - 1
                            }
                        }
                    } else {
                        // Single \n at end
                        if lineOffsets.last == totalLength {
                            // Reached earlier case, but just handle
                            endOffset = totalLength
                        } else {
                            endOffset = totalLength - 1
                        }
                    }
                } else if lastChar == 13 {
                    // \r at end
                    if lineOffsets.last == totalLength {
                        endOffset = totalLength
                    } else {
                        endOffset = totalLength - 1
                    }
                } else {
                    endOffset = totalLength
                }
            } else {
                endOffset = totalLength
            }
        }

        let start = max(0, min(startOffset, totalLength))
        let end = max(start, min(endOffset, totalLength))
        let length = end - start
        return NSRange(location: start, length: length)
    }
}

// MARK: - Helpers for anchor and duplicate resolution

extension DocumentOutlineParser {
    /// Find nearest preceding outline item for a given UTF-16 offset.
    static func nearestHeading(for offset: Int, in outline: [DocumentOutlineItem]) -> DocumentOutlineItem? {
        let clamped = max(0, offset)
        // Items are in source order, sourceRange.location increasing.
        var best: DocumentOutlineItem?
        for item in outline {
            if item.sourceRange.location <= clamped {
                best = item
            } else {
                break
            }
        }
        return best
    }

    /// Resolve duplicate occurrence index for an outline item within the outline.
    /// Returns 1-based occurrence count for same level+title before and including this item.
    static func occurrenceIndex(for item: DocumentOutlineItem, in outline: [DocumentOutlineItem]) -> (index: Int, total: Int) {
        let same = outline.filter { $0.level == item.level && $0.title == item.title }
        let total = same.count
        guard let idx = same.firstIndex(of: item) else { return (1, total) }
        return (idx + 1, total)
    }

    /// Resolve duplicate occurrence among rendered targets.
    static func renderedOccurrence(for item: DocumentOutlineItem, in rendered: [RenderedHeadingTarget]) -> RenderedHeadingTarget? {
        let sameLevelTitle = rendered.filter { $0.level == item.level && $0.plainTitle == item.title }
        guard !sameLevelTitle.isEmpty else { return nil }
        // Need outline occurrence index
        // But this helper is generic; caller should provide outline to compute index.
        return nil // placeholder; actual resolution done in resolver helper
    }
}

/// Helper for rendered heading targets published by MarkdownReadingView
struct RenderedHeadingTarget: Identifiable, Equatable, Sendable {
    let id: UUID
    let level: Int
    let plainTitle: String
}

/// Resolver for mapping outline items to rendered targets via level+title+occurrence
enum OutlineRenderedResolver {
    static func resolve(outlineItem: DocumentOutlineItem, outline: [DocumentOutlineItem], renderedTargets: [RenderedHeadingTarget]) -> RenderedHeadingTarget? {
        // Compute occurrence index of outlineItem within outline's duplicates
        let sameInOutline = outline.filter { $0.level == outlineItem.level && $0.title == outlineItem.title }
        guard let outlineIdx = sameInOutline.firstIndex(of: outlineItem) else { return nil }
        let sameInRendered = renderedTargets.filter { $0.level == outlineItem.level && $0.plainTitle == outlineItem.title }
        guard outlineIdx < sameInRendered.count else { return nil }
        return sameInRendered[outlineIdx]
    }

    /// Stale request check: does outline still contain the item's source location?
    static func isStale(request: DocumentNavigationRequest, outline: [DocumentOutlineItem]) -> Bool {
        // Find exact item by id (location) and level/title; if not found, stale
        return !outline.contains(where: { $0.id == request.anchor.offset && $0.level == (request.anchor.level ?? $0.level) && $0.title == (request.anchor.heading ?? $0.title) })
    }

    /// Alternative stale check via anchor existence in outline
    static func anchorExists(_ anchor: DocumentAnchor, in outline: [DocumentOutlineItem]) -> Bool {
        outline.contains(where: { $0.sourceRange.location == anchor.offset && $0.title == anchor.heading })
    }
}

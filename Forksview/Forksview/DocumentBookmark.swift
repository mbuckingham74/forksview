import Foundation

// MARK: - Bookmark Model (Milestone 8)

/// Durable app-owned reference to one semantic Markdown heading, and therefore to the section introduced by that heading, in one document.
/// Not an arbitrary caret, paragraph, scroll coordinate, selection, or workspace item.
/// Bookmarks remain outside the Markdown file.
struct DocumentBookmark: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let target: HeadingBookmarkTarget

    init(id: UUID = UUID(), target: HeadingBookmarkTarget) {
        self.id = id
        self.target = target
    }
}

struct HeadingBookmarkTarget: Codable, Equatable, Sendable {
    /// Heading level 1...6 captured at creation.
    let level: Int
    /// Plain heading title trimmed captured at creation.
    let title: String
    /// 1-based among headings with equal level + title at creation time.
    let occurrence: Int
    /// Number of headings with equal level + title at creation time.
    let matchingHeadingCount: Int
    /// UTF-16 source offset at creation.
    let sourceOffsetAtCreation: Int
}

// MARK: - Pure Resolver

enum DocumentBookmarkResolver {
    enum Resolution: Sendable {
        case resolved(DocumentOutlineItem)
        case stale
    }

    /// Deterministic policy:
    /// 1) Exact current heading matching sourceOffsetAtCreation + level + title
    /// 2) Fallback: find headings with equal level+title, valid only when current matching count == captured matchingHeadingCount, then select captured 1-based occurrence. Otherwise stale. No guessing, no fuzzy.
    static func resolve(_ bookmark: DocumentBookmark, in outline: [DocumentOutlineItem]) -> Resolution {
        let t = bookmark.target
        // First choice: exact offset + level + title
        if let exact = outline.first(where: { $0.sourceRange.location == t.sourceOffsetAtCreation && $0.level == t.level && $0.title == t.title }) {
            return .resolved(exact)
        }
        // Fallback: equal level + title
        let matching = outline.filter { $0.level == t.level && $0.title == t.title }
        guard matching.count == t.matchingHeadingCount else {
            return .stale
        }
        // Select occurrence (1-based)
        let idx = t.occurrence - 1
        guard idx >= 0, idx < matching.count else {
            return .stale
        }
        // Ensure occurrence is within bounds and matching count preserved (already checked)
        return .resolved(matching[idx])
    }

    /// Whether bookmark is currently resolvable.
    static func isResolvable(_ bookmark: DocumentBookmark, in outline: [DocumentOutlineItem]) -> Bool {
        if case .resolved = resolve(bookmark, in: outline) { return true }
        return false
    }

    /// Returns resolved item if any.
    static func resolvedItem(for bookmark: DocumentBookmark, in outline: [DocumentOutlineItem]) -> DocumentOutlineItem? {
        if case let .resolved(item) = resolve(bookmark, in: outline) { return item }
        return nil
    }

    /// Determine if a given outline item is bookmarked via resolver semantics (not title alone). Used to prevent duplicate bookmarks per resolved heading and for toggle state.
    static func isBookmarked(item: DocumentOutlineItem, bookmarks: [DocumentBookmark], outline: [DocumentOutlineItem]) -> Bool {
        for bm in bookmarks {
            if case let .resolved(resolvedItem) = resolve(bm, in: outline), resolvedItem == item {
                return true
            }
        }
        return false
    }

    /// Find bookmark that resolves to given outline item, if any.
    static func bookmark(for item: DocumentOutlineItem, in bookmarks: [DocumentBookmark], outline: [DocumentOutlineItem]) -> DocumentBookmark? {
        for bm in bookmarks {
            if case let .resolved(resolvedItem) = resolve(bm, in: outline), resolvedItem == item {
                return bm
            }
        }
        return nil
    }

    /// Ordering: 1) resolved bookmarks in current document source order; 2) stale bookmarks afterward; stale ordering by captured source offset, then UUID for deterministic tie-breaking.
    static func ordered(_ bookmarks: [DocumentBookmark], in outline: [DocumentOutlineItem]) -> [DocumentBookmark] {
        var resolved: [(bookmark: DocumentBookmark, offset: Int)] = []
        var stale: [DocumentBookmark] = []
        for bm in bookmarks {
            if case let .resolved(item) = resolve(bm, in: outline) {
                resolved.append((bm, item.sourceRange.location))
            } else {
                stale.append(bm)
            }
        }
        resolved.sort { $0.offset < $1.offset }
        stale.sort {
            if $0.target.sourceOffsetAtCreation != $1.target.sourceOffsetAtCreation {
                return $0.target.sourceOffsetAtCreation < $1.target.sourceOffsetAtCreation
            }
            return $0.id.uuidString < $1.id.uuidString
        }
        return resolved.map(\.bookmark) + stale
    }

    /// Factory helper to capture target fields for a given outline item in current outline.
    static func target(for item: DocumentOutlineItem, in outline: [DocumentOutlineItem]) -> HeadingBookmarkTarget {
        let same = outline.filter { $0.level == item.level && $0.title == item.title }
        let total = same.count
        let idx = (same.firstIndex(of: item) ?? 0) + 1 // 1-based
        return HeadingBookmarkTarget(
            level: item.level,
            title: item.title,
            occurrence: idx,
            matchingHeadingCount: total,
            sourceOffsetAtCreation: item.sourceRange.location
        )
    }
}

// MARK: - Ordering Helpers for Store Persistence (pure)

extension DocumentBookmark {
    /// Convenience to create bookmark for an outline item
    static func make(for item: DocumentOutlineItem, in outline: [DocumentOutlineItem], id: UUID = UUID()) -> DocumentBookmark {
        let target = DocumentBookmarkResolver.target(for: item, in: outline)
        return DocumentBookmark(id: id, target: target)
    }
}

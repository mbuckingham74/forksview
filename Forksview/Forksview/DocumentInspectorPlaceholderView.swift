import SwiftUI

@MainActor
struct DocumentInspectorPlaceholderView: View {
    var outline: [DocumentOutlineItem] = []
    var bookmarks: [DocumentBookmark] = []
    var onSelect: ((DocumentOutlineItem) -> Void)? = nil
    var onToggleBookmark: ((DocumentOutlineItem) -> Void)? = nil
    var onSelectBookmark: ((DocumentBookmark) -> Void)? = nil
    var onRemoveBookmark: ((DocumentBookmark) -> Void)? = nil

    // Default init for backward compat / previews
    init() {
        self.outline = []
        self.bookmarks = []
        self.onSelect = nil
        self.onToggleBookmark = nil
        self.onSelectBookmark = nil
        self.onRemoveBookmark = nil
    }

    init(outline: [DocumentOutlineItem], onSelect: @escaping (DocumentOutlineItem) -> Void) {
        self.outline = outline
        self.bookmarks = []
        self.onSelect = onSelect
        self.onToggleBookmark = nil
        self.onSelectBookmark = nil
        self.onRemoveBookmark = nil
    }

    // Full init for Milestone 8
    init(
        outline: [DocumentOutlineItem],
        bookmarks: [DocumentBookmark],
        onSelect: @escaping (DocumentOutlineItem) -> Void,
        onToggleBookmark: @escaping (DocumentOutlineItem) -> Void,
        onSelectBookmark: @escaping (DocumentBookmark) -> Void,
        onRemoveBookmark: @escaping (DocumentBookmark) -> Void
    ) {
        self.outline = outline
        self.bookmarks = bookmarks
        self.onSelect = onSelect
        self.onToggleBookmark = onToggleBookmark
        self.onSelectBookmark = onSelectBookmark
        self.onRemoveBookmark = onRemoveBookmark
    }

    private var orderedBookmarks: [DocumentBookmark] {
        DocumentBookmarkResolver.ordered(bookmarks, in: outline)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("On This Page")
                        .font(.headline)
                        .accessibilityIdentifier("onThisPageSection")
                    // Outline container
                    Group {
                        if outline.isEmpty {
                            Text("No headings")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("documentOutline")
                        } else {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(outline) { item in
                                    let isBookmarked = DocumentBookmarkResolver.isBookmarked(item: item, bookmarks: bookmarks, outline: outline)
                                    let occurrence = occurrenceInfo(for: item)
                                    let label: String = {
                                        let base = "\(item.title), heading level \(item.level)"
                                        if occurrence.total > 1 {
                                            return "\(base), \(occurrence.index) of \(occurrence.total)"
                                        }
                                        return base
                                    }()
                                    let toggleLabel = isBookmarked ? "Remove bookmark, \(label)" : "Add bookmark, \(label)"
                                    HStack(spacing: 4) {
                                        Button(action: {
                                            onSelect?(item)
                                        }) {
                                            Text(item.title)
                                                .font(.subheadline)
                                                .foregroundStyle(.primary)
                                                .multilineTextAlignment(.leading)
                                                .lineLimit(2)
                                                .truncationMode(.tail)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(.leading, CGFloat(max(0, item.level - 1)) * 12)
                                                .padding(.vertical, 4)
                                                .padding(.horizontal, 6)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel(label)
                                        .accessibilityIdentifier("documentOutlineItem-\(item.sourceRange.location)")
                                        .help(item.title)

                                        // Bookmark toggle
                                        Button(action: {
                                            if let toggle = onToggleBookmark {
                                                toggle(item)
                                            } else {
                                                // Fallback no-op for legacy init
                                            }
                                        }) {
                                            Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                                                .font(.system(size: 12))
                                                .foregroundStyle(isBookmarked ? Color.accentColor : .secondary)
                                                .frame(width: 20, height: 20)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel(toggleLabel)
                                        .accessibilityValue(isBookmarked ? "Bookmarked" : "")
                                        .accessibilityIdentifier("documentBookmarkToggle-\(item.sourceRange.location)")
                                        .help(isBookmarked ? "Remove bookmark" : "Add bookmark")
                                    }
                                    .padding(.vertical, 1)
                                }
                            }
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("documentOutline")
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("onThisPageSection")

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Bookmarks")
                        .font(.headline)
                        .accessibilityIdentifier("bookmarksSection")
                    Group {
                        if orderedBookmarks.isEmpty {
                            Text("No bookmarks yet")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("documentBookmarksEmptyState")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(orderedBookmarks) { bookmark in
                                    let resolution = DocumentBookmarkResolver.resolve(bookmark, in: outline)
                                    switch resolution {
                                    case .resolved(let item):
                                        let occurrence = occurrenceInfo(for: item)
                                        let bookmarkLabel: String = {
                                            let base = "\(bookmark.target.title), heading level \(bookmark.target.level)"
                                            if bookmark.target.matchingHeadingCount > 1 || occurrence.total > 1 {
                                                // Use captured occurrence for label? But for resolved we can show current occurrence.
                                                // Spec: bookmark row: "Installation, heading level 2, 2 of 3"
                                                // We should prefer captured occurrence when possible, but show current occurrence for consistency.
                                                let idx = bookmark.target.occurrence
                                                let total = bookmark.target.matchingHeadingCount
                                                if total > 1 {
                                                    return "\(base), \(idx) of \(total)"
                                                }
                                                if occurrence.total > 1 {
                                                    return "\(base), \(occurrence.index) of \(occurrence.total)"
                                                }
                                                return base
                                            }
                                            return base
                                        }()
                                        HStack(spacing: 4) {
                                            Button(action: {
                                                onSelectBookmark?(bookmark)
                                            }) {
                                                Text(bookmark.target.title)
                                                    .font(.subheadline)
                                                    .foregroundStyle(.primary)
                                                    .multilineTextAlignment(.leading)
                                                    .lineLimit(2)
                                                    .truncationMode(.tail)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                    .padding(.vertical, 4)
                                                    .padding(.horizontal, 6)
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityLabel(bookmarkLabel)
                                            .accessibilityIdentifier("documentBookmarkItem-\(bookmark.id.uuidString)")
                                            .help(bookmark.target.title)

                                            // Remove button (always enabled)
                                            Button(action: {
                                                onRemoveBookmark?(bookmark)
                                            }) {
                                                Image(systemName: "xmark")
                                                    .font(.system(size: 10, weight: .semibold))
                                                    .foregroundStyle(.secondary)
                                                    .frame(width: 20, height: 20)
                                                    .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityLabel("Remove bookmark, \(bookmark.target.title)")
                                            .accessibilityIdentifier("removeDocumentBookmark-\(bookmark.id.uuidString)")
                                            .help("Remove bookmark")
                                        }
                                        .background(Color.clear)
                                        .contentShape(Rectangle())
                                    case .stale:
                                        let staleLabel: String = {
                                            let base = "\(bookmark.target.title), heading level \(bookmark.target.level)"
                                            if bookmark.target.matchingHeadingCount > 1 {
                                                return "\(base), \(bookmark.target.occurrence) of \(bookmark.target.matchingHeadingCount)"
                                            }
                                            return base
                                        }()
                                        HStack(spacing: 4) {
                                            // Stale navigation portion disabled
                                            Button(action: {}) {
                                                Text(bookmark.target.title)
                                                    .font(.subheadline)
                                                    .foregroundStyle(.secondary)
                                                    .multilineTextAlignment(.leading)
                                                    .lineLimit(2)
                                                    .truncationMode(.tail)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                    .padding(.vertical, 4)
                                                    .padding(.horizontal, 6)
                                            }
                                            .buttonStyle(.plain)
                                            .disabled(true)
                                            .accessibilityLabel(staleLabel)
                                            .accessibilityValue("unavailable")
                                            .accessibilityIdentifier("documentBookmarkItem-\(bookmark.id.uuidString)")
                                            .opacity(0.6)

                                            // Remove remains enabled
                                            Button(action: {
                                                onRemoveBookmark?(bookmark)
                                            }) {
                                                Image(systemName: "xmark")
                                                    .font(.system(size: 10, weight: .semibold))
                                                    .foregroundStyle(.secondary)
                                                    .frame(width: 20, height: 20)
                                                    .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityLabel("Remove bookmark, \(bookmark.target.title)")
                                            .accessibilityIdentifier("removeDocumentBookmark-\(bookmark.id.uuidString)")
                                            .help("Remove bookmark")
                                        }
                                        .foregroundStyle(.secondary)
                                        .opacity(0.8)
                                    }
                                }
                            }
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("documentBookmarks")
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("bookmarksSection")

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("documentInspector")
    }

    private func occurrenceInfo(for item: DocumentOutlineItem) -> (index: Int, total: Int) {
        let same = outline.filter { $0.level == item.level && $0.title == item.title }
        let total = same.count
        guard let idx = same.firstIndex(of: item) else { return (1, total) }
        return (idx + 1, total)
    }
}

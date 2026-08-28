import SwiftUI
import AppKit

@MainActor
struct DocumentInspectorPlaceholderView: View {
    var outline: [DocumentOutlineItem] = []
    var bookmarks: [DocumentBookmark] = []
    var onSelect: ((DocumentOutlineItem) -> Void)? = nil
    var onToggleBookmark: ((DocumentOutlineItem) -> Void)? = nil
    var onSelectBookmark: ((DocumentBookmark) -> Void)? = nil
    var onRemoveBookmark: ((DocumentBookmark) -> Void)? = nil
    var isEditing: Bool = false

    private enum BookmarkFocusTarget: Hashable {
        case heading
        case empty
        case remove(UUID)
    }

    @FocusState private var focusedBookmark: BookmarkFocusTarget?

    // Default init for backward compat / previews
    init() {
        self.outline = []
        self.bookmarks = []
        self.onSelect = nil
        self.onToggleBookmark = nil
        self.onSelectBookmark = nil
        self.onRemoveBookmark = nil
        self.isEditing = false
    }

    init(outline: [DocumentOutlineItem], onSelect: @escaping (DocumentOutlineItem) -> Void) {
        self.outline = outline
        self.bookmarks = []
        self.onSelect = onSelect
        self.onToggleBookmark = nil
        self.onSelectBookmark = nil
        self.onRemoveBookmark = nil
        self.isEditing = false
    }

    // Full init for Milestone 8
    init(
        outline: [DocumentOutlineItem],
        bookmarks: [DocumentBookmark],
        onSelect: @escaping (DocumentOutlineItem) -> Void,
        onToggleBookmark: @escaping (DocumentOutlineItem) -> Void,
        onSelectBookmark: @escaping (DocumentBookmark) -> Void,
        onRemoveBookmark: @escaping (DocumentBookmark) -> Void,
        isEditing: Bool = false
    ) {
        self.outline = outline
        self.bookmarks = bookmarks
        self.onSelect = onSelect
        self.onToggleBookmark = onToggleBookmark
        self.onSelectBookmark = onSelectBookmark
        self.onRemoveBookmark = onRemoveBookmark
        self.isEditing = isEditing
    }

    private var orderedBookmarks: [DocumentBookmark] {
        DocumentBookmarkResolver.ordered(bookmarks, in: outline)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // On This Page — flexible height, independently scrollable
            VStack(alignment: .leading, spacing: 8) {
                Text("On This Page")
                    .font(.headline)
                ScrollView {
                    outlineContent
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, 2)
                }
                .scrollIndicators(.visible)
                .frame(maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .layoutPriority(1)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("onThisPageSection")
            .accessibilityLabel("On This Page")

            Divider()
                .padding(.vertical, 8)

            // Bookmarks — always discoverable below outline, independently scrollable, bounded height
            VStack(alignment: .leading, spacing: 8) {
                Text("Bookmarks")
                    .font(.headline)
                    .accessibilityIdentifier("bookmarksHeading")
                    .accessibilityAddTraits(.isHeader)
                    .focusable(true)
                    .focused($focusedBookmark, equals: .heading)
                Group {
                    if orderedBookmarks.isEmpty {
                        Text("No bookmarks yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("documentBookmarksEmptyState")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .focusable(true)
                            .focused($focusedBookmark, equals: .empty)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(orderedBookmarks) { bookmark in
                                    let resolution = DocumentBookmarkResolver.resolve(bookmark, in: outline)
                                    switch resolution {
                                    case .resolved(let item):
                                        let occurrence = occurrenceInfo(for: item)
                                        let bookmarkLabel: String = {
                                            let base = "\(bookmark.target.title), heading level \(bookmark.target.level)"
                                            if bookmark.target.matchingHeadingCount > 1 || occurrence.total > 1 {
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
                                            .focusable(true)
                                            .keyboardActivates { onSelectBookmark?(bookmark) }

                                            // Remove button (always enabled)
                                            Button(action: {
                                                handleRemove(bookmark)
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
                                            .focusable(true)
                                            .focused($focusedBookmark, equals: .remove(bookmark.id))
                                            .keyboardActivates { handleRemove(bookmark) }
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
                                            // Stale navigation portion disabled with visible unavailable semantics
                                            Button(action: {}) {
                                                HStack(spacing: 4) {
                                                    Text(bookmark.target.title)
                                                        .font(.subheadline)
                                                        .foregroundStyle(.secondary)
                                                        .multilineTextAlignment(.leading)
                                                        .lineLimit(2)
                                                        .truncationMode(.tail)
                                                    Text("Unavailable")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                        .accessibilityLabel("Unavailable")
                                                    Image(systemName: "exclamationmark.triangle.fill")
                                                        .font(.system(size: 10))
                                                        .foregroundStyle(.secondary)
                                                        .accessibilityHidden(true)
                                                }
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(.vertical, 4)
                                                .padding(.horizontal, 6)
                                            }
                                            .buttonStyle(.plain)
                                            .disabled(true)
                                            .accessibilityLabel("\(staleLabel), Unavailable")
                                            .accessibilityValue("unavailable")
                                            .accessibilityIdentifier("documentBookmarkItem-\(bookmark.id.uuidString)")
                                            .opacity(0.85)

                                            // Remove remains enabled
                                            Button(action: {
                                                handleRemove(bookmark)
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
                                            .focusable(true)
                                            .focused($focusedBookmark, equals: .remove(bookmark.id))
                                            .keyboardActivates { handleRemove(bookmark) }
                                        }
                                        .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.trailing, 2)
                        }
                        .scrollIndicators(.visible)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("documentBookmarks")
                    }
                }
            }
            .frame(minHeight: 120, idealHeight: 160, maxHeight: 220, alignment: .topLeading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("bookmarksSection")
            .accessibilityLabel("Bookmarks")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("documentInspector")
        .accessibilityLabel("Inspector")
    }

    private var outlineContent: some View {
        Group {
            if outline.isEmpty {
                Text("No headings")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("documentOutline")
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                            .focusable(true)
                            .keyboardActivates { onSelect?(item) }

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
                            .accessibilityValue(isBookmarked ? "Bookmarked" : "Not bookmarked")
                            .accessibilityIdentifier("documentBookmarkToggle-\(item.sourceRange.location)")
                            .help(isBookmarked ? "Remove bookmark" : "Add bookmark")
                            .focusable(true)
                            .keyboardActivates { onToggleBookmark?(item) }
                        }
                        .padding(.vertical, 1)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("documentOutline")
                .accessibilityLabel("Outline")
            }
        }
    }

    private func handleRemove(_ bookmark: DocumentBookmark) {
        let keyWindow = NSApp.keyWindow
        let editorToRestore: NSTextView? = {
            if let firstResponder = keyWindow?.firstResponder as? NSTextView,
               firstResponder.accessibilityIdentifier() == "markdownTextEditor" {
                return firstResponder
            }
            guard isEditing, let contentView = keyWindow?.contentView else { return nil }
            return findEditor(in: contentView)
        }()
        // Deterministic focus movement after removal
        let ordered = orderedBookmarks
        guard let idx = ordered.firstIndex(where: { $0.id == bookmark.id }) else {
            onRemoveBookmark?(bookmark)
            return
        }
        // Determine target for focus after removal
        let focusTarget: BookmarkFocusTarget
        if ordered.count > 1 {
            if idx + 1 < ordered.count {
                let next = ordered[idx + 1]
                focusTarget = .remove(next.id)
            } else if idx - 1 >= 0 {
                let prev = ordered[idx - 1]
                focusTarget = .remove(prev.id)
            } else {
                focusTarget = .heading
            }
        } else {
            focusTarget = .empty
        }
        onRemoveBookmark?(bookmark)
        if let keyWindow, let editorToRestore {
            // Removing a bookmark while editing must not strand the native editor;
            // preserve the established editing workflow after the inspector action.
            DispatchQueue.main.async {
                if editorToRestore.window === keyWindow {
                    keyWindow.makeFirstResponder(editorToRestore)
                }
            }
            return
        }
        DispatchQueue.main.async {
            DispatchQueue.main.async {
                focusedBookmark = focusTarget
            }
            guard let window = NSApp.keyWindow else { return }
            // SwiftUI focus state above handles native buttons and text targets.
            // Keep the window active when removal was initiated from a sheet or
            // another window, without replacing the selected target.
            if !window.isKeyWindow { window.makeKey() }
        }
    }

    private func occurrenceInfo(for item: DocumentOutlineItem) -> (index: Int, total: Int) {
        let same = outline.filter { $0.level == item.level && $0.title == item.title }
        let total = same.count
        guard let idx = same.firstIndex(of: item) else { return (1, total) }
        return (idx + 1, total)
    }

    private func findEditor(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView,
           textView.accessibilityIdentifier() == "markdownTextEditor" {
            return textView
        }
        for subview in view.subviews {
            if let editor = findEditor(in: subview) { return editor }
        }
        return nil
    }
}

private extension View {
    func keyboardActivates(_ action: @escaping () -> Void) -> some View {
        onKeyPress(keys: [.space, .return], phases: [.down]) { _ in
            action()
            return .handled
        }
    }
}

# Forksview Architecture

## Accepted foundation

Forksview uses an AppKit document core: `NSDocument`, `NSDocumentController`, `NSWindowController`, and `NSHostingController` for SwiftUI content. AppKit owns document lifecycle, standard commands, reading and writing, undo, autosave, conflicts, window state, recent documents, and the text editor.

SwiftUI owns the three-pane presentation, reading view, History, outline, bookmarks, toolbar, and their states. Editing uses a plain-text `NSTextView` through `NSViewRepresentable`. Begin with TextKit 1 compatibility and non-destructive temporary attributes for syntax highlighting. Disable smart quote and dash substitutions while preserving native undo, find/replace, spellchecking, selection, text services, and accessibility.

Use `NSDocumentController.shared.recentDocumentURLs`; do not create a second recent-file database. Disable App Sandbox for personal v1 and keep Hardened Runtime enabled. Use the imported Markdown UTI `net.daringfireball.markdown`, with the Editor document role and `.md`/`.markdown` support.

Derived outline metadata never modifies the Markdown file. Store user bookmarks as small, versioned Codable data in Application Support—not in sidecars, extended attributes, SwiftData, or Core Data.

External-change handling must distinguish clean reloads, dirty conflicts, and the app’s own saves. Preserve reading/editing position across mode changes using semantic heading/source anchors rather than raw pixels.

Keep one application target with logical source folders. Avoid internal frameworks, service locators, generic repositories, and speculative abstractions. The accepted deployment target is macOS 26.0. This avoids unnecessary compatibility work for a personal macOS 26 app. The proposed Swift language mode is Swift 6 with default `MainActor` isolation.

## Renderer decision

Spike completed 2026-08-26 against `Forksview/Forksview/Fixtures/AcceptanceFixture.md`, covering headings, emphasis, links, ordered/unordered lists, blockquotes, fenced code, tables, task lists, local/relative and remote images, duplicate headings, selection/copying, theming, and long-document behavior. Verified on macOS 26 / Xcode 26.6 / Swift 6.

`swift-cmark` 0.8.0 (2026-05-07) remains current and is suitable as a semantic parser for headings/source structure, but is parser-only and would require a bespoke renderer.

MarkdownUI 2.4.1 is the latest stable release (maintenance mode, not deprecated; Textual is the actively developed successor but was pre-1.0 at review: 0.5.0 on 2026-06-15, macOS 15+). MarkdownUI 2.4.1 requires macOS 12+ (tables/multi-image on 13+) and remains compatible with macOS 26 + Swift 6.

**Selected: MarkdownUI 2.4.1** via `https://github.com/gonzalezreal/swift-markdown-ui` (`upToNextMajorVersion` 2.4.1, product `MarkdownUI`). It provides GFM headings, emphasis, links, lists including task lists, blockquotes, fenced code, tables, and images (local via `baseURL`, remote via NetworkImage), selectable text (`.textSelection(.enabled)`), clickable links, sensible code blocks and tables via the built-in `gitHub` theme, dark/light appearance, and reasonable long-document behavior inside a `ScrollView`. The dependency is isolated behind the app-owned `MarkdownReadingView`; `MarkdownDocument` retains no parsing/rendering concerns and native edit mode is untouched. Textual remains a future option once it reaches 1.0 but is not adopted for this spike.

## Milestone 8: Persistent Heading Bookmarks

A Forksview bookmark is a durable app-owned reference to one semantic Markdown heading, and therefore to the section introduced by that heading, in one document. It is not an arbitrary caret, paragraph, scroll coordinate, or workspace item and remains outside the Markdown file.

- **Document ownership:** `MarkdownDocument` owns the open document's `bookmarks: [DocumentBookmark]` collection via `@Published private(set) var bookmarks`. This does not make bookmarks Markdown content. `MarkdownDocument.text -> data(ofType:)` remains the only Markdown serialization path; bookmarks never appear in saved `.md` bytes. The SwiftUI inspector does not own persistence. Bookmarks display as a flat list ordered: resolved bookmarks in current document source order, then stale bookmarks ordered by captured source offset, then UUID for deterministic tie-breaking.

- **Model:** `DocumentBookmark` (`id: UUID`, `target: HeadingBookmarkTarget`) with `HeadingBookmarkTarget` capturing `level`, `title`, `occurrence` (1-based among headings with equal level+title), `matchingHeadingCount`, and `sourceOffsetAtCreation` (UTF-16). `occurrence` and `matchingHeadingCount` distinguish duplicate headings. Captured fields are immutable; current location is recomputed against the current outline.

- **Resolver:** Pure `DocumentBookmarkResolver` with deterministic policy: first exact match on `sourceOffsetAtCreation + level + title`; fallback to equal `level+title` only when current matching count equals captured `matchingHeadingCount`, then select captured `occurrence`. Otherwise stale. No guessing, fuzzy-match, or context snippets.

- **Edit-resilience:** Text inserted above or unique heading moved resolves at new offset; heading renamed or deleted becomes stale; duplicate cardinality changes conservatively produce stale.

- **Persistence:** `DocumentBookmarkStore` uses one versioned Codable JSON archive (`BookmarkArchive` schemaVersion 1) at `~/Library/Application Support/org.mzb74.Forksview/Bookmarks.json` located via Foundation `urls(for: .applicationSupportDirectory)`, atomically written. Envelope: `BookmarkArchive` + `PersistedDocumentBookmarks` (`id`, `fileBookmarkData`, `lastKnownPath`, `bookmarks`).

- **File identity:** Normal Foundation URL bookmark data (not security-scoped), created with `url.bookmarkData(options: [], ...)` and resolved with `.withoutUI` `.withoutMounting`. Stale data refreshed. `lastKnownPath` is diagnostic only; path is not primary identity.

- **Bounded behavior:** Rename/move on same filesystem resolves via Foundation bookmark; Save As clones bookmark set to destination and binds active document to destination while original keeps its record; Finder copy creates new identity; deleted/unavailable file does not auto-delete records; untitled bookmarks exist in-memory and bind on first save; never-saved untitled discards bookmarks; corrupt/unknown schema archives are preserved, fail nonfatally, and do not overwrite with empty archive.

- **Testability:** Store supports injected archive URL and test-only launch environment override `FORKSVIEW_BOOKMARK_ARCHIVE_PATH` (and `FORKSVIEW_BOOKMARKS_PATH`) for isolated persistence/relaunch UI tests. No production-visible setting.

- **UI:** Outline rows gain trailing bookmark toggle (`bookmark` / `bookmark.fill`); Bookmarks section shows resolved rows with clickable title navigation and trailing remove, stale rows disabled (`unavailable`) but removable, empty state `No bookmarks yet` preserved. Accessibility identifiers: `bookmarksSection`, `documentBookmarks`, `documentBookmarksEmptyState`, `documentBookmarkToggle-<offset>`, `documentBookmarkItem-<uuid>`, `removeDocumentBookmark-<uuid>`.

- **Navigation:** Bookmark row navigates by resolving against current outline to `DocumentAnchor(from: resolvedOutlineItem)` → fresh `DocumentNavigationRequest` → `DocumentRootView` → reading (scroll) or editing (caret, scroll, focus) via existing M7 route; presentation mode unchanged; `DocumentNavigationRequest` unmodified; no parallel navigation system.

- **Dirty/Undo boundary:** `addBookmark` / `removeBookmark` / `toggleBookmark` and navigation do not change `text`, call `updateChangeCount`, set dirty, register with `undoManager`, or create save sheets. Bookmark Undo deferred (no second Undo system).

- **Multi-document isolation:** Two open documents maintain independent bookmark collections; persistence store may be shared internally but mutations are scoped per document record; two untitled documents have independent session bookmarks; no global bookmark UI.

## Milestone order

1. Configuration and document skeleton
2. Standard document operations
3. Native editor
4. Parser/renderer acceptance spike
5. Reading/editing transition
6. Three-pane shell
7. Outline navigation
8. Bookmarks
9. External-change safety and autosave
10. Visual/accessibility pass

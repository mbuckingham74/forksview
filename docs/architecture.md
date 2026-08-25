# Forksview Architecture

## Accepted foundation

Forksview uses an AppKit document core: `NSDocument`, `NSDocumentController`, `NSWindowController`, and `NSHostingController` for SwiftUI content. AppKit owns document lifecycle, standard commands, reading and writing, undo, autosave, conflicts, window state, recent documents, and the text editor.

SwiftUI owns the three-pane presentation, reading view, History, outline, bookmarks, toolbar, and their states. Editing uses a plain-text `NSTextView` through `NSViewRepresentable`. Begin with TextKit 1 compatibility and non-destructive temporary attributes for syntax highlighting. Disable smart quote and dash substitutions while preserving native undo, find/replace, spellchecking, selection, text services, and accessibility.

Use `NSDocumentController.shared.recentDocumentURLs`; do not create a second recent-file database. Disable App Sandbox for personal v1 and keep Hardened Runtime enabled. Use the imported Markdown UTI `net.daringfireball.markdown`, with the Editor document role and `.md`/`.markdown` support.

Derived outline metadata never modifies the Markdown file. Store user bookmarks as small, versioned Codable data in Application Support—not in sidecars, extended attributes, SwiftData, or Core Data.

External-change handling must distinguish clean reloads, dirty conflicts, and the app’s own saves. Preserve reading/editing position across mode changes using semantic heading/source anchors rather than raw pixels.

Keep one application target with logical source folders. Avoid internal frameworks, service locators, generic repositories, and speculative abstractions. The proposed deployment target is macOS 15.0. The proposed Swift language mode is Swift 6 with default `MainActor` isolation.

## Renderer decision

Renderer selection is deliberately deferred until an acceptance spike. `swift-markdown` 0.8.0 was current at the 2026-08-24 review and is the proposed semantic parser for headings/source structure, subject to re-verification when adopted.

MarkdownUI is in maintenance mode, not deprecated. MarkdownUI 2.4.1—not 2.1.0—was its latest stable release at the 2026-08-24 review. Textual is the actively developed successor but was pre-1.0.

The acceptance spike must compare the then-current compatible releases against the same fixture covering headings, links, lists, blockquotes, fenced code, tables, task lists, local/relative images, remote images, duplicate headings, text selection, theming, and long-document performance. No Markdown dependency is approved until that spike passes. Keep the renderer behind an app-owned `MarkdownReadingView` adapter.

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

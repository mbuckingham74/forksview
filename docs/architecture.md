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

`swift-markdown` 0.8.0 (2026-05-07) remains current and is suitable as a semantic parser for headings/source structure, but is parser-only and would require a bespoke renderer.

MarkdownUI 2.4.1 is the latest stable release (maintenance mode, not deprecated; Textual is the actively developed successor but was pre-1.0 at review: 0.5.0 on 2026-06-15, macOS 15+). MarkdownUI 2.4.1 requires macOS 12+ (tables/multi-image on 13+) and remains compatible with macOS 26 + Swift 6.

**Selected: MarkdownUI 2.4.1** via `https://github.com/gonzalezreal/swift-markdown-ui` (`upToNextMajorVersion` 2.4.1, product `MarkdownUI`). It provides GFM headings, emphasis, links, lists including task lists, blockquotes, fenced code, tables, and images (local via `baseURL`, remote via NetworkImage), selectable text (`.textSelection(.enabled)`), clickable links, sensible code blocks and tables via the built-in `gitHub` theme, dark/light appearance, and reasonable long-document behavior inside a `ScrollView`. The dependency is isolated behind the app-owned `MarkdownReadingView`; `MarkdownDocument` retains no parsing/rendering concerns and native edit mode is untouched. Textual remains a future option once it reaches 1.0 but is not adopted for this spike.

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

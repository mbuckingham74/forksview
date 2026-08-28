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

## Milestone 9: External-change safety and autosave

Forksview retains traditional explicit-save semantics while using AppKit's native out-of-place crash-recovery autosaving.

- **Autosave policy:** `MarkdownDocument.autosavesInPlace == false`, `MarkdownDocument.autosavesDrafts == false`, `NSDocumentController.shared.autosavingDelay = 30` set once at launch after obtaining the shared controller. No custom timer, no override of `scheduleAutosaving()`, `autosave(withImplicitCancellability:completionHandler:)`, `autosavingFileType`, or `autosavedContentsFileURL`. Named and untitled dirty documents use `.autosaveElsewhereOperation`; real file bytes never overwritten, `fileURL` unchanged (`nil` for untitled), `isDocumentEdited` remains true, `hasUnautosavedChanges` becomes false after snapshot and true again after next edit. Recovery URLs never become bookmark identities.

- **External-change detection:** Uses `NSDocument`'s existing `NSFilePresenter` conformance. No second presenter, `DispatchSource`, `FSEvents`, polling, hashing, watcher, or conflict database. Overrides `presentedItemDidChange()` (calls `super`, lightweight, schedules instance-scoped work onto `MainActor`, coalesces duplicates, re-checks `isDocumentEdited`).

- **Clean external modification:** When `isDocumentEdited == false`, preserves `presentationMode`, captures edit selection when editing, derives deterministic semantic heading/relative UTF-16 via `DocumentAnchor` / `DocumentOutlineParser.nearestHeading`, and uses native `revert(toContentsOf:ofType:)` (not a second model). On success `text` becomes external text, document stays clean, old Undo cleared, `NSTextView` updated without registering Undo (delegate suppressed, coalescing broken, selection clamped and restored once, no `replaceText` recursion). Renderer/outline/bookmarks re-resolve; reading mode reuses M7 `DocumentNavigationRequest` when anchor still valid, editing restores caret; mode never flipped merely due to reload. On failure including invalid UTF-8, old model retained, native error presented, no Undo/bookmark mutation.

- **Dirty external modification:** When `isDocumentEdited == true`, never replaces local `text`, never overwrites external file, preserves Undo/selection/mode/dirty, records only minimal per-document `hasPendingExternalConflict` state. Periodic recovery autosave may continue via `.autosaveElsewhereOperation` without touching real file. `File > Save` / close-with-Save stay on native `NSDocument` path for AppKit conflict warnings. `Save As` preserves external source and saves local to new destination. Native `File > Revert to Saved` requires confirmation, discards only after confirmation, reloads via `NSDocument`, clears Undo and pending conflict, preserves presentation/position where reasonable, guards against recursion from its own presenter activity. Undo returning a dirty document to clean schedules the clean reload without requiring another filesystem event (via `updateChangeCount`).

- **Save discrimination:** `save(to:ofType:for:completionHandler:)` is the only bookmark-binding discriminator (always calls `super`, captures pre-save `fileURL`, acts only after success). Handles every `SaveOperationType`: `.saveOperation` (no clone/rebind if already file-backed; if pre-save `nil` treat as first save and bind untitled session bookmarks), `.saveAsOperation` (source record preserved, destination gets current in-memory bookmarks, untitled binds session, bound only after success, never clones stale store over newer in-memory state), `.saveToOperation` (export/copy, `fileURL` unchanged, no bookmark mutation), `.autosaveElsewhereOperation` (recovery, `fileURL` unchanged, `isDocumentEdited` stays true, no bookmark/conflict mutation), `.autosaveInPlaceOperation` / `.autosaveAsOperation` unreachable but defensively no-ops, future unknown preserves AppKit with no side effects. Failed/cancelled saves produce no bookmark mutation.

- **Recovery/restoration:** Inherited `NSDocument` recovery; no custom database or second model. Named recovered document: contents may come from `autosavedContentsFileURL`, original `fileURL` remains, stays edited until Save/Revert, bookmarks stay with original identity. Untitled recovered: `fileURL == nil`, restored text dirty, first explicit save binds session bookmarks. Recovery URL never becomes bookmark identity; M8 never-saved untitled bookmarks not required to survive crash.

- **Rename/move:** Small adapter overriding `presentedItemDidMove(to:)` (calls `super`, lets `NSDocument` update `fileURL`, does not move file, does not rediscover by path, refreshes existing Foundation URL-bookmark record/`lastKnownPath` for new URL without replacing in-memory bookmarks, refreshes `renderingBaseURL`-observed presentation, preserves text/dirty/Undo/selection/mode, no path-based identity).

- **Deletion/unavailability:** Native `NSDocument`/`NSFilePresenter` accommodation; does not recreate deleted path, does not delete bookmark records on temporary unavailability, keeps in-memory contents, post-deletion edits may be recovery-autosaved elsewhere without recreating original, explicit Save/Revert/Save As/close use native warnings/errors.

- **NSTextView sync:** Programmatic external-reload updates disable Undo registration, suppress delegate feedback (`isSynchronizingText`), set `string` from `MarkdownDocument.text`, break coalescing, clear obsolete Undo after native revert, clamp selection to valid UTF-16, restore once, never recursively call `replaceText`, never mark dirty or create Undo entries, no second buffer.

- **Position preservation:** Reuses M5/M7 `DocumentAnchor` / `DocumentNavigationRequest` (`offset` UTF-16 + heading). When previous semantic target still resolves, reading reuses M7 navigation route, editing restores caret relative to resolved heading; ambiguous duplicate headings are not guessed (treated stale with safe clamp/fallback).

- **Multi-document isolation:** All M9 runtime state is instance-scoped (`pendingExternalChangeScheduled`, `hasPendingExternalConflict`, `isHandlingExternalReload`, anchors); no global external-change state; mutation of document A never affects B.

- **File menu:** Native `File > Revert to Saved` via `NSDocument.revertToSaved(_:)` responder-chain action; no custom sheet if AppKit provides native workflow. Existing Save/Save As/Close/Open/New/Undo/Redo/Command-E routing unchanged.

## Milestone 10: Visual/accessibility pass

Bounded polish/accessibility milestone that closes the documented current v1 roadmap. No architecture changes, no new document model, no History implementation, no feature work.

- **Window and pane layout:** Preserves initial 1100×700, NavigationSplitView + .inspector, native materials/dividers, per-window state, existing column width ranges. Changes tested minimum content size to 840×480 to accommodate sidebar 180 / center 420 / inspector 220. At minimum, medium, and large sizes all panes remain usable without unusable clipping; scrolling and inspector controls remain reachable. No custom split-view implementation.

- **Toolbar / titlebar:** Preserves unified native toolbar, visible document title, native dirty indication, existing identifiers, single AppKit Command-E route. Improves accessibility state: History control label toggles Show/Hide History Sidebar with value Shown/Hidden; Inspector control label toggles Show/Hide Inspector with value Shown/Hidden; Reading/Edit mode control uses action-oriented label and value Reading mode / Editing mode. No new toolbar items.

- **Reading view:** Keeps MarkdownUI 2.4.1 and renderer architecture. Centers rendered Markdown in readable column with maximum ~760 (accepted 720–800 only if 760 proven inappropriate), at least 24 horizontal and 16 vertical padding, full vertical scrolling, text selection, links, images, code blocks, tables, task lists, duplicate-heading navigation, baseURL, long-document behavior. Wide tables/code remain usable and not clipped by readable-width treatment. Accessibility: scroll region labeled Markdown document, preserves markdownReadingView identifier, reading mode is keyboard-scrollable focus target; Command-E into reading focuses markdownReadingView and arrow/Page Up/Page Down actually scroll. Replaces fixed RGB readingDivider/readingTertiary with semantic AppKit colors (separatorColor / secondaryLabelColor) so light/dark and Increased Contrast participate. No parallel Markdown accessibility renderer.

- **Native editor:** Keeps MarkdownTextEditorScrollView and retained NSTextView architecture. Improves readability using native macOS configuration only: native user/system fixed-pitch font, readable standard Mac text size, ~16 horizontal and ~14 vertical text-container inset. NSTextView accessibility label Markdown editor. Preserves plain text, selection, caret, Undo/Redo, find, spellcheck, text services, Cut/Copy/Paste, scrolling, delegate sync, M9 reload sync, dirty lifecycle. No SwiftUI TextEditor, no fixed centered column, no rich text, no custom Undo, no syntax highlighting.

- **History sidebar:** No History implementation. Preserves History title, honest No history yet empty state, width range, native material, scrolling. Adds nonduplicative region label History sidebar for VoiceOver. No recent-file database, history model, or timeline.

- **Inspector structure:** Fixes long-outline problem. Keeps width range, identifiers, On This Page, Bookmarks, outline/bookmark semantics. Uses two vertically arranged labeled regions: On This Page flexible height independently scrollable and takes remaining height; Bookmarks always discoverable below outline, independently scrollable with approximately min 120 ideal 160 max 220, so very long outline never pushes Bookmarks offscreen. Uses native SwiftUI layout/scrolling, no new inspector architecture.

- **Outline:** Preserves source order, indentation, duplicate occurrence semantics, two-line truncation, navigation route, bookmark toggles, stable identifiers. Rows remain actionable controls. VoiceOver labels remain useful including heading title, level, and duplicate occurrence where applicable (e.g., Installation, heading level 2, 1 of 2). Keyboard activation continues to work. No parser/model/navigation/resolution changes.

- **Bookmarks:** Preserves all M8 behavior (empty state, resolved/stale, add/remove, navigation, ordering, persistence, Save As, stale resolution, identifiers, no dirty changes, no Undo system). Bookmark toggles expose accessibility values Bookmarked / Not bookmarked (no empty value). Resolved bookmarks remain navigable/removable. Stale navigation remains disabled with accessibility unavailable, removal remains enabled, visually shows explicit semantic text Unavailable (plus system-native warning where trivial) — not opacity/color only. After removal focus moves deterministically to next bookmark, otherwise previous, otherwise Bookmarks heading or empty state, never leaving focus nowhere. Preserves No bookmarks yet. Removes duplicate accessibility identifier from noncanonical section-title child, keeping canonical container identifiers stable. No DocumentBookmark/resolver/store/schema/order/Undo changes.

- **Keyboard and focus:** Command-E entering edit focuses markdownTextEditor; entering reading focuses markdownReadingView with Page Up/Page Down and arrow scrolling. Reading-mode outline/bookmark navigation preserves focus on initiating control where practical; editing-mode outline/bookmark navigation focuses NSTextView at destination. Pane hiding moves focus to corresponding toolbar toggle or appropriate center content target, never stranding focus. With macOS Keyboard Navigation enabled, toolbar controls, outline rows, bookmark toggles, navigation, stale remove controls, and pane controls are keyboard reachable and operable. No new shortcuts.

- **VoiceOver / accessibility:** Accessibility identifiers alone are not sufficient. Adds useful nonduplicative semantics for Markdown reading region, editor, History sidebar, inspector, outline, and bookmarks. Controls expose appropriate roles/labels/values/state/enabled/disabled. Avoids meaningless duplicate announcements. Preserves MarkdownUI child accessibility. No duplicate parser-derived accessibility tree. Rendered Markdown links remain visibly links, are announced meaningfully, and are actionable through VoiceOver. No MarkdownUI replacement.

- **Appearance / contrast / motion:** Uses system semantic colors/materials. Verified light/dark, Increased Contrast, Differentiate Without Color where relevant. Stale/unavailable and bookmarked states not color-only, disabled states remain legible, editor and rendered Markdown remain readable. Keeps existing Reduce Motion handling, adds no gratuitous animation, no custom theme/settings/iOS Dynamic Type/text-size controls, normal native macOS typography.

- **Native document UI:** Does not customize or replace native Open/Save/Save As/Close-with-save/Revert/conflict dialogs/deletion/error sheets; preserves focus restoration after sheets. No change to ForksviewApp.swift except concrete M10 defect. Single AppKit Command-E route remains untouched. M9 external-change/autosave/conflict architecture remains native and unchanged; the bounded reload guard also compares loaded text with current file bytes so rapid writes cannot leave an intermediate version displayed.

No new production file or abstraction is justified. Expected modified files: MarkdownDocument.swift (minimum size plus bounded rapid-reload guard), DocumentShellView.swift (toolbar accessibility state + bounded focus coordination), DocumentRootView.swift (reading/editing first-responder transitions), MarkdownReadingView.swift (centered readable width, semantic colors, accessibility label, keyboard reading focus), MarkdownTextView.swift (native font, inset, accessibility label), DocumentInspectorPlaceholderView.swift (independent section scrolling, explicit stale state, bookmark control state, removal focus), HistorySidebarPlaceholderView.swift (only if needed for region semantics), docs/architecture.md (this record).

**M10 closes the documented current v1 roadmap.**

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
10. Visual/accessibility pass — closes current v1 roadmap

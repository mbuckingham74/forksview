import AppKit
import Combine
import SwiftUI

@MainActor
final class MarkdownDocument: NSDocument, ObservableObject {
    static let typeIdentifier = "net.daringfireball.markdown"

    @Published private(set) var text = ""
    @Published var presentationMode: DocumentPresentationMode = .reading
    @Published private(set) var bookmarks: [DocumentBookmark] = []
    @Published var externalReloadNavigationRequest: DocumentNavigationRequest?
    private weak var textEditor: (any MarkdownTextEditing)?
    // Test hook for error presentation verification
    var lastPresentedErrorForTesting: Error?

    // MARK: - Autosave policy (Milestone 9)
    nonisolated override class var autosavesInPlace: Bool { false }
    override class var autosavesDrafts: Bool { false }

    // MARK: - Bookmark Store

    // Test hook: allow injecting custom store factory for isolation tests.
    static var bookmarkStoreFactory: (() -> DocumentBookmarkStore)? = nil

    private var _bookmarkStore: DocumentBookmarkStore?
    var bookmarkStore: DocumentBookmarkStore {
        if let s = _bookmarkStore { return s }
        if let factory = Self.bookmarkStoreFactory {
            let s = factory()
            _bookmarkStore = s
            return s
        }
        let s = DocumentBookmarkStore()
        _bookmarkStore = s
        return s
    }

    func injectBookmarkStoreForTesting(_ store: DocumentBookmarkStore) {
        _bookmarkStore = store
        // Reload if file-backed
        loadBookmarksIfNeeded()
    }

    // MARK: - Position anchor (Milestone 5)
    // Transient window/document presentation state, not persisted.
    // Editing selection is stored as UTF-16 range to restore exactly via NSTextView.
    // Semantic heading is derived from offset for future outline use.
    var lastAnchor: DocumentAnchor?
    var pendingEditingSelection: NSRange?

    // MARK: - M9 External-change state (instance-scoped)
    private var pendingExternalChangeScheduled = false
    private var hasPendingExternalConflict = false
    private var isHandlingExternalReload = false
    private var lastHandledExternalFileModificationDate: Date?
    private var pendingExternalReloadAnchor: DocumentAnchor?
    private var pendingExternalReloadSelection: NSRange?

    override func makeWindowControllers() {
        // Ensure bookmarks loaded before UI shows
        loadBookmarksIfNeeded()
        markCurrentFileModificationDateAsHandled()
        let shellView = DocumentShellView(document: self)
        let hostingController = NSHostingController(rootView: shellView)
        let window = NSWindow(contentViewController: hostingController)
        window.setContentSize(NSSize(width: 1100, height: 700))
        window.contentMinSize = NSSize(width: 640, height: 480)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setAccessibilityIdentifier("documentWindow")
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        window.center()
        window.isReleasedWhenClosed = false
        let windowController = MarkdownDocumentWindowController(window: window)
        // Keep document-specific commands in the normal window responder chain.
        window.nextResponder = windowController
        addWindowController(windowController)
        DispatchQueue.main.async {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func loadBookmarksIfNeeded() {
        guard let url = fileURL else {
            // Untitled: keep session bookmarks (initially empty)
            return
        }
        let loaded = bookmarkStore.loadBookmarks(for: url)
        if loaded != bookmarks {
            bookmarks = loaded
        }
    }

    @objc func togglePresentationMode(_ sender: Any?) {
        if presentationMode == .editing {
            textEditor?.breakUndoCoalescing()
            captureEditingPosition()
        }
        presentationMode = (presentationMode == .reading) ? .editing : .reading
        if presentationMode == .reading {
            textEditor?.breakUndoCoalescing()
        }
    }

    @objc func enterReadingMode(_ sender: Any?) {
        if presentationMode == .editing {
            textEditor?.breakUndoCoalescing()
            captureEditingPosition()
        }
        presentationMode = .reading
        textEditor?.breakUndoCoalescing()
    }

    @objc func enterEditingMode(_ sender: Any?) {
        presentationMode = .editing
    }

    func captureEditingPosition() {
        guard let editor = textEditor else {
            // No editor attached — anchor from start
            lastAnchor = DocumentAnchor.anchor(for: 0, in: text)
            pendingEditingSelection = NSRange(location: 0, length: 0)
            return
        }
        let range = editor.selectedRange()
        let offset = range.location
        lastAnchor = DocumentAnchor.anchor(for: offset, in: text)
        pendingEditingSelection = range
    }

    func restoreEditingSelectionIfNeeded() -> NSRange? {
        pendingEditingSelection
    }

    nonisolated override func read(from data: Data, ofType typeName: String) throws {
        guard let decodedText = String(data: data, encoding: .utf8) else {
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: CocoaError.Code.fileReadInapplicableStringEncoding.rawValue,
                userInfo: [
                    NSLocalizedDescriptionKey: "The Markdown document could not be opened because it is not valid UTF-8.",
                    NSLocalizedFailureReasonErrorKey: "Forksview reads Markdown files using strict UTF-8 decoding."
                ]
            )
        }

        // NSDocument performs reads on the main thread unless a subclass opts in
        // to concurrent reading. Forksview intentionally keeps that default.
        MainActor.assumeIsolated {
            text = decodedText
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        textEditor?.breakUndoCoalescing()
        return Data(text.utf8)
    }

    func replaceText(with newText: String) {
        guard newText != text else {
            return
        }
        text = newText
    }

    func registerTextEditor(_ editor: any MarkdownTextEditing) {
        textEditor = editor
    }

    func unregisterTextEditor(_ editor: any MarkdownTextEditing) {
        guard textEditor === editor else {
            return
        }

        textEditor = nil
    }

    // MARK: - Bookmark APIs (Milestone 8)

    /// Add bookmark for given outline item. At most one bookmark per resolved heading. Does not affect dirty/undo.
    func addBookmark(for item: DocumentOutlineItem, in outline: [DocumentOutlineItem]) {
        // Prevent duplicate for same resolved heading
        if DocumentBookmarkResolver.isBookmarked(item: item, bookmarks: bookmarks, outline: outline) {
            return
        }
        // Keep bookmark operation separate from user's preceding typing group so subsequent undo does not coalesce.
        textEditor?.breakUndoCoalescing()
        let bm = DocumentBookmark.make(for: item, in: outline)
        bookmarks.append(bm)
        // Persist if file-backed, without marking dirty or undo
        if let url = fileURL {
            bookmarkStore.saveBookmarks(bookmarks, for: url)
        }
        textEditor?.breakUndoCoalescing()
    }

    func removeBookmark(id: UUID) {
        // Keep bookmark operation separate from typing group
        textEditor?.breakUndoCoalescing()
        guard let idx = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        bookmarks.remove(at: idx)
        if let url = fileURL {
            bookmarkStore.saveBookmarks(bookmarks, for: url)
        }
        textEditor?.breakUndoCoalescing()
    }

    func removeBookmark(for item: DocumentOutlineItem, in outline: [DocumentOutlineItem]) {
        guard let bm = DocumentBookmarkResolver.bookmark(for: item, in: bookmarks, outline: outline) else { return }
        removeBookmark(id: bm.id)
    }

    func toggleBookmark(for item: DocumentOutlineItem, in outline: [DocumentOutlineItem]) {
        if let existing = DocumentBookmarkResolver.bookmark(for: item, in: bookmarks, outline: outline) {
            removeBookmark(id: existing.id)
        } else {
            addBookmark(for: item, in: outline)
        }
    }

    func isBookmarked(_ item: DocumentOutlineItem, outline: [DocumentOutlineItem]) -> Bool {
        DocumentBookmarkResolver.isBookmarked(item: item, bookmarks: bookmarks, outline: outline)
    }

    // MARK: - Save Handling for Bookmarks (Milestone 9 discriminator)

    override func save(to url: URL, ofType typeName: String, for saveOperation: SaveOperationType, completionHandler: @escaping (Error?) -> Void) {
        let oldURL = fileURL
        super.save(to: url, ofType: typeName, for: saveOperation) { [weak self] error in
            guard let self = self else {
                completionHandler(error)
                return
            }
            Task { @MainActor in
                if error == nil {
                    self.markCurrentFileModificationDateAsHandled()
                    switch saveOperation {
                    case .saveOperation:
                        if oldURL == nil {
                            // First explicit save of untitled (via saveOperation): bind session bookmarks
                            self.bookmarkStore.saveBookmarks(self.bookmarks, for: url)
                        } else {
                            // Normal save to same file: no clone, just ensure no side effects
                            break
                        }
                    case .saveAsOperation:
                        if let old = oldURL {
                            // Clone source record to destination, then ensure current in-memory bookmarks win
                            self.bookmarkStore.handleSaveAs(from: old, to: url)
                            self.bookmarkStore.saveBookmarks(self.bookmarks, for: url)
                        } else {
                            // Untitled Save As (first save): persist session bookmarks
                            self.bookmarkStore.saveBookmarks(self.bookmarks, for: url)
                        }
                    case .saveToOperation:
                        // Export/copy: no bookmark mutation, fileURL unchanged
                        break
                    case .autosaveElsewhereOperation:
                        // Recovery autosave: no bookmark mutation, fileURL unchanged, do not touch conflict identity
                        break
                    case .autosaveInPlaceOperation:
                        // Unreachable under policy: no side effects
                        break
                    case .autosaveAsOperation:
                        // Unreachable because autosavesDrafts false: no side effects
                        break
                    @unknown default:
                        break
                    }
                    if oldURL != self.fileURL {
                        // fileURL is NS_SWIFT_NONISOLATED and is not observable through
                        // ObservableObject. Refresh views that derive relative resources
                        // from the document's current location.
                        self.objectWillChange.send()
                    }
                }
                completionHandler(error)
            }
        }
    }

    // MARK: - NSDocument change count handling for M9

    override func updateChangeCount(_ change: NSDocument.ChangeType) {
        super.updateChangeCount(change)
        // If undo returned a dirty document with pending external change back to clean, schedule reload
        if hasPendingExternalConflict && !isDocumentEdited && !isHandlingExternalReload {
            hasPendingExternalConflict = false
            scheduleExternalChangeHandling()
        }
    }

    // MARK: - External change detection (Milestone 9)

    nonisolated override func presentedItemDidChange() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            // NSDocument's presenter bookkeeping and the state decision both run
            // on the document actor, while this callback remains lightweight.
            if self.isDocumentEdited {
                self.hasPendingExternalConflict = true
            }
            self.invokeSuperPresentedItemDidChange()
            if self.isDocumentEdited {
                // Recheck after native bookkeeping in case it changed the count.
                self.hasPendingExternalConflict = true
                return
            }
            guard self.currentPresentedFileModificationDate() != self.lastHandledExternalFileModificationDate else {
                return
            }
            self.scheduleExternalChangeHandling()
        }
    }

    nonisolated override func presentedItemDidMove(to newURL: URL) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            // NSDocument owns the fileURL transition. Invoke its native move
            // implementation on the document actor before the small bookmark
            // and rendering adapters below.
            self.invokeSuperPresentedItemDidMove(to: newURL)
            // NSDocument has already adopted newURL. Refresh only the existing
            // Foundation URL-bookmark record; never replace the live collection.
            if !self.bookmarks.isEmpty || self.bookmarkStore.containsRecord(for: newURL) {
                self.bookmarkStore.saveBookmarks(self.bookmarks, for: newURL)
            }
            self.markCurrentFileModificationDateAsHandled()
            self.objectWillChange.send()
        }
    }

    private func invokeSuperPresentedItemDidChange() {
        super.presentedItemDidChange()
    }

    private func invokeSuperPresentedItemDidMove(to newURL: URL) {
        super.presentedItemDidMove(to: newURL)
    }

    private func markCurrentFileModificationDateAsHandled() {
        lastHandledExternalFileModificationDate = currentPresentedFileModificationDate()
    }

    private func currentPresentedFileModificationDate() -> Date? {
        guard let fileURL else {
            return fileModificationDate
        }
        return (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate]) as? Date
            ?? fileModificationDate
    }

    nonisolated override func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) {
        // Acknowledge the native deletion immediately so NSDocument does not close
        // the document. The presenter callback itself must not wait on MainActor.
        completionHandler(nil)
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            // The default NSDocument implementation closes the document. M9 keeps
            // the document open and retains its in-memory source instead.
            self.hasPendingExternalConflict = self.isDocumentEdited
        }
    }

    private func scheduleExternalChangeHandling() {
        if isHandlingExternalReload { return }
        if pendingExternalChangeScheduled { return }
        pendingExternalChangeScheduled = true
        Task { @MainActor [weak self] in
            // Coalesce: yield to runloop to allow duplicates to collapse
            // Use async to coalesce rapid external writes
            await Task.yield()
            guard let self else { return }
            self.pendingExternalChangeScheduled = false
            // Guard against untitled, a presenter callback produced by our own
            // revert, or a deleted/unavailable file.
            guard !self.isHandlingExternalReload else { return }
            guard let fileURL = self.fileURL else { return }
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
            // Re-check dirty state immediately before deciding
            if self.isDocumentEdited {
                // Dirty: record pending conflict, preserve local state, do not reload
                self.hasPendingExternalConflict = true
                return
            } else {
                guard self.currentPresentedFileModificationDate() != self.lastHandledExternalFileModificationDate else {
                    return
                }
                // Clean: perform external reload
                self.hasPendingExternalConflict = false
                await self.performCleanExternalReload(from: fileURL)
            }
        }
    }

    private func performCleanExternalReload(from fileURL: URL) async {
        // Preserve presentationMode and capture selection/anchor
        let preservedMode = presentationMode
        let oldOutline = DocumentOutlineParser.outline(from: text)
        var capturedAnchor: DocumentAnchor?
        var capturedSelection: NSRange?

        if presentationMode == .editing, let editor = textEditor {
            let sel = editor.selectedRange()
            capturedSelection = sel
            capturedAnchor = DocumentAnchor.anchor(for: sel.location, in: text)
        } else if let anchor = lastAnchor {
            capturedAnchor = anchor
            // For reading mode, selection not relevant, but keep anchor
        } else {
            // Fallback: derive anchor from start
            capturedAnchor = DocumentAnchor.anchor(for: 0, in: text)
        }
        let capturedRelativeOffset: Int? = {
            guard let anchor = capturedAnchor,
                  let heading = anchor.heading,
                  let level = anchor.level,
                  let oldHeading = DocumentOutlineParser.nearestHeading(for: anchor.offset, in: oldOutline),
                  oldHeading.title == heading,
                  oldHeading.level == level else {
                return nil
            }
            return max(0, anchor.offset - oldHeading.sourceRange.location)
        }()

        // Also capture heading-relative position for fallback: we already have anchor
        pendingExternalReloadAnchor = capturedAnchor
        pendingExternalReloadSelection = capturedSelection

        let typeName = fileType ?? Self.typeIdentifier
        isHandlingExternalReload = true
        defer { isHandlingExternalReload = false }

        // Use native revert toContentsOf:ofType:
        // Use completionHandler variant to handle success/failure without blocking
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            // NSDocument revert has a synchronous throws version and async completionHandler version
            // We use the async one via revert(toContentsOf:ofType:completionHandler:) if available
            // Fallback to synchronous in Task: try revert(toContentsOf:ofType:)
            // Need to handle invalid UTF-8 error path
            self.revertWithCompletion(to: fileURL, ofType: typeName) { [weak self] error in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                Task { @MainActor in
                    if let error = error {
                        // Failed: retain old model, present native document error, do not mutate undo/bookmarks
                        _ = self.presentError(error)
                        continuation.resume()
                        return
                    }
                    self.markCurrentFileModificationDateAsHandled()
                    // Success: text already updated via read(from:ofType:), document remains clean, old undo cleared
                    // Clear obsolete undo history
                    self.undoManager?.removeAllActions()
                    // Synchronize the retained native editor before restoring its
                    // selection. The coordinator suppresses delegate feedback and
                    // disables NSTextView undo registration for this replacement.
                    self.textEditor?.synchronizeTextView(with: self.text)
                    // Break coalescing appropriately
                    self.textEditor?.breakUndoCoalescing()
                    // Clamp and restore selection exactly once
                    let newLength = (self.text as NSString).length
                    var targetSelection: NSRange?
                    var navigationRequestToPublish: DocumentNavigationRequest?

                    // Determine outline after reload for semantic resolution
                    let newOutline = DocumentOutlineParser.outline(from: self.text)

                    // Resolve captured anchor against new outline
                    if let anchor = self.pendingExternalReloadAnchor {
                        // Try exact offset + title match, then fallback via resolver-like logic
                        // Use DocumentAnchor resolution: find nearest heading for offset, then check if heading still exists
                        if let heading = anchor.heading, let level = anchor.level {
                            // Find matching heading in new outline with same level+title that preserves occurrence semantics
                            let matching = newOutline.filter { $0.level == level && $0.title == heading }
                            if !matching.isEmpty {
                                // Check if captured heading still valid (old count == new count ? deterministic)
                                // For simplicity, if exact previous heading title exists, use its location
                                // Find exact item that corresponds to anchor.heading
                                // Prefer exact previous source offset title match if still at same offset, else fallback to occurrence
                                let exact = newOutline.first(where: { $0.title == heading && $0.level == level && $0.sourceRange.location == anchor.offset })
                                let resolvedItem: DocumentOutlineItem?
                                if let exact = exact {
                                    resolvedItem = exact
                                } else {
                                    // Use occurrence derived from anchor? We stored sourceOffsetAtCreation only, but anchor alone doesn't have occurrence.
                                    // For M9, we can attempt deterministic: if matching count == 1, pick it; otherwise if anchor offset falls within heading block, pick nearest
                                    // Simpler: pick nearest heading by offset if multiple, but spec says do not guess across ambiguous duplicates.
                                    // So if matching.count == 1, use it; otherwise stale -> fallback to clamped offset.
                                    if matching.count == 1 {
                                        resolvedItem = matching.first
                                    } else {
                                        // Ambiguous duplicate: treat as stale, do not guess
                                        resolvedItem = nil
                                    }
                                }
                                if let item = resolvedItem {
                                    if preservedMode == .editing {
                                        let offset = item.sourceRange.location + (capturedRelativeOffset ?? 0)
                                        let clampedLoc = max(0, min(offset, newLength))
                                        let clampedLen = max(0, min(capturedSelection?.length ?? 0, newLength - clampedLoc))
                                        targetSelection = NSRange(location: clampedLoc, length: clampedLen)
                                    } else {
                                        // Reading mode: reuse M7 navigation route
                                        let readingAnchor = DocumentAnchor(from: item)
                                        navigationRequestToPublish = DocumentNavigationRequest(anchor: readingAnchor)
                                    }
                                } else {
                                    // Fallback to clamped relative offset
                                    if let sel = capturedSelection, preservedMode == .editing {
                                        let clampedLoc = max(0, min(sel.location, newLength))
                                        let clampedLen = max(0, min(sel.length, newLength - clampedLoc))
                                        targetSelection = NSRange(location: clampedLoc, length: clampedLen)
                                    } else if preservedMode == .editing {
                                        let clamped = max(0, min(anchor.offset, newLength))
                                        targetSelection = NSRange(location: clamped, length: 0)
                                    }
                                }
                            } else {
                                // Heading no longer exists -> fallback
                                if let sel = capturedSelection, preservedMode == .editing {
                                    let clampedLoc = max(0, min(sel.location, newLength))
                                    let clampedLen = max(0, min(sel.length, newLength - clampedLoc))
                                    targetSelection = NSRange(location: clampedLoc, length: clampedLen)
                                } else if preservedMode == .editing {
                                    let clamped = max(0, min(anchor.offset, newLength))
                                    targetSelection = NSRange(location: clamped, length: 0)
                                }
                            }
                        } else {
                            // No heading anchor (plain offset): restore offset clamped
                            if let sel = capturedSelection, preservedMode == .editing {
                                let clampedLoc = max(0, min(sel.location, newLength))
                                let clampedLen = max(0, min(sel.length, newLength - clampedLoc))
                                targetSelection = NSRange(location: clampedLoc, length: clampedLen)
                            } else if preservedMode == .editing {
                                let clamped = max(0, min(anchor.offset, newLength))
                                targetSelection = NSRange(location: clamped, length: 0)
                            }
                        }
                    } else if let sel = capturedSelection, preservedMode == .editing {
                        let clampedLoc = max(0, min(sel.location, newLength))
                        let clampedLen = max(0, min(sel.length, newLength - clampedLoc))
                        targetSelection = NSRange(location: clampedLoc, length: clampedLen)
                    }

                    // Ensure presentationMode unchanged
                    self.presentationMode = preservedMode

                    // Update pending editing selection for text view
                    if let target = targetSelection {
                        self.pendingEditingSelection = target
                        // Restore via textEditor
                        self.textEditor?.breakUndoCoalescing()
                        self.textEditor?.restoreExternalSelection(target)
                        self.textEditor?.breakUndoCoalescing()
                    } else if let nav = navigationRequestToPublish {
                        // Reading mode navigation via M7 route
                        self.externalReloadNavigationRequest = nav
                        // Also update lastAnchor to new heading location
                        self.lastAnchor = nav.anchor
                    } else {
                        // No specific navigation, but ensure editor break coalescing
                        self.textEditor?.breakUndoCoalescing()
                    }

                    // Ensure document remains clean after revert (revert should have cleared dirty)
                    // NSDocument's revert will update change count; ensure hasUnautosavedChanges becomes false (native)
                    // Break undo coalescing again
                    self.textEditor?.breakUndoCoalescing()

                    // Renderer/outline/bookmark updates happen via @Published text change
                    // Stale bookmarks remain stale per resolver

                    self.pendingExternalReloadAnchor = nil
                    self.pendingExternalReloadSelection = nil

                    continuation.resume()
                }
            }
        }
    }

    private func revertWithCompletion(to url: URL, ofType typeName: String, completionHandler: @escaping (Error?) -> Void) {
        do {
            try self.revert(toContentsOf: url, ofType: typeName)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }

    nonisolated override func revert(toContentsOf url: URL, ofType typeName: String) throws {
        // Call super on MainActor? NSDocument's revert is expected on main
        try MainActor.assumeIsolated {
            // Temporarily set handling flag to avoid recursion in presentedItemDidChange
            let prev = self.isHandlingExternalReload
            self.isHandlingExternalReload = true
            defer { self.isHandlingExternalReload = prev }
            try super.revert(toContentsOf: url, ofType: typeName)
            self.markCurrentFileModificationDateAsHandled()
            // After successful revert: clear undo, clear pending conflict, preserve presentationMode
            self.undoManager?.removeAllActions()
            self.hasPendingExternalConflict = false
            self.pendingExternalChangeScheduled = false
            // Selection/position preservation for revertToSaved will be handled by caller (performed via menu)
            // For external clean reload, the async helper already handles selection
            // For explicit revert, we should preserve approximate position similarly but discard local edits
            // Capture and restore is done by the caller of revertToSaved? Instead handle here minimally:
            // Break coalescing
            self.textEditor?.breakUndoCoalescing()
        }
    }

    // MARK: - Rendering support (Milestone 4)
    // Ordinary document information only. Renderer-specific loading stays in MarkdownReadingView.

    /// Directory containing the document on disk, used as `baseURL` for relative image resolution.
    /// Returns `nil` for untitled documents without a file URL.
    var renderingBaseURL: URL? {
        fileURL?.deletingLastPathComponent()
    }

    // MARK: - Conflict state helpers for tests

    func hasPendingConflictForTesting() -> Bool {
        hasPendingExternalConflict
    }

    func pendingExternalReloadAnchorForTesting() -> DocumentAnchor? {
        pendingExternalReloadAnchor
    }

    override func presentError(_ error: Error) -> Bool {
        lastPresentedErrorForTesting = error
        // In unit-test harness without UI windows, avoid blocking modal presentation that would hang the test
        let isUITestHost = ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if isUITestHost && windowControllers.isEmpty {
            // No window to present in unit test: record and don't block
            return true
        }
        // For UI tests the app process has windows; allow native presentation
        // Also check if app has no windows yet (early launch) - don't block
        if windowControllers.isEmpty && NSApp.windows.isEmpty {
            return true
        }
        return super.presentError(error)
    }
}

@MainActor
final class MarkdownDocumentWindowController: NSWindowController, NSMenuItemValidation, NSUserInterfaceValidations {
    @objc func togglePresentationMode(_ sender: Any?) {
        (document as? MarkdownDocument)?.togglePresentationMode(sender)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(togglePresentationMode(_:)) {
            return document is MarkdownDocument
        }
        return true
    }

    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(togglePresentationMode(_:)) {
            return document is MarkdownDocument
        }
        return true
    }
}

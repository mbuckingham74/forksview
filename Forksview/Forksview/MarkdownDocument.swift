import AppKit
import Combine
import SwiftUI

@MainActor
final class MarkdownDocument: NSDocument, ObservableObject {
    static let typeIdentifier = "net.daringfireball.markdown"

    @Published private(set) var text = ""
    @Published var presentationMode: DocumentPresentationMode = .reading
    @Published private(set) var bookmarks: [DocumentBookmark] = []
    private weak var textEditor: (any MarkdownTextEditing)?

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

    // Track fileURL changes for bookmark binding
    private var observedFileURL: URL?
    private var isHandlingSave = false

    override func makeWindowControllers() {
        // Ensure bookmarks loaded before UI shows
        loadBookmarksIfNeeded()
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

    // Override fileURL to observe changes for bookmark binding
    // NSDocument.fileURL is NS_SWIFT_NONISOLATED, so override must be nonisolated.
    nonisolated override var fileURL: URL? {
        didSet {
            if oldValue != fileURL {
                let old = oldValue
                let new = fileURL
                Task { @MainActor [weak self] in
                    self?.handleFileURLChange(from: old, to: new)
                }
            }
        }
    }

    private func handleFileURLChange(from old: URL?, to new: URL?) {
        // Avoid handling during save handling where we manage explicitly
        if isHandlingSave { return }
        if old == nil, let newURL = new {
            // First save of untitled: persist current session bookmarks, or load if empty
            if !bookmarks.isEmpty {
                bookmarkStore.saveBookmarks(bookmarks, for: newURL)
            } else {
                let loaded = bookmarkStore.loadBookmarks(for: newURL)
                if loaded != bookmarks {
                    bookmarks = loaded
                }
            }
            observedFileURL = newURL
        } else if let newURL = new {
            // Regular file URL change (open, or Save As completed elsewhere)
            let loaded = bookmarkStore.loadBookmarks(for: newURL)
            if loaded != bookmarks {
                bookmarks = loaded
            }
            observedFileURL = newURL
        } else {
            // Became untitled (should not happen after save, but handle)
            observedFileURL = nil
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
        observedFileURL = url
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

    // MARK: - Save Handling for Bookmarks

    override func save(to url: URL, ofType typeName: String, for saveOperation: SaveOperationType, completionHandler: @escaping (Error?) -> Void) {
        let oldURL = fileURL
        isHandlingSave = true
        super.save(to: url, ofType: typeName, for: saveOperation) { [weak self] error in
            guard let self = self else {
                completionHandler(error)
                return
            }
            Task { @MainActor in
                defer { self.isHandlingSave = false }
                if error == nil {
                    switch saveOperation {
                    case .saveAsOperation:
                        if let old = oldURL {
                            // Clone source to destination
                            self.bookmarkStore.handleSaveAs(from: old, to: url)
                            // Also ensure current in-memory bookmarks are saved to destination (if they differ from source record)
                            self.bookmarkStore.saveBookmarks(self.bookmarks, for: url)
                        } else {
                            // Untitled Save As (first save): persist session bookmarks
                            self.bookmarkStore.saveBookmarks(self.bookmarks, for: url)
                        }
                        // Reload to bind to destination
                        let loaded = self.bookmarkStore.loadBookmarks(for: url)
                        // If we just saved, loaded should equal bookmarks, but ensure binding
                        if loaded != self.bookmarks {
                            // If store's clone was source's saved bookmarks, but current session had extra unsaved bookmarks, we already saved above, so keep current
                            // Only update if loaded differs and we didn't just save current
                        }
                        self.observedFileURL = url
                    case .saveOperation:
                        if oldURL == nil {
                            // First save of untitled via saveOperation (not saveAs) — treat same as saveAs
                            self.bookmarkStore.saveBookmarks(self.bookmarks, for: url)
                            self.observedFileURL = url
                        } else {
                            // Regular save: fileURL same, ensure bookmarks persisted? Already persisted on change, but refresh lastKnownPath if needed
                            if self.fileURL != nil {
                                // Ensure store has correct path (for rename via save)
                            }
                        }
                    default:
                        break
                    }
                }
                completionHandler(error)
            }
        }
    }

    // MARK: - Rendering support (Milestone 4)
    // Ordinary document information only. Renderer-specific loading stays in MarkdownReadingView.

    /// Directory containing the document on disk, used as `baseURL` for relative image resolution.
    /// Returns `nil` for untitled documents without a file URL.
    var renderingBaseURL: URL? {
        fileURL?.deletingLastPathComponent()
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

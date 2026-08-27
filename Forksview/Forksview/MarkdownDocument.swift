import AppKit
import Combine
import SwiftUI

@MainActor
final class MarkdownDocument: NSDocument, ObservableObject {
    static let typeIdentifier = "net.daringfireball.markdown"

    @Published private(set) var text = ""
    @Published var presentationMode: DocumentPresentationMode = .reading
    private weak var textEditor: (any MarkdownTextEditing)?

    // MARK: - Position anchor (Milestone 5)
    // Transient window/document presentation state, not persisted.
    // Editing selection is stored as UTF-16 range to restore exactly via NSTextView.
    // Semantic heading is derived from offset for future outline use.
    var lastAnchor: DocumentAnchor?
    var pendingEditingSelection: NSRange?

    override func makeWindowControllers() {
        let rootView = DocumentRootView(document: self)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.setContentSize(NSSize(width: 860, height: 640))
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

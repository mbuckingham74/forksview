import AppKit
import Combine
import SwiftUI

@MainActor
final class MarkdownDocument: NSDocument, ObservableObject {
    static let typeIdentifier = "net.daringfireball.markdown"

    @Published private(set) var text = ""
    private weak var textEditor: (any MarkdownTextEditing)?

    override func makeWindowControllers() {
        let editor = MarkdownTextView(document: self)
        let hostingController = NSHostingController(rootView: editor)
        let window = NSWindow(contentViewController: hostingController)
        window.setContentSize(NSSize(width: 720, height: 520))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]

        addWindowController(NSWindowController(window: window))
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

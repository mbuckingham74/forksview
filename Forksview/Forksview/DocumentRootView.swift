import SwiftUI
import AppKit

/// Milestone 5+7+10: Single source-of-truth container that toggles between
/// MarkdownReadingView (rendered) and MarkdownTextView (native NSTextView).
/// Owns no second copy of text — both branches observe `document.text`.
/// Mode is window/document presentation state, default reading.
///
/// Position preservation (M7 improved):
/// - Editing -> Reading uses real outline parser for nearest heading anchor,
///   then reading scrolls to rendered heading occurrence.
/// - Reading -> Editing restores pendingEditingSelection via NSTextView.
/// - Outline navigation is handled via transient navigationRequest that
///   routes to reading (scroll) or editing (caret) without mode switch.
/// Lifecycle: native editor retained across switches via opacity.
/// M10: Command-E reading transition focuses markdownReadingView for keyboard scrolling.
@MainActor
struct DocumentRootView: View {
    @ObservedObject var document: MarkdownDocument
    var outline: [DocumentOutlineItem] = []
    @Binding var navigationRequest: DocumentNavigationRequest?

    // Legacy init for existing call sites without outline/navigation
    init(document: MarkdownDocument) {
        self.document = document
        self.outline = DocumentOutlineParser.outline(from: document.text)
        self._navigationRequest = .constant(nil)
    }

    init(document: MarkdownDocument, outline: [DocumentOutlineItem], navigationRequest: Binding<DocumentNavigationRequest?>) {
        self.document = document
        self.outline = outline
        self._navigationRequest = navigationRequest
    }

    var body: some View {
        ZStack {
            // Native editor always exists — hidden in reading mode.
            MarkdownTextView(document: document, outline: outline, navigationRequest: $navigationRequest)
                .opacity(document.presentationMode == .editing ? 1 : 0)
                .allowsHitTesting(document.presentationMode == .editing)
                .accessibilityHidden(document.presentationMode == .reading)

            // Reading view always exists — hidden in editing mode.
            MarkdownReadingView(markdown: document.text, baseURL: document.renderingBaseURL, isActive: document.presentationMode == .reading, outline: outline, navigationRequest: $navigationRequest)
                .opacity(document.presentationMode == .reading ? 1 : 0)
                .allowsHitTesting(document.presentationMode == .reading)
                .accessibilityHidden(document.presentationMode == .editing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: document.presentationMode) { _, newMode in
            if newMode == .editing {
                DispatchQueue.main.async {
                    focusTextView()
                }
            }
        }
    }

    private func focusTextView() {
        let window = document.windowControllers.first?.window ?? NSApp.keyWindow
        guard let window else { return }
        if let textView = findTextView(in: window) {
            if window.firstResponder !== textView {
                window.makeFirstResponder(textView)
            }
        } else if let keyWindow = NSApp.keyWindow, keyWindow !== window,
                  let tv = findTextView(in: keyWindow) {
            keyWindow.makeFirstResponder(tv)
        }
    }

    private func findTextView(in window: NSWindow) -> NSTextView? {
        guard let contentView = window.contentView else { return nil }
        return findTextView(in: contentView)
    }

    private func findTextView(in view: NSView) -> NSTextView? {
        if let tv = view as? NSTextView, tv.accessibilityIdentifier() == "markdownTextEditor" {
            return tv
        }
        if let scroll = view as? NSScrollView, let docView = scroll.documentView as? NSTextView {
            if docView.accessibilityIdentifier() == "markdownTextEditor" {
                return docView
            }
        }
        for sub in view.subviews {
            if let found = findTextView(in: sub) {
                return found
            }
        }
        return nil
    }

}

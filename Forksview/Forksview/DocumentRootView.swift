import SwiftUI
import AppKit

/// Milestone 5: Single source-of-truth container that toggles between
/// MarkdownReadingView (rendered) and MarkdownTextView (native NSTextView).
/// Owns no second copy of text — both branches observe `document.text`.
/// Mode is window/document presentation state, default reading.
///
/// Position preservation (M5 minimal):
/// - Editing -> Reading captures source offset + nearest heading as DocumentAnchor
///   stored transiently on MarkdownDocument (semantic over pixels).
/// - Reading -> Editing restores pendingEditingSelection via NSTextView.
/// - Reading scroll precise heading-scroll is deferred to M7 outline infrastructure;
///   current reading ScrollView remains at top on toggle, but editing cursor is preserved.
///   This is the smallest safe transitional behavior documented per spec.
///
/// Lifecycle fix (M5 remediation):
/// The native editor is retained across presentation switches. Instead of destroying/
/// recreating the NSTextView via conditional branches, both views always exist and
/// visibility/interactivity is controlled via opacity/hitTesting/accessibility.
/// This preserves native NSTextView undo registrations (which target the specific
/// textStorage) and selection, while keeping single source of truth on document.text.
@MainActor
struct DocumentRootView: View {
    @ObservedObject var document: MarkdownDocument

    var body: some View {
        ZStack {
            // Native editor always exists — hidden in reading mode.
            // Persistent instance preserves undo history and selection across mode switches.
            MarkdownTextView(document: document)
                .opacity(document.presentationMode == .editing ? 1 : 0)
                .allowsHitTesting(document.presentationMode == .editing)
                .accessibilityHidden(document.presentationMode == .reading)

            // Reading view always exists — hidden in editing mode.
            MarkdownReadingView(markdown: document.text, baseURL: document.renderingBaseURL)
                .opacity(document.presentationMode == .reading ? 1 : 0)
                .allowsHitTesting(document.presentationMode == .reading)
                .accessibilityHidden(document.presentationMode == .editing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: document.presentationMode) { _, newMode in
            if newMode == .reading {
                // Relinquish first responder when entering reading
                let window = document.windowControllers.first?.window ?? NSApp.keyWindow
                if let window, window.firstResponder is NSTextView {
                    window.makeFirstResponder(nil)
                } else {
                    NSApp.keyWindow?.makeFirstResponder(nil)
                }
            } else {
                // Return focus to editor when entering editing — deferred to next runloop
                // so the editor is hittable and window is key.
                DispatchQueue.main.async {
                    // Prefer document's window; fallback to keyWindow
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
            }
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

import AppKit
import SwiftUI

@MainActor
protocol MarkdownTextEditing: AnyObject {
    func breakUndoCoalescing()
    func selectedRange() -> NSRange
    func synchronizeTextView(with text: String)
    func handleNavigation(_ request: DocumentNavigationRequest, outline: [DocumentOutlineItem])
    func restoreExternalSelection(_ range: NSRange)
}

@MainActor
struct MarkdownTextView: NSViewRepresentable {
    @ObservedObject var document: MarkdownDocument
    var outline: [DocumentOutlineItem] = []
    @Binding var navigationRequest: DocumentNavigationRequest?

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

    func makeCoordinator() -> Coordinator {
        Coordinator(document: document)
    }

    func makeNSView(context: Context) -> MarkdownTextEditorScrollView {
        let scrollView = MarkdownTextEditorScrollView()
        context.coordinator.connect(to: scrollView.textView)
        let undoManager = scrollView.textView.undoManager
        undoManager?.disableUndoRegistration()
        if scrollView.textView.string != document.text {
            scrollView.textView.string = document.text
        }
        undoManager?.enableUndoRegistration()
        return scrollView
    }

    func updateNSView(_ scrollView: MarkdownTextEditorScrollView, context: Context) {
        context.coordinator.synchronizeTextView(with: document.text)
        // Update coordinator's outline and document reference for navigation handling
        context.coordinator.outline = outline
        context.coordinator.document = document
        if let req = navigationRequest, document.presentationMode == .editing {
            // Stale check: if anchor no longer exists, ignore
            if !OutlineRenderedResolver.isStale(request: req, outline: outline) {
                context.coordinator.handleNavigation(req, outline: outline)
            }
        }
    }

    static func dismantleNSView(
        _ scrollView: MarkdownTextEditorScrollView,
        coordinator: Coordinator
    ) {
        coordinator.disconnect()
    }

    final class Coordinator: NSObject, MarkdownTextEditing, NSTextViewDelegate {
        weak var document: MarkdownDocument?
        weak var textView: NSTextView?
        var outline: [DocumentOutlineItem] = []
        private var isSynchronizingText = false
        private var lastHandledNavigationToken: UUID?

        init(document: MarkdownDocument) {
            self.document = document
        }

        func connect(to textView: NSTextView) {
            self.textView = textView
            textView.delegate = self
            document?.registerTextEditor(self)
            if let pending = document?.pendingEditingSelection {
                let maxLoc = (textView.string as NSString).length
                let clampedLoc = min(pending.location, maxLoc)
                let clampedLen = min(pending.length, max(0, maxLoc - clampedLoc))
                let clamped = NSRange(location: clampedLoc, length: clampedLen)
                textView.setSelectedRange(clamped)
                textView.scrollRangeToVisible(clamped)
            }
        }

        func disconnect() {
            if textView?.delegate === self {
                textView?.delegate = nil
            }
            document?.unregisterTextEditor(self)
            textView = nil
        }

        func synchronizeTextView(with text: String) {
            guard let textView, textView.string != text else {
                return
            }
            isSynchronizingText = true
            let undoManager = textView.undoManager
            // Break coalescing before programmatic replacement per M9
            textView.breakUndoCoalescing()
            undoManager?.disableUndoRegistration()
            defer {
                undoManager?.enableUndoRegistration()
                textView.breakUndoCoalescing()
                isSynchronizingText = false
            }
            textView.string = text
        }

        func restoreExternalSelection(_ range: NSRange) {
            guard let textView else { return }
            let maxLen = (textView.string as NSString).length
            let clampedLoc = max(0, min(range.location, maxLen))
            let clampedLen = max(0, min(range.length, maxLen - clampedLoc))
            let clamped = NSRange(location: clampedLoc, length: clampedLen)
            isSynchronizingText = true
            let um = textView.undoManager
            um?.disableUndoRegistration()
            textView.breakUndoCoalescing()
            defer {
                um?.enableUndoRegistration()
                textView.breakUndoCoalescing()
                isSynchronizingText = false
            }
            textView.setSelectedRange(clamped)
            textView.scrollRangeToVisible(clamped)
            // Ensure first responder remains textView if in editing mode
            if let window = textView.window, window.firstResponder !== textView {
                window.makeFirstResponder(textView)
            }
        }

        func handleNavigation(_ request: DocumentNavigationRequest, outline: [DocumentOutlineItem]) {
            guard let textView, let document else { return }
            // Only handle when editing mode is active; caller already checks, but double-check
            guard document.presentationMode == .editing else { return }
            // Navigation requests are transient events. Do not replay the same event when
            // document.text changes and SwiftUI calls updateNSView again during typing.
            guard request.token != lastHandledNavigationToken else { return }
            // Stale check
            if OutlineRenderedResolver.isStale(request: request, outline: outline) { return }
            // Resolve outline item from anchor offset
            guard let item = outline.first(where: { $0.sourceRange.location == request.anchor.offset }) else { return }
            let targetRange = item.sourceRange
            let maxLen = (textView.string as NSString).length
            // Clamp location and length
            let clampedLoc = max(0, min(targetRange.location, maxLen))
            let clampedLen = 0 // zero-length caret at heading start per spec
            let caret = NSRange(location: clampedLoc, length: clampedLen)
            // Keep navigation separate from the user's preceding typing group so a
            // subsequent native undo removes only edits made after navigation.
            textView.breakUndoCoalescing()
            // Ensure we don't register undo or dirty: selection change doesn't affect undo.
            // Use undoManager disable just in case scroll or selection triggers anything
            let um = textView.undoManager
            um?.disableUndoRegistration()
            textView.setSelectedRange(caret)
            textView.scrollRangeToVisible(caret)
            um?.enableUndoRegistration()
            // Restore first responder to native NSTextView
            if let window = textView.window {
                if window.firstResponder !== textView {
                    window.makeFirstResponder(textView)
                }
            } else if let window = document.windowControllers.first?.window {
                window.makeFirstResponder(textView)
            }
            lastHandledNavigationToken = request.token
            // Do not update change count or register undo; caret move is presentation only.
        }

        func textDidChange(_ notification: Notification) {
            guard !isSynchronizingText, let textView, let document else {
                return
            }
            let newText = textView.string
            guard newText != document.text else { return }
            document.replaceText(with: newText)
        }

        func breakUndoCoalescing() {
            textView?.breakUndoCoalescing()
        }

        func selectedRange() -> NSRange {
            textView?.selectedRange() ?? NSRange(location: 0, length: 0)
        }

        func undoManager(for view: NSTextView) -> UndoManager? {
            document?.undoManager
        }
    }
}

@MainActor
final class MarkdownTextEditorScrollView: NSScrollView {
    let textView: NSTextView

    init() {
        textView = NSTextView(frame: .zero)
        super.init(frame: .zero)

        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true
        documentView = textView

        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true

        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        // M10 readability: native fixed-pitch, readable size, insets via native config only
        if let fixed = NSFont.userFixedPitchFont(ofSize: NSFont.systemFontSize) {
            textView.font = fixed
        } else {
            textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        }
        textView.textContainerInset = NSSize(width: 16, height: 14)
        textView.setAccessibilityIdentifier("markdownTextEditor")
        textView.setAccessibilityLabel("Markdown editor")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

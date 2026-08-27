import AppKit
import SwiftUI

@MainActor
protocol MarkdownTextEditing: AnyObject {
    func breakUndoCoalescing()
    func selectedRange() -> NSRange
}

@MainActor
struct MarkdownTextView: NSViewRepresentable {
    @ObservedObject var document: MarkdownDocument

    func makeCoordinator() -> Coordinator {
        Coordinator(document: document)
    }

    func makeNSView(context: Context) -> MarkdownTextEditorScrollView {
        let scrollView = MarkdownTextEditorScrollView()
        context.coordinator.connect(to: scrollView.textView)
        // Initial text load must not register undo; document's manager should remain clean.
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
    }

    static func dismantleNSView(
        _ scrollView: MarkdownTextEditorScrollView,
        coordinator: Coordinator
    ) {
        coordinator.disconnect()
    }

    final class Coordinator: NSObject, MarkdownTextEditing, NSTextViewDelegate {
        private weak var document: MarkdownDocument?
        private weak var textView: NSTextView?
        private var isSynchronizingText = false

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
            undoManager?.disableUndoRegistration()
            defer {
                undoManager?.enableUndoRegistration()
                isSynchronizingText = false
            }
            textView.string = text
        }

        func textDidChange(_ notification: Notification) {
            guard !isSynchronizingText, let textView, let document else {
                return
            }

            let newText = textView.string
            guard newText != document.text else { return }
            document.replaceText(with: newText)
            // NSDocument automatically observes its UndoManager and updates
            // isDocumentEdited / changeCount on grouping and undo/redo.
            // No manual updateChangeCount required.
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
        textView.setAccessibilityIdentifier("markdownTextEditor")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

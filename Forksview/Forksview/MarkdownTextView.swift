import AppKit
import SwiftUI

@MainActor
protocol MarkdownTextEditing: AnyObject {
    func breakUndoCoalescing()
}

@MainActor
struct MarkdownTextView: NSViewRepresentable {
    @ObservedObject var document: MarkdownDocument

    func makeCoordinator() -> Coordinator {
        Coordinator(document: document)
    }

    func makeNSView(context: Context) -> MarkdownTextEditorScrollView {
        let scrollView = MarkdownTextEditorScrollView()
        scrollView.textView.string = document.text
        context.coordinator.connect(to: scrollView.textView)
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
            guard !isSynchronizingText, let textView else {
                return
            }

            document?.replaceText(with: textView.string)
        }

        func breakUndoCoalescing() {
            textView?.breakUndoCoalescing()
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

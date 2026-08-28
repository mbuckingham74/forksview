import AppKit
import XCTest
@testable import Forksview

@MainActor
final class Milestone10VisualTests: XCTestCase {

    func testMinimumWindowContentSizeIs840x480() async throws {
        let document = MarkdownDocument()
        document.makeWindowControllers()
        guard let window = document.windowControllers.first?.window else {
            XCTFail("MarkdownDocument should create a window via makeWindowControllers")
            return
        }
        XCTAssertEqual(window.contentMinSize.width, 840, accuracy: 0.5, "minimum content width must be 840 to accommodate sidebar 180 + center 420 + inspector 220")
        XCTAssertEqual(window.contentMinSize.height, 480, accuracy: 0.5, "minimum content height must be 480")
        // Initial content size preserved
        XCTAssertEqual(window.contentView?.frame.width ?? window.frame.width, window.frame.width, "window should exist")
        // Cleanup
        window.close()
    }

    func testInitialWindowContentSizeIs1100x700() async throws {
        let document = MarkdownDocument()
        document.makeWindowControllers()
        guard let window = document.windowControllers.first?.window else {
            XCTFail("window should exist")
            return
        }
        // setContentSize is 1100x700 in makeWindowControllers; frame may be slightly larger due to titlebar but content size should be approx
        let contentSize = window.contentLayoutRect.size
        // Allow small titlebar/chrome delta but ensure at least 1100x700 content
        XCTAssertGreaterThanOrEqual(contentSize.width, 1095, "initial content width should be ~1100")
        XCTAssertGreaterThanOrEqual(contentSize.height, 695, "initial content height should be ~700")
        window.close()
    }

    func testEditorUsesNativeFixedPitchFontReadableSizeAndInsets() {
        let editor = MarkdownTextEditorScrollView()
        let tv = editor.textView

        // Font: native fixed-pitch, readable standard Mac text size (~ systemFontSize 13)
        guard let font = tv.font else {
            XCTFail("NSTextView font should be set")
            return
        }
        // isFixedPitch or userFixedPitchFont
        XCTAssertTrue(font.isFixedPitch, "editor must use fixed-pitch font (userFixedPitchFont / monospacedSystemFont)")
        // Readable size: systemFontSize is 13.0, allow 11-15
        let sysSize = NSFont.systemFontSize
        XCTAssertEqual(font.pointSize, sysSize, accuracy: 1.0, "font size should be readable standard Mac text size (~\(sysSize))")

        // Insets: approximately 16 horizontal, 14 vertical
        XCTAssertEqual(tv.textContainerInset.width, 16, accuracy: 1.0, "horizontal text-container inset should be ~16")
        XCTAssertEqual(tv.textContainerInset.height, 14, accuracy: 1.0, "vertical text-container inset should be ~14")

        // Accessibility label
        XCTAssertEqual(tv.accessibilityLabel(), "Markdown editor", "NSTextView accessibility label must be Markdown editor")

        // Identifier preserved
        XCTAssertEqual(tv.accessibilityIdentifier(), "markdownTextEditor")
    }

    func testEditorPlainTextAndNativeFlagsPreserved() {
        let editor = MarkdownTextEditorScrollView()
        let tv = editor.textView

        XCTAssertFalse(tv.isRichText, "must remain plain text")
        XCTAssertFalse(tv.importsGraphics, "must not import graphics")
        XCTAssertTrue(tv.allowsUndo, "Undo must remain enabled")
        XCTAssertFalse(tv.isAutomaticQuoteSubstitutionEnabled)
        XCTAssertFalse(tv.isAutomaticDashSubstitutionEnabled)

        XCTAssertTrue(tv.isEditable)
        XCTAssertTrue(tv.isSelectable)
        XCTAssertTrue(tv.isVerticallyResizable)
        XCTAssertFalse(tv.isHorizontallyResizable)
        XCTAssertTrue(tv.textContainer?.widthTracksTextView == true)

        XCTAssertTrue(editor.hasVerticalScroller)
        XCTAssertFalse(editor.hasHorizontalScroller)

        // Resizability
        XCTAssertEqual(tv.autoresizingMask, [.width], "editor should autoresize width")
        if let height = tv.textContainer?.containerSize.height {
            XCTAssertEqual(height, CGFloat.greatestFiniteMagnitude, accuracy: 1.0)
        } else {
            XCTFail("textContainer containerSize should exist")
        }
    }

    func testEditorIdentifierAndLabelAreStable() {
        let e1 = MarkdownTextEditorScrollView()
        let e2 = MarkdownTextEditorScrollView()
        XCTAssertEqual(e1.textView.accessibilityIdentifier(), "markdownTextEditor")
        XCTAssertEqual(e2.textView.accessibilityIdentifier(), "markdownTextEditor")
        XCTAssertEqual(e1.textView.accessibilityLabel(), "Markdown editor")
        XCTAssertEqual(e2.textView.accessibilityLabel(), "Markdown editor")
    }
}

import AppKit
import XCTest
@testable import Forksview

@MainActor
final class MarkdownTextViewNavigationReplayTests: XCTestCase {

    // A. Same navigation event handled exactly once
    // Verifies: navigate -> caret moves -> type -> document.text publishes -> SwiftUI would call updateNSView again with same request -> caret must NOT jump back
    func testSameNavigationTokenIsNotReplayed() throws {
        let document = MarkdownDocument()
        document.replaceText(with: "# Top\n\n## Section One\n\nContent\n\n## Section Two\n\nMore\n")
        document.presentationMode = .editing
        let outline = DocumentOutlineParser.outline(from: document.text)
        let target = try XCTUnwrap(outline.first(where: { $0.title == "Section Two" }))
        let anchor = DocumentAnchor(from: target)
        let request = DocumentNavigationRequest(anchor: anchor)

        let editor = MarkdownTextEditorScrollView()
        let coordinator = MarkdownTextView.Coordinator(document: document)
        coordinator.connect(to: editor.textView)
        defer { coordinator.disconnect() }
        coordinator.synchronizeTextView(with: document.text)

        // Place caret at start
        editor.textView.setSelectedRange(NSRange(location: 0, length: 0))
        coordinator.handleNavigation(request, outline: outline)
        XCTAssertEqual(editor.textView.selectedRange().location, target.sourceRange.location, "first navigation should move caret to heading")

        // Simulate user moved caret elsewhere (typed AFTER at location 0)
        editor.textView.setSelectedRange(NSRange(location: 0, length: 0))
        // Simulate SwiftUI recomputation after document.text change calling handleNavigation again with SAME token
        coordinator.handleNavigation(request, outline: outline)
        XCTAssertEqual(editor.textView.selectedRange().location, 0, "same token replay must be ignored – caret should stay at 0")

        // Distinct activation with new token must be handled
        let secondRequest = DocumentNavigationRequest(anchor: anchor)
        XCTAssertNotEqual(secondRequest.token, request.token)
        coordinator.handleNavigation(secondRequest, outline: outline)
        XCTAssertEqual(editor.textView.selectedRange().location, target.sourceRange.location, "new token must trigger navigation")
    }

    // B. Undo boundary across outline navigation
    // Verifies: BEFORE -> navigate -> AFTER -> Undo removes only AFTER -> BEFORE remains -> second Undo removes BEFORE, no empty undo for navigation itself
    func testUndoBoundaryAcrossNavigation() throws {
        let document = MarkdownDocument()
        let um = try XCTUnwrap(document.undoManager)
        um.groupsByEvent = false
        let base = "# Top\n\nBody\n"
        document.replaceText(with: base)
        // Ensure clean state then create BEFORE as undo-tracked edit
        let outlineBase = DocumentOutlineParser.outline(from: document.text)
        let target = try XCTUnwrap(outlineBase.first)
        let editor = MarkdownTextEditorScrollView()
        let coordinator = MarkdownTextView.Coordinator(document: document)
        coordinator.connect(to: editor.textView)
        defer { coordinator.disconnect() }

        // Synchronize editor to base
        coordinator.synchronizeTextView(with: document.text)
        XCTAssertFalse(um.canUndo)
        XCTAssertFalse(document.isDocumentEdited)

        // Simulate typing BEFORE via document undo registration
        let beforeText = base + "BEFORE"
        let previousBefore = document.text
        um.beginUndoGrouping()
        um.registerUndo(withTarget: document) { [weak document] target in
            guard let document else { return }
            target.replaceText(with: previousBefore)
            // Register redo inside undo (simplified)
        }
        document.replaceText(with: beforeText)
        coordinator.synchronizeTextView(with: document.text)
        um.endUndoGrouping()
        XCTAssertTrue(um.canUndo)
        XCTAssertTrue(document.isDocumentEdited)
        XCTAssertEqual(document.text, beforeText)

        // Navigate – must not create undo entry nor dirty extra
        let outlineAfterBefore = DocumentOutlineParser.outline(from: document.text)
        // Re-resolve target (still at 0)
        let navRequest = DocumentNavigationRequest(anchor: DocumentAnchor(from: target))
        let canUndoBeforeNav = um.canUndo
        coordinator.handleNavigation(navRequest, outline: outlineAfterBefore)
        XCTAssertEqual(um.canUndo, canUndoBeforeNav, "navigation must not create undo entry")
        XCTAssertTrue(document.isDocumentEdited, "navigation must not clear dirty")
        // Navigation itself should not change text
        XCTAssertEqual(document.text, beforeText)

        // Simulate typing AFTER as separate undo group
        let afterText = beforeText + " AFTER"
        let previousAfter = document.text
        um.beginUndoGrouping()
        um.registerUndo(withTarget: document) { [weak document] target in
            target.replaceText(with: previousAfter)
        }
        document.replaceText(with: afterText)
        coordinator.synchronizeTextView(with: document.text)
        um.endUndoGrouping()
        XCTAssertEqual(document.text, afterText)

        // Undo should remove AFTER only
        um.undo()
        XCTAssertEqual(document.text, beforeText, "first undo should remove AFTER, BEFORE remains")
        XCTAssertTrue(document.text.contains("BEFORE"))
        XCTAssertFalse(document.text.contains("AFTER"))
        XCTAssertTrue(um.canUndo, "should still have BEFORE to undo")

        // Second undo should remove BEFORE via normal native history
        um.undo()
        XCTAssertEqual(document.text, base)
        XCTAssertFalse(document.text.contains("BEFORE"))
    }

    // C. Navigation-only remains clean is covered by existing DocumentOutlineUITests.testNavigationStaysClean,
    // but also verify at unit level: navigation does not dirty clean document nor create undo
    func testNavigationDoesNotDirtyCleanDocument() throws {
        let document = MarkdownDocument()
        let um = try XCTUnwrap(document.undoManager)
        try document.read(from: Data("# Head\n\nBody".utf8), ofType: MarkdownDocument.typeIdentifier)
        XCTAssertFalse(document.isDocumentEdited)
        XCTAssertFalse(um.canUndo)
        let outline = DocumentOutlineParser.outline(from: document.text)
        let target = try XCTUnwrap(outline.first)
        let request = DocumentNavigationRequest(anchor: DocumentAnchor(from: target))
        document.presentationMode = .editing
        let editor = MarkdownTextEditorScrollView()
        let coordinator = MarkdownTextView.Coordinator(document: document)
        coordinator.connect(to: editor.textView)
        defer { coordinator.disconnect() }
        coordinator.handleNavigation(request, outline: outline)
        XCTAssertFalse(document.isDocumentEdited, "navigation-only must remain clean")
        XCTAssertFalse(um.canUndo, "navigation must not create undo")
    }
}

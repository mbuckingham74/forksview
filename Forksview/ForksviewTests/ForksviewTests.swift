//
//  ForksviewTests.swift
//  ForksviewTests
//
//  Created by Michael Buckingham on 8/24/26.
//

import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import Forksview

@MainActor
final class ForksviewTests: XCTestCase {
    func testEmptyUTF8DocumentRoundTrip() throws {
        XCTAssertEqual(try roundTrip(Data()), Data())
    }

    func testUnicodeContentRoundTrip() throws {
        let text = "Forks 🧭 caf\u{65}\u{301} 한"
        let data = Data(text.utf8)

        XCTAssertEqual(try roundTrip(data), data)
    }

    func testTrailingNewlineIsPreserved() throws {
        let data = Data("first\nsecond\n".utf8)

        XCTAssertEqual(try roundTrip(data), data)
    }

    func testCRLFLineEndingsArePreserved() throws {
        let data = Data("first\r\nsecond\r\n".utf8)

        XCTAssertEqual(try roundTrip(data), data)
    }

    func testInvalidUTF8IsRejectedWithMeaningfulCocoaError() throws {
        let document = MarkdownDocument()
        let invalidUTF8 = Data([0x66, 0x80, 0x6F])

        XCTAssertThrowsError(try document.read(from: invalidUTF8, ofType: MarkdownDocument.typeIdentifier)) { error in
            let cocoaError = error as NSError
            XCTAssertEqual(cocoaError.domain, NSCocoaErrorDomain)
            XCTAssertEqual(cocoaError.code, CocoaError.Code.fileReadInapplicableStringEncoding.rawValue)
            XCTAssertTrue(cocoaError.localizedDescription.contains("UTF-8"))
        }
    }

    func testTwoDocumentsHaveIndependentContents() {
        let first = MarkdownDocument()
        let second = MarkdownDocument()

        first.replaceText(with: "first")
        second.replaceText(with: "second")

        XCTAssertEqual(first.text, "first")
        XCTAssertEqual(second.text, "second")
    }

    func testNativeEditorUsesPlainTextConfiguration() {
        let editor = MarkdownTextEditorScrollView()

        XCTAssertTrue(editor.hasVerticalScroller)
        XCTAssertFalse(editor.hasHorizontalScroller)
        XCTAssertTrue(editor.textView.isVerticallyResizable)
        XCTAssertFalse(editor.textView.isHorizontallyResizable)
        XCTAssertTrue(editor.textView.textContainer?.widthTracksTextView == true)
        XCTAssertTrue(editor.textView.isEditable)
        XCTAssertTrue(editor.textView.isSelectable)
        XCTAssertFalse(editor.textView.isRichText)
        XCTAssertFalse(editor.textView.importsGraphics)
        XCTAssertTrue(editor.textView.allowsUndo)
        XCTAssertFalse(editor.textView.isAutomaticQuoteSubstitutionEnabled)
        XCTAssertFalse(editor.textView.isAutomaticDashSubstitutionEnabled)
    }

    func testProgrammaticModelSynchronizationCreatesNoUndoOrDirtyState() throws {
        let document = MarkdownDocument()
        let undoManager = try XCTUnwrap(document.undoManager)
        let editor = MarkdownTextEditorScrollView()
        let coordinator = MarkdownTextView.Coordinator(document: document)
        coordinator.connect(to: editor.textView)
        defer { coordinator.disconnect() }

        document.replaceText(with: "programmatic synchronization")
        coordinator.synchronizeTextView(with: document.text)

        XCTAssertEqual(editor.textView.string, "programmatic synchronization")
        XCTAssertFalse(undoManager.canUndo)
        XCTAssertFalse(document.isDocumentEdited)
    }

    func testInitialReadCreatesNoUndoOrDirtyState() throws {
        let document = MarkdownDocument()
        let undoManager = try XCTUnwrap(document.undoManager)

        try document.read(
            from: Data("loaded contents\n".utf8),
            ofType: MarkdownDocument.typeIdentifier
        )

        XCTAssertEqual(document.text, "loaded contents\n")
        XCTAssertFalse(undoManager.canUndo)
        XCTAssertFalse(document.isDocumentEdited)
    }

    func testNativeUndoManagerTracksEditUndoAndRedoChangeCount() throws {
        let document = MarkdownDocument()
        let undoManager = try XCTUnwrap(document.undoManager)
        undoManager.groupsByEvent = false
        XCTAssertFalse(document.isDocumentEdited)

        undoManager.beginUndoGrouping()
        replaceText("changed", in: document, registeringWith: undoManager)
        undoManager.endUndoGrouping()
        XCTAssertTrue(document.isDocumentEdited)

        undoManager.undo()
        XCTAssertEqual(document.text, "")
        XCTAssertFalse(document.isDocumentEdited)

        undoManager.redo()
        XCTAssertEqual(document.text, "changed")
        XCTAssertTrue(document.isDocumentEdited)
    }

    func testUndoAndChangeStateAreIndependentAcrossDocuments() throws {
        let first = MarkdownDocument()
        let second = MarkdownDocument()
        let firstUndoManager = try XCTUnwrap(first.undoManager)
        let secondUndoManager = try XCTUnwrap(second.undoManager)
        firstUndoManager.groupsByEvent = false
        secondUndoManager.groupsByEvent = false

        firstUndoManager.beginUndoGrouping()
        replaceText("first", in: first, registeringWith: firstUndoManager)
        firstUndoManager.endUndoGrouping()
        secondUndoManager.beginUndoGrouping()
        replaceText("second", in: second, registeringWith: secondUndoManager)
        secondUndoManager.endUndoGrouping()

        XCTAssertTrue(first.isDocumentEdited)
        XCTAssertTrue(second.isDocumentEdited)

        firstUndoManager.undo()
        XCTAssertEqual(first.text, "")
        XCTAssertFalse(first.isDocumentEdited)
        XCTAssertEqual(second.text, "second")
        XCTAssertTrue(second.isDocumentEdited)

        secondUndoManager.undo()
        XCTAssertFalse(second.isDocumentEdited)
        secondUndoManager.redo()
        XCTAssertEqual(second.text, "second")
        XCTAssertTrue(second.isDocumentEdited)
        XCTAssertFalse(first.isDocumentEdited)
    }

    func testSystemMarkdownTypeRecognizesBothExtensions() {
        XCTAssertEqual(UTType(filenameExtension: "md")?.identifier, MarkdownDocument.typeIdentifier)
        XCTAssertEqual(UTType(filenameExtension: "markdown")?.identifier, MarkdownDocument.typeIdentifier)
    }

    func testAppRegistersMarkdownDocumentAsAlternateEditor() throws {
        let documentTypes = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]])
        let markdown = try XCTUnwrap(documentTypes.first)

        XCTAssertEqual(markdown["CFBundleTypeRole"] as? String, "Editor")
        XCTAssertEqual(markdown["LSHandlerRank"] as? String, "Alternate")
        XCTAssertEqual(markdown["LSItemContentTypes"] as? [String], [MarkdownDocument.typeIdentifier])
        XCTAssertEqual(markdown["NSDocumentClass"] as? String, "Forksview.MarkdownDocument")
        XCTAssertEqual(NSDocumentController.shared.defaultType, MarkdownDocument.typeIdentifier)
        XCTAssertTrue(
            NSDocumentController.shared.documentClass(forType: MarkdownDocument.typeIdentifier) === MarkdownDocument.self
        )
    }

    func testSavingClearsChangeCountAndReopensExactContents() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let fileURL = directory.appending(path: "round-trip.md")
        let expected = "emoji 🧭\r\ntrailing\r\n"
        let document = MarkdownDocument()
        document.replaceText(with: expected)

        try await save(document, to: fileURL)

        XCTAssertFalse(document.isDocumentEdited)
        XCTAssertEqual(try Data(contentsOf: fileURL), Data(expected.utf8))

        let reopened = try MarkdownDocument(contentsOf: fileURL, ofType: MarkdownDocument.typeIdentifier)
        XCTAssertEqual(reopened.text, expected)
    }

    func testUndoAndRedoTraverseSavedStateWhenDocumentHasNoWindow() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let fileURL = directory.appending(path: "no-window-save-boundary.md")
        let originalText = "original\n"
        let savedText = "saved state\n"
        let postSaveText = "saved state\npost-save edit"
        try Data(originalText.utf8).write(to: fileURL)

        let document = try MarkdownDocument(
            contentsOf: fileURL,
            ofType: MarkdownDocument.typeIdentifier
        )
        XCTAssertTrue(document.windowControllers.isEmpty)
        let undoManager = try XCTUnwrap(document.undoManager)
        undoManager.groupsByEvent = false
        XCTAssertFalse(document.isDocumentEdited)

        undoManager.beginUndoGrouping()
        replaceText(savedText, in: document, registeringWith: undoManager)
        undoManager.endUndoGrouping()
        XCTAssertTrue(document.isDocumentEdited)

        try await save(document, to: fileURL, operation: .saveOperation)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), savedText)
        XCTAssertFalse(document.isDocumentEdited)

        undoManager.beginUndoGrouping()
        replaceText(postSaveText, in: document, registeringWith: undoManager)
        undoManager.endUndoGrouping()
        XCTAssertTrue(document.isDocumentEdited)

        undoManager.undo()
        XCTAssertEqual(document.text, savedText)
        XCTAssertFalse(document.isDocumentEdited)

        undoManager.undo()
        XCTAssertEqual(document.text, originalText)
        XCTAssertTrue(document.isDocumentEdited)

        undoManager.redo()
        XCTAssertEqual(document.text, savedText)
        XCTAssertFalse(document.isDocumentEdited)

        undoManager.redo()
        XCTAssertEqual(document.text, postSaveText)
        XCTAssertTrue(document.isDocumentEdited)

        undoManager.undo()
        XCTAssertFalse(document.isDocumentEdited)
    }

    private func roundTrip(_ data: Data) throws -> Data {
        let document = MarkdownDocument()
        try document.read(from: data, ofType: MarkdownDocument.typeIdentifier)
        return try document.data(ofType: MarkdownDocument.typeIdentifier)
    }

    private func save(
        _ document: MarkdownDocument,
        to url: URL,
        operation: NSDocument.SaveOperationType = .saveAsOperation
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            document.save(to: url, ofType: MarkdownDocument.typeIdentifier, for: operation) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func replaceText(
        _ newText: String,
        in document: MarkdownDocument,
        registeringWith undoManager: UndoManager
    ) {
        let previousText = document.text
        undoManager.registerUndo(withTarget: document) { [weak self, weak undoManager] target in
            guard let self, let undoManager else {
                return
            }
            self.replaceText(previousText, in: target, registeringWith: undoManager)
        }
        document.replaceText(with: newText)
    }
}

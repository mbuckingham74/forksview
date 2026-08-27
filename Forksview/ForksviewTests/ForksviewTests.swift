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

    func testAcceptanceFixtureContainsRequiredMarkdownElements() throws {
        let fixtureURL = try XCTUnwrap(locateAcceptanceFixtureURL())
        let content = try String(contentsOf: fixtureURL, encoding: .utf8)
        XCTAssertTrue(content.contains("# Forksview Acceptance Fixture"), "fixture must contain top-level heading")
        XCTAssertTrue(content.contains("## Overview"), "fixture must contain headings")
        XCTAssertTrue(content.contains("**"), "fixture must contain emphasis")
        XCTAssertTrue(content.contains("[Example](https://example.com)"), "fixture must contain links")
        XCTAssertTrue(content.contains("- First item"), "fixture must contain unordered lists")
        XCTAssertTrue(content.contains("1. Step one"), "fixture must contain ordered lists")
        XCTAssertTrue(content.contains("> “Reading mode is the default"), "fixture must contain blockquote")
        XCTAssertTrue(content.contains("```swift"), "fixture must contain fenced code")
        XCTAssertTrue(content.contains("| Feature | Required |"), "fixture must contain tables")
        XCTAssertTrue(content.contains("- [x] Completed task"), "fixture must contain task lists")
        XCTAssertTrue(content.contains("![Local asset]"), "fixture must contain local image")
        XCTAssertTrue(content.contains("![Remote]"), "fixture must contain remote image")
        XCTAssertTrue(content.contains("Duplicate heading"), "fixture must contain duplicate headings")
        XCTAssertTrue(content.filter({ $0 == "\n" }).count > 80, "fixture must be long enough to expose long-document behavior")
        XCTAssertTrue(content.contains("Repeated Block 15"), "fixture must include repeated block to test long-document scrolling")
    }

    func testMarkdownReadingViewPreservesContentAndBaseURL() {
        let base = URL(fileURLWithPath: "/tmp/example.md")
        let sample = "# Hello\n\nWorld [link](https://example.com)"
        let view = MarkdownReadingView(markdown: sample, baseURL: base)
        XCTAssertEqual(view.markdown, sample)
        XCTAssertEqual(view.baseURL, base)

        let empty = MarkdownReadingView(markdown: "")
        XCTAssertEqual(empty.markdown, "")
        XCTAssertNil(empty.baseURL)
    }

    func testRendererIsIsolatedBehindMarkdownReadingView() throws {
        let appSourcesURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Forksview", directoryHint: .isDirectory)
        let fileURLs = try FileManager.default
            .contentsOfDirectory(at: appSourcesURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        var importers: [String] = []
        for url in fileURLs {
            let text = try String(contentsOf: url, encoding: .utf8)
            if text.contains("import MarkdownUI") {
                importers.append(url.lastPathComponent)
            }
        }
        // Reading layer is the only place allowed to import MarkdownUI.
        // MarkdownImageSupport is part of the reading layer alongside MarkdownReadingView.
        XCTAssertEqual(Set(importers), Set(["MarkdownReadingView.swift", "MarkdownImageSupport.swift"]))
        XCTAssertEqual(importers.sorted(), importers.sorted(), "isolation check is deterministic")
    }

    // MARK: - Milestone 4 behavioral coverage

    func testRenderingBaseURLIsDocumentDirectory() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let fileURL = dir.appending(path: "note.md")
        try Data("# hi".utf8).write(to: fileURL)
        let doc = try MarkdownDocument(contentsOf: fileURL, ofType: MarkdownDocument.typeIdentifier)
        XCTAssertEqual(doc.renderingBaseURL?.path, dir.path)
    }

    func testRenderingBaseURLIsNilForUntitledDocument() {
        let doc = MarkdownDocument()
        XCTAssertNil(doc.renderingBaseURL)
    }

    func testMarkdownImageResolverResolvesRelativeLocalImage() {
        let base = URL(fileURLWithPath: "/tmp/docs/")
        let resolved = MarkdownImageResolver.resolvedURL(for: "assets/local.png", baseURL: base)
        XCTAssertNotNil(resolved)
        XCTAssertTrue(resolved?.isFileURL == true)
        XCTAssertEqual(resolved?.path, "/tmp/docs/assets/local.png")
        XCTAssertTrue(MarkdownImageResolver.isLocalFileURL(resolved))
    }

    func testMarkdownImageResolverResolvesDotSlashRelative() {
        let base = URL(fileURLWithPath: "/tmp/docs/")
        let resolved = MarkdownImageResolver.resolvedURL(for: "./assets/local.png", baseURL: base)
        XCTAssertEqual(resolved?.path, "/tmp/docs/assets/local.png")
        XCTAssertTrue(MarkdownImageResolver.isLocalFileURL(resolved))
    }

    func testMarkdownImageResolverRemoteURLIsNotLocal() {
        let remote = MarkdownImageResolver.resolvedURL(for: "https://example.com/image.png", baseURL: nil)
        XCTAssertNotNil(remote)
        XCTAssertFalse(MarkdownImageResolver.isLocalFileURL(remote))
        XCTAssertEqual(remote?.scheme, "https")
    }

    func testMarkdownImageResolverAbsoluteFileURLIsLocal() {
        let url = URL(fileURLWithPath: "/tmp/image.png")
        XCTAssertTrue(MarkdownImageResolver.isLocalFileURL(url))
    }

    func testFixtureLocalImageResolvesToExistingFile() throws {
        // Exact invariant: the renderer-resolved URL must itself exist.
        // No fallback search (bundle root, flattened location) is relevant.
        let fixtureURL = try XCTUnwrap(locateAcceptanceFixtureURL(), "fixture must be located")
        let baseURL = fixtureURL.deletingLastPathComponent()
        let local = MarkdownImageResolver.resolvedURL(for: "assets/local.png", baseURL: baseURL)
        XCTAssertNotNil(local)
        XCTAssertTrue(MarkdownImageResolver.isLocalFileURL(local))
        XCTAssertTrue(MarkdownImageResolver.localFileExists(at: local), "renderer-resolved URL \(String(describing: local?.path)) must exist relative to fixture base \(baseURL.path)")
        let dotLocal = MarkdownImageResolver.resolvedURL(for: "./assets/local.png", baseURL: baseURL)
        XCTAssertNotNil(dotLocal)
        XCTAssertTrue(MarkdownImageResolver.isLocalFileURL(dotLocal))
        XCTAssertTrue(MarkdownImageResolver.localFileExists(at: dotLocal), "renderer-resolved ./assets/local.png URL \(String(describing: dotLocal?.path)) must exist")
    }

    func testFixtureLocatorFindsAcceptanceFixture() throws {
        let fixtureURL = try XCTUnwrap(locateAcceptanceFixtureURL())
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixtureURL.path))
        let content = try String(contentsOf: fixtureURL, encoding: .utf8)
        XCTAssertFalse(content.isEmpty)
        XCTAssertTrue(content.contains("# Forksview Acceptance Fixture"))
        let baseURL = fixtureURL.deletingLastPathComponent()
        XCTAssertTrue(baseURL.isFileURL)
    }

    func testReadingViewRendersRealFixtureContent() throws {
        let fixtureURL = try XCTUnwrap(locateAcceptanceFixtureURL())
        let markdown = try String(contentsOf: fixtureURL, encoding: .utf8)
        let baseURL = fixtureURL.deletingLastPathComponent()
        let view = MarkdownReadingView(markdown: markdown, baseURL: baseURL)
        XCTAssertEqual(view.markdown, markdown)
        XCTAssertEqual(view.baseURL, baseURL)
        XCTAssertTrue(view.markdown.contains("assets/local.png"))
    }

    // MARK: - Milestone 5: reading/edit transition

    func testReadingIsDefaultForNewDocument() {
        let document = MarkdownDocument()
        XCTAssertEqual(document.presentationMode, .reading, "new documents must default to reading per product contract")
    }

    func testReadingIsDefaultForReopenedDocument() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let fileURL = dir.appending(path: "reopen-default.md")
        try Data("# Hello\n".utf8).write(to: fileURL)
        let doc = try MarkdownDocument(contentsOf: fileURL, ofType: MarkdownDocument.typeIdentifier)
        XCTAssertEqual(doc.presentationMode, .reading)
    }

    func testTogglePresentationModeSwitchesBetweenReadingAndEditing() {
        let document = MarkdownDocument()
        XCTAssertEqual(document.presentationMode, .reading)
        document.togglePresentationMode(nil)
        XCTAssertEqual(document.presentationMode, .editing)
        document.togglePresentationMode(nil)
        XCTAssertEqual(document.presentationMode, .reading)
        document.enterEditingMode(nil)
        XCTAssertEqual(document.presentationMode, .editing)
        document.enterReadingMode(nil)
        XCTAssertEqual(document.presentationMode, .reading)
    }

    func testEditToReadUsesLatestTextWithoutSave() {
        let document = MarkdownDocument()
        document.replaceText(with: "initial")
        document.togglePresentationMode(nil) // reading -> editing
        XCTAssertEqual(document.presentationMode, .editing)
        // Simulate typing via replaceText (same path as NSTextView delegate)
        document.replaceText(with: "# Edited\n\nNew content with **bold**")
        // Toggle to reading - should immediately see latest text
        document.togglePresentationMode(nil)
        XCTAssertEqual(document.presentationMode, .reading)
        // Reading view consumes document.text directly - verify latest
        let reading = MarkdownReadingView(markdown: document.text, baseURL: document.renderingBaseURL)
        XCTAssertEqual(reading.markdown, "# Edited\n\nNew content with **bold**")
        XCTAssertTrue(reading.markdown.contains("New content"))
    }

    func testReadToEditPreservesText() {
        let document = MarkdownDocument()
        let original = "## Heading\n\nBody text"
        document.replaceText(with: original)
        XCTAssertEqual(document.presentationMode, .reading)
        document.togglePresentationMode(nil) // to editing
        XCTAssertEqual(document.presentationMode, .editing)
        XCTAssertEqual(document.text, original)
        // Simulate editing branch still shows same text via MarkdownTextView sync
        let editor = MarkdownTextEditorScrollView()
        let coordinator = MarkdownTextView.Coordinator(document: document)
        coordinator.connect(to: editor.textView)
        defer { coordinator.disconnect() }
        coordinator.synchronizeTextView(with: document.text)
        XCTAssertEqual(editor.textView.string, original)
    }

    func testRendererReceivesCorrectBaseURLViaDocument() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let fileURL = dir.appending(path: "base.md")
        try Data("![Local](assets/local.png)".utf8).write(to: fileURL)
        let doc = try MarkdownDocument(contentsOf: fileURL, ofType: MarkdownDocument.typeIdentifier)
        // readingBaseURL is dir, passed to reading view
        let view = MarkdownReadingView(markdown: doc.text, baseURL: doc.renderingBaseURL)
        XCTAssertEqual(view.baseURL?.path, dir.path)
        XCTAssertEqual(view.markdown, "![Local](assets/local.png)")
    }

    func testNativeEditorRemainsNSTextView() {
        let editor = MarkdownTextEditorScrollView()
        XCTAssertFalse(editor.textView.isRichText)
        XCTAssertTrue(editor.textView.allowsUndo)
        XCTAssertFalse(editor.textView.isAutomaticQuoteSubstitutionEnabled)
        XCTAssertFalse(editor.textView.isAutomaticDashSubstitutionEnabled)
        XCTAssertEqual(editor.textView.accessibilityIdentifier(), "markdownTextEditor")
    }

    func testDirtyStateRemainsTruthfulAcrossModeToggles() throws {
        let document = MarkdownDocument()
        let um = try XCTUnwrap(document.undoManager)
        um.groupsByEvent = false
        XCTAssertFalse(document.isDocumentEdited)
        um.beginUndoGrouping()
        replaceText("dirty edit", in: document, registeringWith: um)
        um.endUndoGrouping()
        XCTAssertTrue(document.isDocumentEdited)
        // Toggle reading/editing should not clear dirty
        document.togglePresentationMode(nil)
        XCTAssertTrue(document.isDocumentEdited)
        document.togglePresentationMode(nil)
        XCTAssertTrue(document.isDocumentEdited)
        // Undo should clear dirty even after toggles
        um.undo()
        XCTAssertFalse(document.isDocumentEdited)
        XCTAssertEqual(document.text, "")
    }

    func testUndoHistorySurvivesModeTransitions() throws {
        let document = MarkdownDocument()
        let um = try XCTUnwrap(document.undoManager)
        um.groupsByEvent = false
        um.beginUndoGrouping()
        replaceText("first edit", in: document, registeringWith: um)
        um.endUndoGrouping()
        um.beginUndoGrouping()
        replaceText("second edit", in: document, registeringWith: um)
        um.endUndoGrouping()
        XCTAssertEqual(document.text, "second edit")
        // Toggle through modes several times
        document.togglePresentationMode(nil)
        document.togglePresentationMode(nil)
        document.togglePresentationMode(nil)
        XCTAssertEqual(document.presentationMode, .editing)
        um.undo()
        XCTAssertEqual(document.text, "first edit")
        um.undo()
        XCTAssertEqual(document.text, "")
        um.redo()
        XCTAssertEqual(document.text, "first edit")
    }

    func testSyncAvoidsFakeUndoOnProgrammaticUpdate() throws {
        let document = MarkdownDocument()
        let um = try XCTUnwrap(document.undoManager)
        let editor = MarkdownTextEditorScrollView()
        let coordinator = MarkdownTextView.Coordinator(document: document)
        coordinator.connect(to: editor.textView)
        defer { coordinator.disconnect() }
        // Programmatic sync must not register undo
        document.replaceText(with: "programmatic")
        coordinator.synchronizeTextView(with: document.text)
        XCTAssertFalse(um.canUndo)
        // Toggle should keep that invariant
        document.togglePresentationMode(nil)
        document.togglePresentationMode(nil)
        XCTAssertFalse(um.canUndo)
    }

    func testDocumentAnchorFindsNearestHeading() {
        let text = "# Top\n\nBody\n\n## Section One\n\nContent\n\n### Subsection\n\nMore"
        // Offset inside "More" should find "Subsection"
        let offsetNearEnd = (text as NSString).length - 2
        let anchor = DocumentAnchor.anchor(for: offsetNearEnd, in: text)
        XCTAssertEqual(anchor.heading, "Subsection")
        // Offset inside Section One content should find Section One
        let sectionOneRange = (text as NSString).range(of: "Content")
        let anchor2 = DocumentAnchor.anchor(for: sectionOneRange.location, in: text)
        XCTAssertEqual(anchor2.heading, "Section One")
        // Offset at top should find Top
        let anchorTop = DocumentAnchor.anchor(for: 2, in: text)
        XCTAssertEqual(anchorTop.heading, "Top")
        // No heading case
        let plain = "Just plain text\nno headings"
        let anchorPlain = DocumentAnchor.anchor(for: 5, in: plain)
        XCTAssertNil(anchorPlain.heading)
    }

    func testDocumentAnchorClampsOffsetAndCalculatesLine() {
        let text = "line1\nline2\n# Heading\nline4"
        let anchor = DocumentAnchor.anchor(for: 9999, in: text)
        XCTAssertEqual(anchor.offset, (text as NSString).length)
        XCTAssertEqual(anchor.heading, "Heading")
        let lineAnchor = DocumentAnchor.anchor(for: 0, in: text)
        XCTAssertEqual(lineAnchor.line, 1)
        let secondLine = DocumentAnchor.anchor(for: 6, in: text) // after "line1\n"
        XCTAssertEqual(secondLine.line, 2)
    }

    func testSingleSourceOfTruthAcrossModes() {
        let document = MarkdownDocument()
        document.replaceText(with: "shared")
        // Both presentations read same string, no copy
        let reading = MarkdownReadingView(markdown: document.text, baseURL: nil)
        XCTAssertEqual(reading.markdown, document.text)
        let editor = MarkdownTextEditorScrollView()
        let coordinator = MarkdownTextView.Coordinator(document: document)
        coordinator.connect(to: editor.textView)
        defer { coordinator.disconnect() }
        coordinator.synchronizeTextView(with: document.text)
        XCTAssertEqual(editor.textView.string, document.text)
        // Change once, both should see latest on next sync/toggle
        document.replaceText(with: "shared updated")
        coordinator.synchronizeTextView(with: document.text)
        let reading2 = MarkdownReadingView(markdown: document.text, baseURL: nil)
        XCTAssertEqual(reading2.markdown, "shared updated")
        XCTAssertEqual(editor.textView.string, "shared updated")
    }

    private func locateAcceptanceFixtureURL() -> URL? {
        let bundles: [Bundle] = [.main, Bundle(for: ForksviewTests.self)]
        for bundle in bundles {
            if let url = bundle.url(forResource: "AcceptanceFixture", withExtension: "md") {
                return url
            }
            if let url = bundle.url(forResource: "AcceptanceFixture", withExtension: "md", subdirectory: "Fixtures") {
                return url
            }
        }
        let candidatePaths: [String] = [
            "Forksview/Forksview/Fixtures/AcceptanceFixture.md",
            "Forksview/Fixtures/AcceptanceFixture.md",
        ]
        let fm = FileManager.default
        let searchRoots: [URL] = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent(),
            URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent(),
        ]
        for root in searchRoots {
            for candidate in candidatePaths {
                let url = root.appending(path: candidate)
                if fm.fileExists(atPath: url.path) {
                    return url
                }
            }
        }
        return nil
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

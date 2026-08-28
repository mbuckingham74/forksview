import AppKit
import XCTest
@testable import Forksview

private final class FileCoordinationResult: @unchecked Sendable {
    var coordinatorError: NSError?
    var accessorError: NSError?
}

@MainActor
final class ExternalChangeTests: XCTestCase {

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func makeIsolatedStore() throws -> (DocumentBookmarkStore, URL) {
        let dir = try makeTempDir()
        let archive = dir.appending(path: "Bookmarks.json")
        let store = DocumentBookmarkStore(archiveURL: archive)
        return (store, archive)
    }

    private func makeDocument(text: String, fileURL: URL, store: DocumentBookmarkStore) throws -> MarkdownDocument {
        try Data(text.utf8).write(to: fileURL)
        let doc = MarkdownDocument()
        doc.injectBookmarkStoreForTesting(store)
        try doc.read(from: Data(text.utf8), ofType: MarkdownDocument.typeIdentifier)
        // set fileURL without triggering didSet observer (removed in M9) – use NSDocument's fileURL setter
        // NSDocument fileURL is set via display? We can use the internal fileURL property directly
        // Use KVC alternative: set via fileURL setter on MainActor
        doc.setFileURLForTesting(fileURL)
        doc.undoManager?.removeAllActions()
        doc.updateChangeCount(.changeCleared)
        // Register the real NSDocument presenter path used by the application.
        // Coordinated mutations below run off the main actor so presenter delivery
        // can reach this MainActor document without deadlocking the test.
        let documentController = NSDocumentController.shared
        documentController.addDocument(doc)
        NSFileCoordinator.addFilePresenter(doc)
        addTeardownBlock {
            NSFileCoordinator.removeFilePresenter(doc)
            documentController.removeDocument(doc)
        }
        return doc
    }

    private func makeDirtyDocument(initialText: String, editedText: String, fileURL: URL, store: DocumentBookmarkStore) throws -> MarkdownDocument {
        let doc = try makeDocument(text: initialText, fileURL: fileURL, store: store)
        let um = try XCTUnwrap(doc.undoManager)
        um.groupsByEvent = false
        um.beginUndoGrouping()
        replaceText(editedText, in: doc, registeringWith: um)
        um.endUndoGrouping()
        XCTAssertTrue(doc.isDocumentEdited)
        return doc
    }

    private func replaceText(_ newText: String, in doc: MarkdownDocument, registeringWith um: UndoManager) {
        let prev = doc.text
        um.registerUndo(withTarget: doc) { [weak self] target in
            guard let self else { return }
            self.replaceText(prev, in: target, registeringWith: um)
        }
        doc.replaceText(with: newText)
    }

    private func coordinatedWrite(_ newText: String, to url: URL) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = FileCoordinationResult()
                NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: [], error: &result.coordinatorError) { newURL in
                    do { try Data(newText.utf8).write(to: newURL) } catch { result.accessorError = error as NSError }
                }
                if let e = result.coordinatorError { cont.resume(throwing: e) }
                else if let e = result.accessorError { cont.resume(throwing: e) }
                else { cont.resume() }
            }
        }
    }

    private func coordinatedWriteInvalidBytes(_ bytes: Data, to url: URL) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = FileCoordinationResult()
                NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: [], error: &result.coordinatorError) { newURL in
                    do { try bytes.write(to: newURL) } catch { result.accessorError = error as NSError }
                }
                if let e = result.coordinatorError { cont.resume(throwing: e) }
                else if let e = result.accessorError { cont.resume(throwing: e) }
                else { cont.resume() }
            }
        }
    }

    private func coordinatedMove(from src: URL, to dst: URL) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = FileCoordinationResult()
                NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: src, options: .forMoving, writingItemAt: dst, options: .forReplacing, error: &result.coordinatorError) { oldURL, newURL in
                    do { try FileManager.default.moveItem(at: oldURL, to: newURL) } catch { result.accessorError = error as NSError }
                }
                if let e = result.coordinatorError { cont.resume(throwing: e) }
                else if let e = result.accessorError { cont.resume(throwing: e) }
                else { cont.resume() }
            }
        }
    }

    private func coordinatedDelete(at url: URL) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = FileCoordinationResult()
                NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forDeleting, error: &result.coordinatorError) { newURL in
                    do { try FileManager.default.removeItem(at: newURL) } catch { result.accessorError = error as NSError }
                }
                if let e = result.coordinatorError { cont.resume(throwing: e) }
                else if let e = result.accessorError { cont.resume(throwing: e) }
                else { cont.resume() }
            }
        }
    }

    private func save(_ document: MarkdownDocument, to url: URL, operation: NSDocument.SaveOperationType = .saveOperation) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            document.save(to: url, ofType: MarkdownDocument.typeIdentifier, for: operation) { err in
                if let err { cont.resume(throwing: err) } else { cont.resume() }
            }
        }
    }

    private func waitForText(_ expected: String, in doc: MarkdownDocument, timeout: TimeInterval = 2.0) async throws {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if doc.text == expected { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out waiting for text \"\(expected)\", current \"\(doc.text)\"")
    }

    private func waitForPendingConflict(in doc: MarkdownDocument, timeout: TimeInterval = 2.0) async {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if doc.hasPendingConflictForTesting() { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out waiting for pending external conflict")
    }

    private func waitForFileURL(_ expected: URL, in doc: MarkdownDocument, timeout: TimeInterval = 2.0) async {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if doc.fileURL == expected { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        let currentPath = doc.fileURL?.path ?? "nil"
        XCTFail("Timed out waiting for document URL \(expected.path); current \(currentPath)")
    }

    // MARK: - 1. Autosave policy

    func testAutosavesInPlaceIsFalse() {
        XCTAssertFalse(MarkdownDocument.autosavesInPlace)
    }

    func testAutosavesDraftsIsFalse() {
        XCTAssertFalse(MarkdownDocument.autosavesDrafts)
    }

    func testAutosavingDelayIsThirty() {
        _ = NSDocumentController.shared
        XCTAssertEqual(NSDocumentController.shared.autosavingDelay, 30)
    }

    func testAutosavedContentsFileURLInitiallyNil() {
        let doc = MarkdownDocument()
        XCTAssertNil(doc.autosavedContentsFileURL)
    }

    // MARK: - Clean external change

    func testCleanExternalWriteReloadsAndRemainsCleanAndClearsUndo() async throws {
        let dir = try makeTempDir()
        let url = dir.appending(path: "clean.md")
        let initial = "# Title\n\ninitial"
        let external = "# Title\n\nexternal change"
        let (store, _) = try makeIsolatedStore()
        let doc = try makeDocument(text: initial, fileURL: url, store: store)
        XCTAssertFalse(doc.isDocumentEdited)
        let um = try XCTUnwrap(doc.undoManager)
        um.groupsByEvent = false
        um.beginUndoGrouping()
        let prev = doc.text
        um.registerUndo(withTarget: doc) { t in t.replaceText(with: prev) }
        doc.replaceText(with: "temp")
        doc.updateChangeCount(.changeDone)
        um.endUndoGrouping()
        um.removeAllActions()
        doc.updateChangeCount(.changeCleared)
        doc.replaceText(with: initial)
        um.removeAllActions()
        XCTAssertFalse(doc.isDocumentEdited)
        XCTAssertFalse(um.canUndo)

        try await coordinatedWrite(external, to: url)
        try await waitForText(external, in: doc)

        XCTAssertEqual(doc.text, external)
        XCTAssertFalse(doc.isDocumentEdited)
        XCTAssertFalse(um.canUndo, "old undo cleared")
        XCTAssertEqual(doc.presentationMode, .reading)
        XCTAssertFalse(doc.hasPendingConflictForTesting())
    }

    func testCleanExternalReloadPreservesEditingModeAndSelection() async throws {
        let dir = try makeTempDir()
        let url = dir.appending(path: "editmode.md")
        let initial = "# Top\n\nBody\n\n## Section\n\nContent"
        let external = "# Top\n\nBody updated\n\n## Section\n\nContent updated"
        let (store, _) = try makeIsolatedStore()
        let doc = try makeDocument(text: initial, fileURL: url, store: store)
        doc.presentationMode = .editing
        let sel = NSRange(location: 5, length: 0)
        doc.pendingEditingSelection = sel
        let editorView = MarkdownTextEditorScrollView()
        let coordinator = MarkdownTextView.Coordinator(document: doc)
        coordinator.connect(to: editorView.textView)
        defer { coordinator.disconnect() }
        editorView.textView.string = initial
        editorView.textView.setSelectedRange(sel)

        try await coordinatedWrite(external, to: url)
        try await waitForText(external, in: doc)

        XCTAssertEqual(doc.presentationMode, .editing)
        XCTAssertEqual(doc.text, external)
        XCTAssertFalse(doc.isDocumentEdited)
        XCTAssertNotNil(doc.pendingEditingSelection)
        XCTAssertFalse(try XCTUnwrap(doc.undoManager).canUndo)
    }

    func testCleanExternalReloadReadingUsesSemanticNavigation() async throws {
        let dir = try makeTempDir()
        let url = dir.appending(path: "reading.md")
        let initial = "# Alpha\n\nContent\n\n## Beta\n\nMore"
        let external = "# Alpha\n\nContent changed\n\n## Beta\n\nMore changed"
        let (store, _) = try makeIsolatedStore()
        let doc = try makeDocument(text: initial, fileURL: url, store: store)
        doc.presentationMode = .reading
        let outline = DocumentOutlineParser.outline(from: initial)
        let beta = try XCTUnwrap(outline.first(where: { $0.title == "Beta" }))
        doc.lastAnchor = DocumentAnchor(from: beta)

        try await coordinatedWrite(external, to: url)
        try await waitForText(external, in: doc)
        XCTAssertEqual(doc.presentationMode, .reading)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNotNil(doc.externalReloadNavigationRequest)
        XCTAssertEqual(doc.externalReloadNavigationRequest?.anchor.heading, "Beta")
    }

    func testCleanReloadUpdatesOutlineAndBookmarkStale() async throws {
        let dir = try makeTempDir()
        let url = dir.appending(path: "bookmark.md")
        let initial = "# Keep\n\nText\n\n## RemoveMe\n\nBody"
        let external = "# Keep\n\nText updated\n\nBody without heading"
        let (store, _) = try makeIsolatedStore()
        let doc = try makeDocument(text: initial, fileURL: url, store: store)
        let outline0 = DocumentOutlineParser.outline(from: initial)
        let removeItem = try XCTUnwrap(outline0.first(where: { $0.title == "RemoveMe" }))
        doc.addBookmark(for: removeItem, in: outline0)
        let bm = doc.bookmarks[0]
        XCTAssertEqual(DocumentBookmarkResolver.resolve(bm, in: outline0).isResolved, true)

        try await coordinatedWrite(external, to: url)
        try await waitForText(external, in: doc)

        let newOutline = DocumentOutlineParser.outline(from: doc.text)
        XCTAssertEqual(newOutline.count, 1)
        XCTAssertTrue(DocumentBookmarkResolver.resolve(bm, in: newOutline).isStale)
    }

    func testCleanReloadNoUndoEntryAndOldHistoryCleared() async throws {
        let dir = try makeTempDir()
        let url = dir.appending(path: "undo.md")
        let initial = "initial"
        let external = "external"
        let (store, _) = try makeIsolatedStore()
        let doc = try makeDocument(text: initial, fileURL: url, store: store)
        let um = try XCTUnwrap(doc.undoManager)
        um.groupsByEvent = false
        um.beginUndoGrouping()
        let prev = doc.text
        um.registerUndo(withTarget: doc) { t in t.replaceText(with: prev) }
        doc.replaceText(with: "temp")
        um.endUndoGrouping()
        um.removeAllActions()
        doc.updateChangeCount(.changeCleared)
        doc.replaceText(with: initial)
        um.removeAllActions()
        XCTAssertFalse(um.canUndo)

        try await coordinatedWrite(external, to: url)
        try await waitForText(external, in: doc)
        XCTAssertFalse(um.canUndo)
        XCTAssertFalse(doc.isDocumentEdited)
    }

    // MARK: - Dirty external conflict

    func testDirtyExternalChangeIsNotReloadedAndPreservesLocal() async throws {
        let dir = try makeTempDir()
        let url = dir.appending(path: "dirty.md")
        let initial = "initial\n"
        let local = "local dirty\n"
        let external = "external dirty\n"
        let (store, _) = try makeIsolatedStore()
        let doc = try makeDirtyDocument(initialText: initial, editedText: local, fileURL: url, store: store)
        let um = try XCTUnwrap(doc.undoManager)

        try await coordinatedWrite(external, to: url)
        await waitForPendingConflict(in: doc)

        XCTAssertEqual(doc.text, local)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), external)
        XCTAssertTrue(doc.isDocumentEdited)
        XCTAssertTrue(um.canUndo)
        XCTAssertTrue(doc.hasPendingConflictForTesting())
    }

    func testDirtyConflictPreservesSelectionAndUndo() async throws {
        let dir = try makeTempDir()
        let url = dir.appending(path: "dirty2.md")
        let initial = "# H\n\ninitial"
        let local = "# H\n\nlocal"
        let external = "# H\n\nexternal"
        let (store, _) = try makeIsolatedStore()
        let doc = try makeDirtyDocument(initialText: initial, editedText: local, fileURL: url, store: store)
        doc.presentationMode = .editing
        doc.pendingEditingSelection = NSRange(location: 2, length: 1)
        let um = try XCTUnwrap(doc.undoManager)
        let canUndoBefore = um.canUndo

        try await coordinatedWrite(external, to: url)
        await waitForPendingConflict(in: doc)

        XCTAssertEqual(doc.presentationMode, .editing)
        XCTAssertEqual(doc.pendingEditingSelection, NSRange(location: 2, length: 1))
        XCTAssertEqual(um.canUndo, canUndoBefore)
    }

    func testSaveAsPreservesExternalSource() async throws {
        let dir = try makeTempDir()
        let src = dir.appending(path: "src.md")
        let dst = dir.appending(path: "dst.md")
        let initial = "initial"
        let local = "local"
        let external = "external"
        let (store, _) = try makeIsolatedStore()
        let doc = try makeDirtyDocument(initialText: initial, editedText: local, fileURL: src, store: store)
        try await coordinatedWrite(external, to: src)
        try await Task.sleep(nanoseconds: 100_000_000)

        try await save(doc, to: dst, operation: .saveAsOperation)
        XCTAssertEqual(try String(contentsOf: src, encoding: .utf8), external)
        XCTAssertEqual(try String(contentsOf: dst, encoding: .utf8), local)
        XCTAssertEqual(doc.fileURL?.path, dst.path)
    }

    func testRevertDiscardsLocalViaNativePath() async throws {
        let dir = try makeTempDir()
        let url = dir.appending(path: "revert.md")
        let initial = "initial"
        let local = "local"
        let external = "external"
        let (store, _) = try makeIsolatedStore()
        let doc = try makeDirtyDocument(initialText: initial, editedText: local, fileURL: url, store: store)
        try await coordinatedWrite(external, to: url)
        await waitForPendingConflict(in: doc)

        try doc.revert(toContentsOf: url, ofType: MarkdownDocument.typeIdentifier)
        XCTAssertEqual(doc.text, external)
        XCTAssertFalse(doc.isDocumentEdited)
        XCTAssertFalse(doc.hasPendingConflictForTesting())
        XCTAssertFalse(try XCTUnwrap(doc.undoManager).canUndo)
    }

    // MARK: - Autosave elsewhere

    func testAutosaveElsewhereDoesNotOverwriteRealFileAndPreservesState() async throws {
        let dir = try makeTempDir()
        let url = dir.appending(path: "autosave.md")
        let initial = "initial"
        let local = "local dirty autosave"
        let (store, _) = try makeIsolatedStore()
        let doc = try makeDirtyDocument(initialText: initial, editedText: local, fileURL: url, store: store)
        let outline = DocumentOutlineParser.outline(from: local)
        if let first = outline.first { doc.addBookmark(for: first, in: outline) }
        let bookmarksBefore = doc.bookmarks
        let archiveBefore = store.currentArchive()
        let recoveryURL = dir.appending(path: "recovery.md")

        try await save(doc, to: recoveryURL, operation: .autosaveElsewhereOperation)

        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), initial)
        XCTAssertEqual(doc.fileURL?.path, url.path)
        XCTAssertTrue(doc.isDocumentEdited)
        XCTAssertEqual(doc.bookmarks, bookmarksBefore)
        XCTAssertEqual(store.currentArchive().documents, archiveBefore.documents)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(doc.hasUnautosavedChanges)
        let um = try XCTUnwrap(doc.undoManager)
        um.beginUndoGrouping()
        let prev = doc.text
        um.registerUndo(withTarget: doc) { t in t.replaceText(with: prev) }
        doc.replaceText(with: local + " again")
        doc.updateChangeCount(.changeDone)
        um.endUndoGrouping()
        XCTAssertTrue(doc.hasUnautosavedChanges)
    }

    func testUntitledAutosaveElsewherePreservesNilFileURL() async throws {
        let (store, _) = try makeIsolatedStore()
        let doc = MarkdownDocument()
        doc.injectBookmarkStoreForTesting(store)
        doc.replaceText(with: "untitled dirty")
        let um = try XCTUnwrap(doc.undoManager)
        um.groupsByEvent = false
        um.beginUndoGrouping()
        um.registerUndo(withTarget: doc) { t in t.replaceText(with: "") }
        doc.updateChangeCount(.changeDone)
        um.endUndoGrouping()
        XCTAssertTrue(doc.isDocumentEdited)
        XCTAssertNil(doc.fileURL)

        let dir = try makeTempDir()
        let recovery = dir.appending(path: "untitled-recovery.md")
        let before = doc.bookmarks
        try await save(doc, to: recovery, operation: .autosaveElsewhereOperation)
        XCTAssertNil(doc.fileURL)
        XCTAssertTrue(doc.isDocumentEdited)
        XCTAssertEqual(doc.bookmarks, before)
        XCTAssertFalse(store.containsRecord(for: recovery))
    }

    // MARK: - Own-save discrimination

    func testExplicitSaveDoesNotTriggerFalseReload() async throws {
        let dir = try makeTempDir()
        let url = dir.appending(path: "ownsave.md")
        let initial = "initial"
        let edited = "edited"
        let (store, _) = try makeIsolatedStore()
        let doc = try makeDirtyDocument(initialText: initial, editedText: edited, fileURL: url, store: store)
        try await save(doc, to: url, operation: .saveOperation)
        XCTAssertFalse(doc.isDocumentEdited)
        XCTAssertEqual(doc.text, edited)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(doc.text, edited)
        XCTAssertFalse(doc.hasPendingConflictForTesting())
    }

    func testSaveAsDoesNotTriggerReloadLoop() async throws {
        let dir = try makeTempDir()
        let src = dir.appending(path: "src2.md")
        let dst = dir.appending(path: "dst2.md")
        let initial = "initial"
        let edited = "edited saveAs"
        let (store, _) = try makeIsolatedStore()
        let doc = try makeDirtyDocument(initialText: initial, editedText: edited, fileURL: src, store: store)
        try await save(doc, to: dst, operation: .saveAsOperation)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(doc.text, edited)
        XCTAssertFalse(doc.hasPendingConflictForTesting())
        XCTAssertEqual(doc.fileURL?.path, dst.path)
    }

    // MARK: - Rapid external writes

    func testRapidExternalWritesCoalesceAndFinalWins() async throws {
        let dir = try makeTempDir()
        let url = dir.appending(path: "rapid.md")
        let initial = "initial"
        let mid = "mid external"
        let final = "final external"
        let (store, _) = try makeIsolatedStore()
        let doc = try makeDocument(text: initial, fileURL: url, store: store)
        XCTAssertFalse(doc.isDocumentEdited)
        try await coordinatedWrite(mid, to: url)
        try await coordinatedWrite(final, to: url)
        try await waitForText(final, in: doc)
        XCTAssertEqual(doc.text, final)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(doc.text, final)
    }

    // MARK: - Rename / move

    func testRenameMoveUpdatesFileURLAndPreservesState() async throws {
        let dir = try makeTempDir()
        let src = dir.appending(path: "a.md")
        let dst = dir.appending(path: "b.md")
        let content = "# Keep\n\ncontent"
        let (store, _) = try makeIsolatedStore()
        let doc = try makeDocument(text: content, fileURL: src, store: store)
        let outline = DocumentOutlineParser.outline(from: content)
        if let item = outline.first { doc.addBookmark(for: item, in: outline) }
        let bmBefore = doc.bookmarks
        let um = try XCTUnwrap(doc.undoManager)
        um.groupsByEvent = false
        um.beginUndoGrouping()
        um.registerUndo(withTarget: doc) { t in t.replaceText(with: content) }
        doc.replaceText(with: content + " dirty")
        doc.updateChangeCount(.changeDone)
        um.endUndoGrouping()
        let dirtyText = doc.text
        let wasEdited = doc.isDocumentEdited
        let modeBefore = doc.presentationMode
        doc.pendingEditingSelection = NSRange(location: 2, length: 1)

        try await coordinatedMove(from: src, to: dst)
        await waitForFileURL(dst, in: doc)
        XCTAssertEqual(doc.fileURL?.path, dst.path)
        XCTAssertEqual(doc.text, dirtyText)
        XCTAssertEqual(doc.bookmarks, bmBefore)
        XCTAssertTrue(store.containsRecord(for: dst))
        XCTAssertEqual(doc.renderingBaseURL?.path, dst.deletingLastPathComponent().path)
        XCTAssertEqual(doc.isDocumentEdited, wasEdited)
        XCTAssertEqual(doc.presentationMode, modeBefore)
        XCTAssertEqual(doc.pendingEditingSelection, NSRange(location: 2, length: 1))
        XCTAssertTrue(um.canUndo)
    }

    // MARK: - Deletion

    func testDeletionRetainsInMemoryAndDoesNotRecreate() async throws {
        let dir = try makeTempDir()
        let url = dir.appending(path: "del.md")
        let content = "# Title\n\nkeep"
        let (store, _) = try makeIsolatedStore()
        let doc = try makeDocument(text: content, fileURL: url, store: store)
        let outline = DocumentOutlineParser.outline(from: content)
        if let item = outline.first { doc.addBookmark(for: item, in: outline) }
        let bmBefore = doc.bookmarks
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        // Native coordinated deletion off MainActor — exercises NSDocument/NSFilePresenter path
        try await coordinatedDelete(at: url)
        // Allow presenter accommodation to deliver (bounded poll, no arbitrary long sleep)
        let deadline = Date().addingTimeInterval(2.0)
        while FileManager.default.fileExists(atPath: url.path) && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        // Even if file already gone, give presenter a short coalescing window
        try await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "native coordinated .forDeleting must complete and not leave file")
        XCTAssertEqual(doc.text, content, "must retain in-memory Markdown text after native deletion")
        XCTAssertEqual(doc.bookmarks, bmBefore, "bookmark record must remain")
        // Bookmark record must remain even if file bookmark data is temporarily unresolvable after deletion; verify via archive, not via path-primary lookup
        let archiveAfterDeletion = store.currentArchive()
        XCTAssertEqual(archiveAfterDeletion.documents.count, 1, "M8 bookmark archive must still contain 1 record after deletion")
        XCTAssertEqual(archiveAfterDeletion.documents.first?.bookmarks, bmBefore, "archived bookmarks must equal pre-deletion")
        XCTAssertEqual(archiveAfterDeletion.documents.first?.lastKnownPath, url.path, "lastKnownPath must still point to deleted path")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "deleted path must not be silently recreated")
        // Subsequent local editing remains dirty
        let um = try XCTUnwrap(doc.undoManager)
        um.groupsByEvent = false
        um.beginUndoGrouping()
        um.registerUndo(withTarget: doc) { t in t.replaceText(with: content) }
        doc.replaceText(with: content + " edited")
        doc.updateChangeCount(.changeDone)
        um.endUndoGrouping()
        XCTAssertTrue(doc.isDocumentEdited, "post-deletion edit must be dirty")
        XCTAssertTrue(um.canUndo)
        XCTAssertEqual(doc.text, content + " edited")
        // Recovery autosave elsewhere must not recreate the deleted real file
        let recovery = dir.appending(path: "recovery-del.md")
        try await save(doc, to: recovery, operation: .autosaveElsewhereOperation)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "autosave elsewhere must not recreate deleted file")
        XCTAssertTrue(FileManager.default.fileExists(atPath: recovery.path), "recovery file should exist")
        XCTAssertEqual(try String(contentsOf: recovery, encoding: .utf8), content + " edited")
        XCTAssertEqual(doc.fileURL?.path, url.path, "fileURL should still point to deleted path (not recovery)")
        XCTAssertFalse(store.containsRecord(for: recovery), "recovery URL must not become bookmark identity")
        // Document A deletion must not affect document B (instance-scoped state)
        let urlB = dir.appending(path: "delB.md")
        let contentB = "# BTitle\n\nkeep B"
        let docB = try makeDocument(text: contentB, fileURL: urlB, store: store)
        let outlineB = DocumentOutlineParser.outline(from: contentB)
        if let itemB = outlineB.first { docB.addBookmark(for: itemB, in: outlineB) }
        let bTextBefore = docB.text
        let bBookmarksBefore = docB.bookmarks
        let bEditedBefore = docB.isDocumentEdited
        // Delete A already done; verify B unaffected after a short window
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(docB.text, bTextBefore, "B text must be unaffected by A deletion")
        XCTAssertEqual(docB.bookmarks, bBookmarksBefore, "B bookmarks must be unaffected")
        XCTAssertEqual(docB.isDocumentEdited, bEditedBefore, "B dirty state unaffected")
        XCTAssertTrue(FileManager.default.fileExists(atPath: urlB.path), "B file must still exist")
        XCTAssertFalse(docB.hasPendingConflictForTesting(), "B must not inherit A conflict state")
    }

    // MARK: - Invalid UTF-8

    func testInvalidUTF8RetainsOldModel() async throws {
        let dir = try makeTempDir()
        let url = dir.appending(path: "invalid.md")
        let initial = "valid utf8"
        let (store, _) = try makeIsolatedStore()
        let doc = try makeDocument(text: initial, fileURL: url, store: store)
        let um = try XCTUnwrap(doc.undoManager)
        um.removeAllActions()
        XCTAssertFalse(doc.isDocumentEdited)
        try await coordinatedWriteInvalidBytes(Data([0xFF, 0xFE, 0xFD]), to: url)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(doc.text, initial)
        XCTAssertFalse(doc.isDocumentEdited)
        XCTAssertFalse(um.canUndo)
        let fresh = MarkdownDocument()
        XCTAssertThrowsError(try fresh.read(from: Data([0xFF, 0xFE, 0xFD]), ofType: MarkdownDocument.typeIdentifier))
    }

    // MARK: - Multi-document isolation

    func testMultiDocumentIsolation() async throws {
        let dir = try makeTempDir()
        let urlA = dir.appending(path: "a.md")
        let urlB = dir.appending(path: "b.md")
        let textA = "# Ahead\n\nA"
        let textB = "# Bhead\n\nB"
        let commonStore = DocumentBookmarkStore(archiveURL: dir.appending(path: "common.json"))
        let docA = try makeDocument(text: textA, fileURL: urlA, store: commonStore)
        let docB = try makeDocument(text: textB, fileURL: urlB, store: commonStore)
        docA.replaceText(with: "# Ahead\n\nA")
        docB.replaceText(with: "# Bhead\n\nB")
        let umB = try XCTUnwrap(docB.undoManager)
        umB.groupsByEvent = false
        umB.beginUndoGrouping()
        umB.registerUndo(withTarget: docB) { t in t.replaceText(with: "# Bhead\n\nB") }
        docB.replaceText(with: "# Bhead\n\nB dirty")
        docB.updateChangeCount(.changeDone)
        umB.endUndoGrouping()
        let bTextBefore = docB.text
        let bEditedBefore = docB.isDocumentEdited
        let bBookmarksBefore = docB.bookmarks
        let bSelBefore = docB.pendingEditingSelection

        let externalA = "A external"
        try await coordinatedWrite(externalA, to: urlA)
        try await waitForText(externalA, in: docA)
        XCTAssertEqual(docA.text, externalA)
        XCTAssertEqual(docB.text, bTextBefore)
        XCTAssertEqual(docB.isDocumentEdited, bEditedBefore)
        XCTAssertEqual(docB.bookmarks, bBookmarksBefore)
        XCTAssertEqual(docB.pendingEditingSelection, bSelBefore)
        XCTAssertFalse(docB.hasPendingConflictForTesting())
        XCTAssertTrue(umB.canUndo)
    }

    // MARK: - Save discrimination bookmarks

    func testSaveOperationDoesNotCloneForBackedDocument() async throws {
        let dir = try makeTempDir()
        let url = dir.appending(path: "save.md")
        let initial = "# H\n"
        let (store, _) = try makeIsolatedStore()
        let doc = try makeDocument(text: initial, fileURL: url, store: store)
        let outline = DocumentOutlineParser.outline(from: initial)
        if let item = outline.first { doc.addBookmark(for: item, in: outline) }
        let before = store.currentArchive()
        let um = try XCTUnwrap(doc.undoManager)
        um.groupsByEvent = false
        um.beginUndoGrouping()
        um.registerUndo(withTarget: doc) { t in t.replaceText(with: initial) }
        doc.replaceText(with: initial + "more")
        doc.updateChangeCount(.changeDone)
        um.endUndoGrouping()
        try await save(doc, to: url, operation: .saveOperation)
        XCTAssertEqual(store.currentArchive().documents.count, before.documents.count)
        XCTAssertEqual(doc.bookmarks, store.loadBookmarks(for: url))
    }

    func testSaveAsClonesBookmarksPreservesSource() async throws {
        let dir = try makeTempDir()
        let src = dir.appending(path: "src3.md")
        let dst = dir.appending(path: "dst3.md")
        let text = "# Title\n"
        let (store, _) = try makeIsolatedStore()
        let doc = try makeDocument(text: text, fileURL: src, store: store)
        let outline = DocumentOutlineParser.outline(from: text)
        if let item = outline.first { doc.addBookmark(for: item, in: outline) }
        let srcBookmarks = doc.bookmarks
        doc.replaceText(with: text + "local edit")
        let um = try XCTUnwrap(doc.undoManager)
        um.beginUndoGrouping()
        um.registerUndo(withTarget: doc) { t in t.replaceText(with: text) }
        doc.updateChangeCount(.changeDone)
        um.endUndoGrouping()
        let currentBM = doc.bookmarks
        try await save(doc, to: dst, operation: .saveAsOperation)
        XCTAssertTrue(store.containsRecord(for: src))
        XCTAssertTrue(store.containsRecord(for: dst))
        XCTAssertEqual(store.loadBookmarks(for: dst), currentBM)
        XCTAssertEqual(store.loadBookmarks(for: src), srcBookmarks)
    }

    func testSaveToHasNoBookmarkSideEffects() async throws {
        let dir = try makeTempDir()
        let src = dir.appending(path: "src4.md")
        let dst = dir.appending(path: "export.md")
        let text = "# H\n"
        let (store, _) = try makeIsolatedStore()
        let doc = try makeDocument(text: text, fileURL: src, store: store)
        let outline = DocumentOutlineParser.outline(from: text)
        if let item = outline.first { doc.addBookmark(for: item, in: outline) }
        let before = store.currentArchive()
        try await save(doc, to: dst, operation: .saveToOperation)
        XCTAssertEqual(store.currentArchive().documents, before.documents)
        XCTAssertEqual(doc.fileURL?.path, src.path)
    }

    func testAutosaveElsewhereNeverBecomesIdentity() async throws {
        let dir = try makeTempDir()
        let url = dir.appending(path: "never.md")
        let text = "# H\n"
        let (store, _) = try makeIsolatedStore()
        let doc = try makeDocument(text: text, fileURL: url, store: store)
        let beforeCount = store.allRecords().count
        let recovery = dir.appending(path: "recovery-id.md")
        let um = try XCTUnwrap(doc.undoManager)
        um.groupsByEvent = false
        um.beginUndoGrouping()
        um.registerUndo(withTarget: doc) { t in t.replaceText(with: text) }
        doc.replaceText(with: text + "x")
        doc.updateChangeCount(.changeDone)
        um.endUndoGrouping()
        try await save(doc, to: recovery, operation: .autosaveElsewhereOperation)
        XCTAssertFalse(store.containsRecord(for: recovery))
        XCTAssertEqual(store.allRecords().count, beforeCount)
        XCTAssertEqual(doc.fileURL?.path, url.path)
    }

    func testFailedSaveNoBookmarkMutation() async throws {
        let dir = try makeTempDir()
        let url = dir.appending(path: "fail.md")
        let text = "# H\n"
        let (store, _) = try makeIsolatedStore()
        let doc = try makeDocument(text: text, fileURL: url, store: store)
        let before = store.currentArchive()
        let badURL = URL(fileURLWithPath: "/nonexistent_dir_\(UUID().uuidString)/fail.md")
        do { try await save(doc, to: badURL, operation: .saveOperation); XCTFail() } catch {}
        XCTAssertEqual(store.currentArchive().documents, before.documents)
    }

    func testUndoReturningToCleanSchedulesReload() async throws {
        let dir = try makeTempDir()
        let url = dir.appending(path: "undoClean.md")
        let initial = "initial"
        let external = "external"
        let local = "local"
        let (store, _) = try makeIsolatedStore()
        let doc = try makeDirtyDocument(initialText: initial, editedText: local, fileURL: url, store: store)
        try await coordinatedWrite(external, to: url)
        await waitForPendingConflict(in: doc)
        let um = try XCTUnwrap(doc.undoManager)
        um.undo()
        try await waitForText(external, in: doc)
        XCTAssertEqual(doc.text, external)
        XCTAssertFalse(doc.hasPendingConflictForTesting())
    }

    func testTextViewSyncNoUndoOrDirty() throws {
        let doc = MarkdownDocument()
        let um = try XCTUnwrap(doc.undoManager)
        let view = MarkdownTextEditorScrollView()
        let coordinator = MarkdownTextView.Coordinator(document: doc)
        coordinator.connect(to: view.textView)
        defer { coordinator.disconnect() }
        doc.replaceText(with: "initial")
        coordinator.synchronizeTextView(with: doc.text)
        XCTAssertFalse(um.canUndo)
        XCTAssertFalse(doc.isDocumentEdited)
        doc.replaceText(with: "external via doc")
        coordinator.synchronizeTextView(with: doc.text)
        XCTAssertFalse(um.canUndo)
        XCTAssertEqual(view.textView.string, "external via doc")
    }

    func testSelectionClamping() async throws {
        let dir = try makeTempDir()
        let url = dir.appending(path: "clamp.md")
        let initial = "12345"
        let external = "12"
        let (store, _) = try makeIsolatedStore()
        let doc = try makeDocument(text: initial, fileURL: url, store: store)
        doc.presentationMode = .editing
        doc.pendingEditingSelection = NSRange(location: 10, length: 5)
        let editor = MarkdownTextEditorScrollView()
        let coordinator = MarkdownTextView.Coordinator(document: doc)
        coordinator.connect(to: editor.textView)
        defer { coordinator.disconnect() }
        editor.textView.string = initial
        editor.textView.setSelectedRange(NSRange(location: 10, length: 5))
        try await coordinatedWrite(external, to: url)
        try await waitForText(external, in: doc)
        let sel = try XCTUnwrap(doc.pendingEditingSelection)
        XCTAssertTrue(sel.location <= (external as NSString).length)
        XCTAssertTrue(sel.location + sel.length <= (external as NSString).length)
        coordinator.synchronizeTextView(with: doc.text)
        coordinator.restoreExternalSelection(sel)
        XCTAssertEqual(editor.textView.selectedRange.location, sel.location)
    }
}

private extension DocumentBookmarkResolver.Resolution {
    var isResolved: Bool { if case .resolved = self { return true }; return false }
    var isStale: Bool { if case .stale = self { return true }; return false }
}

// Test helper to set fileURL for unit tests without triggering M8 didSet (removed in M9)
private extension MarkdownDocument {
    func setFileURLForTesting(_ url: URL) {
        // Use NSDocument's fileURL setter directly; in M9 we removed didSet, so simple assignment
        self.fileURL = url
        // Load bookmarks for testing
        self.injectBookmarkStoreForTesting(self.bookmarkStore)
    }
}

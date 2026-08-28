import AppKit
import XCTest
@testable import Forksview

@MainActor
final class DocumentBookmarkTests: XCTestCase {

    // MARK: - Helpers

    private func makeOutline(from text: String) -> [DocumentOutlineItem] {
        DocumentOutlineParser.outline(from: text)
    }

    private func tempStore() throws -> (DocumentBookmarkStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let archiveURL = dir.appending(path: "Bookmarks.json")
        let store = DocumentBookmarkStore(archiveURL: archiveURL)
        return (store, dir)
    }

    private func createTempFile(at dir: URL, name: String, contents: String) throws -> URL {
        let url = dir.appending(path: name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    // 1. Codable round-trip and UUID identity.
    func testCodableRoundTripAndUUIDIdentity() throws {
        let target = HeadingBookmarkTarget(level: 2, title: "Installation", occurrence: 1, matchingHeadingCount: 1, sourceOffsetAtCreation: 42)
        let id = UUID()
        let bm = DocumentBookmark(id: id, target: target)
        let encoder = JSONEncoder()
        let data = try encoder.encode(bm)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DocumentBookmark.self, from: data)
        XCTAssertEqual(decoded, bm)
        XCTAssertEqual(decoded.id, id)
        // Different UUID should not equal
        let other = DocumentBookmark(id: UUID(), target: target)
        XCTAssertNotEqual(bm, other)
    }

    // 2. Unique heading resolution.
    func testUniqueHeadingResolution() {
        let md = "# Title\n\n## Installation\n\nContent\n## Other\n"
        let outline = makeOutline(from: md)
        XCTAssertEqual(outline.count, 3)
        let installation = outline[1]
        let bm = DocumentBookmark.make(for: installation, in: outline)
        let result = DocumentBookmarkResolver.resolve(bm, in: outline)
        if case let .resolved(item) = result {
            XCTAssertEqual(item, installation)
        } else {
            XCTFail("should resolve unique heading")
        }
    }

    // 3. Insertion above shifts resolved offset.
    func testInsertionAboveShiftsResolvedOffset() {
        let original = "## Installation\n\nBody\n"
        let outline1 = makeOutline(from: original)
        XCTAssertEqual(outline1.count, 1)
        let item1 = outline1[0]
        let bm = DocumentBookmark.make(for: item1, in: outline1)
        let loc1 = item1.sourceRange.location
        // Insert text above
        let modified = "Intro line\n\n" + original
        let outline2 = makeOutline(from: modified)
        XCTAssertEqual(outline2.count, 1)
        let item2 = outline2[0]
        XCTAssertNotEqual(item2.sourceRange.location, loc1)
        // Resolver should still resolve via fallback or exact? Our resolver first checks exact offset which will fail (offset changed), then fallback checks level+title with same matching count (1) and occurrence 1, so should resolve.
        let result = DocumentBookmarkResolver.resolve(bm, in: outline2)
        if case let .resolved(resolvedItem) = result {
            XCTAssertEqual(resolvedItem.title, "Installation")
            XCTAssertEqual(resolvedItem.sourceRange.location, item2.sourceRange.location)
        } else {
            XCTFail("should resolve after insertion above")
        }
    }

    // 4. Unique heading moved resolves.
    func testUniqueHeadingMoveResolves() {
        let md1 = "## Installation\n\nText\n\n## Other\n"
        let outline1 = makeOutline(from: md1)
        let installation = outline1.first(where: { $0.title == "Installation" })!
        let bm = DocumentBookmark.make(for: installation, in: outline1)
        // Move Installation to end
        let md2 = "## Other\n\nText\n\n## Installation\n"
        let outline2 = makeOutline(from: md2)
        let moved = outline2.first(where: { $0.title == "Installation" })!
        let result = DocumentBookmarkResolver.resolve(bm, in: outline2)
        if case let .resolved(item) = result {
            XCTAssertEqual(item, moved)
        } else {
            XCTFail("should resolve moved unique heading")
        }
    }

    // 5. Rename becomes stale.
    func testRenameBecomesStale() {
        let md1 = "## Installation\n"
        let outline1 = makeOutline(from: md1)
        let item = outline1[0]
        let bm = DocumentBookmark.make(for: item, in: outline1)
        let md2 = "## Installed\n"
        let outline2 = makeOutline(from: md2)
        let result = DocumentBookmarkResolver.resolve(bm, in: outline2)
        if case .stale = result {
            // expected
        } else {
            XCTFail("should be stale after rename")
        }
    }

    // 6. Deletion becomes stale.
    func testDeletionBecomesStale() {
        let md1 = "## Installation\n\n## Other\n"
        let outline1 = makeOutline(from: md1)
        let inst = outline1.first(where: { $0.title == "Installation" })!
        let bm = DocumentBookmark.make(for: inst, in: outline1)
        let md2 = "## Other\n"
        let outline2 = makeOutline(from: md2)
        let result = DocumentBookmarkResolver.resolve(bm, in: outline2)
        if case .stale = result {
        } else {
            XCTFail("should be stale after deletion")
        }
    }

    // 7. Duplicate occurrence resolution.
    func testDuplicateOccurrenceResolution() {
        let md = "## Installation\n\ntext\n\n## Installation\n"
        let outline = makeOutline(from: md)
        XCTAssertEqual(outline.count, 2)
        let first = outline[0]
        let second = outline[1]
        let bm1 = DocumentBookmark.make(for: first, in: outline)
        let bm2 = DocumentBookmark.make(for: second, in: outline)
        XCTAssertEqual(bm1.target.occurrence, 1)
        XCTAssertEqual(bm2.target.occurrence, 2)
        XCTAssertEqual(bm1.target.matchingHeadingCount, 2)
        XCTAssertEqual(bm2.target.matchingHeadingCount, 2)
        // Resolve each should go to correct occurrence
        if case let .resolved(r1) = DocumentBookmarkResolver.resolve(bm1, in: outline) {
            XCTAssertEqual(r1, first)
        } else { XCTFail("first duplicate should resolve") }
        if case let .resolved(r2) = DocumentBookmarkResolver.resolve(bm2, in: outline) {
            XCTAssertEqual(r2, second)
        } else { XCTFail("second duplicate should resolve") }
        // Ensure they remain independently bookmarkable (different IDs)
        XCTAssertNotEqual(bm1.id, bm2.id)
    }

    // 8. Changed duplicate cardinality becomes conservatively stale.
    func testChangedDuplicateCardinalityBecomesStale() {
        let md1 = "## Installation\n\n## Installation\n"
        let outline1 = makeOutline(from: md1)
        let first = outline1[0]
        let bm = DocumentBookmark.make(for: first, in: outline1)
        // Add another equal heading
        let md2 = "## Installation\n\n## Installation\n\n## Installation\n"
        let outline2 = makeOutline(from: md2)
        XCTAssertEqual(outline2.filter { $0.title == "Installation" }.count, 3)
        // Exact offset no longer resolves safely? Our first choice is exact offset + level + title: outline2 still has first heading at same offset 0? Actually offset 0 remains same for first heading, so it would resolve via exact. But spec says if another equal heading is added or removed and exact original offset no longer resolves safely, mark stale. However if exact offset still matches, it's valid per first choice. To make stale, we need to test case where exact offset fails and cardinality changed.
        // For conservative stale, we need scenario where exact offset fails: insertion above shifts offset, and cardinality changed.
        // So test insertion above + cardinality change makes stale.
        let inserted = "Intro\n\n## Installation\n\n## Installation\n\n## Installation\n"
        let outline3 = makeOutline(from: inserted)
        // Original bm had offset 0, but outline3 first Installation is at offset after Intro, so exact fails, then fallback checks cardinality (3 vs 2) -> stale
        let result = DocumentBookmarkResolver.resolve(bm, in: outline3)
        if case .stale = result {
            // expected stale
        } else {
            XCTFail("should be stale when cardinality changed and exact fails")
        }
        // Also test removal: remove one duplicate
        let md3 = "## Installation\n"
        let outline4 = makeOutline(from: md3)
        let result2 = DocumentBookmarkResolver.resolve(bm, in: outline4)
        // Exact would still resolve if first heading offset same (0), so not stale in that case. But fallback path with changed cardinality and exact failure would be stale.
        // To ensure conservative, test with shifted offset for md3 as well
        let shiftedMd3 = "Intro\n\n## Installation\n"
        let outline5 = makeOutline(from: shiftedMd3)
        let result3 = DocumentBookmarkResolver.resolve(bm, in: outline5)
        if case .stale = result3 {
        } else {
            XCTFail("should be stale when cardinality differs and exact offset shifted")
        }
    }

    // 9. Resolved source ordering.
    func testResolvedSourceOrdering() {
        let md = "## Zebra\n\n## Apple\n\n## Mango\n"
        let outline = makeOutline(from: md)
        XCTAssertEqual(outline.map(\.title), ["Zebra", "Apple", "Mango"])
        // Create bookmarks in creation order different from source order: bookmark Mango first, then Zebra
        let zebra = outline[0]
        let apple = outline[1]
        let mango = outline[2]
        let bmZebra = DocumentBookmark.make(for: zebra, in: outline)
        let bmApple = DocumentBookmark.make(for: apple, in: outline)
        let bmMango = DocumentBookmark.make(for: mango, in: outline)
        let bookmarks = [bmMango, bmZebra, bmApple] // creation out of order
        let ordered = DocumentBookmarkResolver.ordered(bookmarks, in: outline)
        XCTAssertEqual(ordered.map { $0.id }, [bmZebra.id, bmApple.id, bmMango.id], "should be source order")
    }

    // 10. Stale-at-end ordering.
    func testStaleAtEndOrdering() {
        let md1 = "## A\n\n## B\n\n## C\n"
        let outline1 = makeOutline(from: md1)
        let a = outline1[0]
        let b = outline1[1]
        let c = outline1[2]
        let bmA = DocumentBookmark.make(for: a, in: outline1)
        let bmB = DocumentBookmark.make(for: b, in: outline1)
        let bmC = DocumentBookmark.make(for: c, in: outline1)
        let bookmarks = [bmC, bmA, bmB] // shuffled
        // New outline where B is deleted (so bmB stale), others resolved
        let md2 = "## A\n\n## C\n"
        let outline2 = makeOutline(from: md2)
        let ordered = DocumentBookmarkResolver.ordered(bookmarks, in: outline2)
        // Resolved: A, C in source order; stale: B at end
        XCTAssertEqual(ordered.count, 3)
        // First two should be resolved
        let firstTwo = Array(ordered.prefix(2))
        XCTAssertTrue(firstTwo.contains(where: { $0.id == bmA.id }))
        XCTAssertTrue(firstTwo.contains(where: { $0.id == bmC.id }))
        // Last should be stale B
        XCTAssertEqual(ordered.last?.id, bmB.id)
        // Stale ordering by captured source offset, then UUID tie-breaking
        // Test stale ordering deterministic: create two stale with same offset? Need UUID tie-break
        let stale1 = DocumentBookmark(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, target: HeadingBookmarkTarget(level: 2, title: "X", occurrence: 1, matchingHeadingCount: 1, sourceOffsetAtCreation: 100))
        let stale2 = DocumentBookmark(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, target: HeadingBookmarkTarget(level: 2, title: "Y", occurrence: 1, matchingHeadingCount: 1, sourceOffsetAtCreation: 100))
        let staleBookmarks = [stale2, stale1]
        let emptyOutline: [DocumentOutlineItem] = []
        let orderedStale = DocumentBookmarkResolver.ordered(staleBookmarks, in: emptyOutline)
        XCTAssertEqual(orderedStale.map(\.id), [stale1.id, stale2.id], "UUID tie-breaker should order deterministically")
    }

    // 11. Toggle/add prevents duplicate bookmark for same resolved heading.
    func testToggleAddPreventsDuplicate() {
        let doc = MarkdownDocument()
        let md = "## Installation\n"
        doc.replaceText(with: md)
        let outline = makeOutline(from: md)
        let item = outline[0]
        XCTAssertEqual(doc.bookmarks.count, 0)
        doc.addBookmark(for: item, in: outline)
        XCTAssertEqual(doc.bookmarks.count, 1)
        // Adding same heading again should not duplicate
        doc.addBookmark(for: item, in: outline)
        XCTAssertEqual(doc.bookmarks.count, 1)
        // Toggle should remove
        doc.toggleBookmark(for: item, in: outline)
        XCTAssertEqual(doc.bookmarks.count, 0)
        // Toggle again should add
        doc.toggleBookmark(for: item, in: outline)
        XCTAssertEqual(doc.bookmarks.count, 1)
        // Duplicate same-title headings remain independently bookmarkable already tested in resolver, but test via document as well
        let dupMD = "## Installation\n\n## Installation\n"
        doc.replaceText(with: dupMD)
        let dupOutline = makeOutline(from: dupMD)
        XCTAssertEqual(dupOutline.count, 2)
        // Clear bookmarks
        doc.removeBookmark(id: doc.bookmarks.first!.id)
        XCTAssertEqual(doc.bookmarks.count, 0)
        doc.addBookmark(for: dupOutline[0], in: dupOutline)
        doc.addBookmark(for: dupOutline[1], in: dupOutline)
        XCTAssertEqual(doc.bookmarks.count, 2)
        // Ensure resolver distinguishes them
        XCTAssertTrue(DocumentBookmarkResolver.isBookmarked(item: dupOutline[0], bookmarks: doc.bookmarks, outline: dupOutline))
        XCTAssertTrue(DocumentBookmarkResolver.isBookmarked(item: dupOutline[1], bookmarks: doc.bookmarks, outline: dupOutline))
    }

    // 12. Add/remove do not modify Markdown text.
    func testAddRemoveDoNotModifyText() {
        let doc = MarkdownDocument()
        let md = "# Title\n\n## Section\n"
        doc.replaceText(with: md)
        let outline = makeOutline(from: md)
        let item = outline[1]
        let before = doc.text
        doc.addBookmark(for: item, in: outline)
        XCTAssertEqual(doc.text, before)
        doc.removeBookmark(for: item, in: outline)
        XCTAssertEqual(doc.text, before)
        doc.toggleBookmark(for: item, in: outline)
        XCTAssertEqual(doc.text, before)
        doc.toggleBookmark(for: item, in: outline)
        XCTAssertEqual(doc.text, before)
    }

    // 13. Add/remove do not affect document dirty/change count.
    func testAddRemoveDoNotAffectDirty() throws {
        let doc = MarkdownDocument()
        // Ensure clean
        XCTAssertFalse(doc.isDocumentEdited)
        let md = "# Title\n"
        doc.replaceText(with: md) // This will make dirty? But replaceText doesn't call updateChangeCount directly; need to check dirty via isDocumentEdited after replace? In earlier tests, replaceText without undoManager does not automatically set dirty? Actually isDocumentEdited reflects changeCount, which is updated via updateChangeCount(.changeDone) when text edited via NSDocument? But replaceText alone may set isDocumentEdited true? Let's check baseline: In earlier tests, after replaceText, isDocumentEdited became true when undo grouping. But for clean doc, we need to start from clean state: after init, isDocumentEdited false, after read, false. We'll use document created via read to be clean.
        let cleanDoc = MarkdownDocument()
        try cleanDoc.read(from: Data("# A\n".utf8), ofType: MarkdownDocument.typeIdentifier)
        XCTAssertFalse(cleanDoc.isDocumentEdited)
        let outline = makeOutline(from: cleanDoc.text)
        XCTAssertEqual(outline.count, 1)
        let item = outline[0]
        cleanDoc.addBookmark(for: item, in: outline)
        XCTAssertFalse(cleanDoc.isDocumentEdited, "add bookmark must not set dirty")
        cleanDoc.removeBookmark(for: item, in: outline)
        XCTAssertFalse(cleanDoc.isDocumentEdited, "remove bookmark must not set dirty")
        // Also test after toggle
        cleanDoc.toggleBookmark(for: item, in: outline)
        XCTAssertFalse(cleanDoc.isDocumentEdited)
        cleanDoc.toggleBookmark(for: item, in: outline)
        XCTAssertFalse(cleanDoc.isDocumentEdited)
        // Ensure updateChangeCount not called: isDocumentEdited remains false after multiple ops
    }

    // 14. Add/remove do not pollute native text Undo.
    func testAddRemoveDoNotPolluteUndo() throws {
        let doc = MarkdownDocument()
        let um = try XCTUnwrap(doc.undoManager)
        um.groupsByEvent = false
        // Start clean
        doc.replaceText(with: "# Initial\n")
        um.removeAllActions()
        XCTAssertFalse(um.canUndo)
        let outline = makeOutline(from: doc.text)
        let item = outline[0]
        // Bookmark ops should not register undo
        doc.addBookmark(for: item, in: outline)
        XCTAssertFalse(um.canUndo, "bookmark add should not pollute undo")
        doc.removeBookmark(for: item, in: outline)
        XCTAssertFalse(um.canUndo)
        // Now do a text edit with undo
        um.beginUndoGrouping()
        replaceText("changed", in: doc, registeringWith: um)
        um.endUndoGrouping()
        XCTAssertTrue(um.canUndo)
        let canUndoBefore = um.canUndo
        // Bookmark ops after text edit should not affect undo stack depth
        doc.addBookmark(for: item, in: makeOutline(from: doc.text))
        XCTAssertEqual(um.canUndo, canUndoBefore)
        doc.removeBookmark(id: doc.bookmarks.first!.id)
        XCTAssertEqual(um.canUndo, canUndoBefore)
        // Undo should revert text, not bookmarks
        um.undo()
        XCTAssertEqual(doc.text, "# Initial\n")
        // Bookmarks should remain as before undo? Actually we removed bookmark after adding, so bookmarks empty. Undo shouldn't affect bookmarks.
        XCTAssertEqual(doc.bookmarks.count, 0)
    }

    // 15. Version 1 archive round-trip.
    func testVersion1ArchiveRoundTrip() throws {
        let target = HeadingBookmarkTarget(level: 1, title: "Title", occurrence: 1, matchingHeadingCount: 1, sourceOffsetAtCreation: 0)
        let bm = DocumentBookmark(id: UUID(), target: target)
        // Create archive with dummy bookmark data (need file URL for real data, but for round-trip test we can use empty Data and stub)
        let dummyData = Data([0,1,2,3])
        let record = PersistedDocumentBookmarks(id: UUID(), fileBookmarkData: dummyData, lastKnownPath: "/tmp/foo.md", bookmarks: [bm])
        let archive = BookmarkArchive(schemaVersion: 1, documents: [record])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(archive)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(BookmarkArchive.self, from: data)
        XCTAssertEqual(decoded, archive)
        XCTAssertEqual(decoded.schemaVersion, 1)
        // Also test store helper
        XCTAssertTrue(DocumentBookmarkStore.archiveRoundtrip(archive))
    }

    // 16. Atomic store reload.
    func testAtomicStoreReload() throws {
        let (store, dir) = try tempStore()
        let archiveURL = dir.appending(path: "Bookmarks.json")
        // Create a file and add bookmarks via store
        let fileURL = try createTempFile(at: dir, name: "doc.md", contents: "# Title\n")
        let outline = makeOutline(from: "# Title\n")
        let item = outline[0]
        let bm = DocumentBookmark.make(for: item, in: outline)
        store.saveBookmarks([bm], for: fileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))
        // Create second store reading same file
        let store2 = DocumentBookmarkStore(archiveURL: archiveURL)
        XCTAssertEqual(store2.loadBookmarks(for: fileURL), [bm])
        // Modify via store, then reload first store
        let bm2 = DocumentBookmark(id: UUID(), target: HeadingBookmarkTarget(level: 1, title: "Title", occurrence: 1, matchingHeadingCount: 1, sourceOffsetAtCreation: 0))
        store.saveBookmarks([bm, bm2], for: fileURL)
        // Each load refreshes from disk so separate document/store instances
        // observe mutations made by another open document.
        XCTAssertEqual(store2.loadBookmarks(for: fileURL).count, 2)
        store2.reload()
        XCTAssertEqual(store2.loadBookmarks(for: fileURL).count, 2)
    }

    // 17. File rename/move locator resolution via Foundation URL bookmarks.
    func testFileRenameMoveLocatorResolution() throws {
        let (store, dir) = try tempStore()
        let fileURL = try createTempFile(at: dir, name: "original.md", contents: "# Title\n\n## Section\n")
        let outline = makeOutline(from: "# Title\n\n## Section\n")
        let section = outline[1]
        let bm = DocumentBookmark.make(for: section, in: outline)
        store.saveBookmarks([bm], for: fileURL)
        XCTAssertEqual(store.loadBookmarks(for: fileURL).count, 1)
        // Rename file
        let renamedURL = dir.appending(path: "renamed.md")
        try FileManager.default.moveItem(at: fileURL, to: renamedURL)
        let movedDirectory = dir.appending(path: "moved", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: movedDirectory, withIntermediateDirectories: true)
        let movedURL = movedDirectory.appending(path: "moved.md")
        try FileManager.default.moveItem(at: renamedURL, to: movedURL)

        // The record must resolve through the Foundation bookmark data, not the
        // diagnostic lastKnownPath fallback.
        XCTAssertEqual(store.loadBookmarks(for: movedURL), [bm])
        XCTAssertEqual(store.allRecords().count, 1)
        XCTAssertEqual(store.allRecords().first?.lastKnownPath, movedURL.path)
        let resolved = DocumentBookmarkStore.resolveBookmarkData(store.allRecords()[0].fileBookmarkData)
        XCTAssertEqual(resolved.url?.standardizedFileURL.path, movedURL.standardizedFileURL.path)
    }

    // 18. Separate document records remain isolated.
    func testSeparateDocumentRecordsRemainIsolated() throws {
        let (store, dir) = try tempStore()
        let fileA = try createTempFile(at: dir, name: "a.md", contents: "# A\n\n## SectionA\n")
        let fileB = try createTempFile(at: dir, name: "b.md", contents: "# B\n\n## SectionB\n")
        let outlineA = makeOutline(from: "# A\n\n## SectionA\n")
        let outlineB = makeOutline(from: "# B\n\n## SectionB\n")
        let bmA = DocumentBookmark.make(for: outlineA[1], in: outlineA)
        let bmB = DocumentBookmark.make(for: outlineB[1], in: outlineB)
        store.saveBookmarks([bmA], for: fileA)
        store.saveBookmarks([bmB], for: fileB)
        XCTAssertEqual(store.loadBookmarks(for: fileA), [bmA])
        XCTAssertEqual(store.loadBookmarks(for: fileB), [bmB])
        // Ensure isolation: modifying A doesn't affect B
        let bmA2 = DocumentBookmark.make(for: outlineA[0], in: outlineA)
        store.saveBookmarks([bmA, bmA2], for: fileA)
        XCTAssertEqual(store.loadBookmarks(for: fileA).count, 2)
        XCTAssertEqual(store.loadBookmarks(for: fileB).count, 1)
        // Test document isolation: two MarathonDocument instances have independent bookmarks
        let doc1 = MarkdownDocument()
        let doc2 = MarkdownDocument()
        // Use same store factory for both via injection
        doc1.injectBookmarkStoreForTesting(store)
        doc2.injectBookmarkStoreForTesting(DocumentBookmarkStore(archiveURL: store.archiveURL))
        // Set fileURLs via save? For unit isolation, we can directly set fileURL via save simulation: create temp files and load
        // But easier: test that bookmarks arrays are independent
        doc1.replaceText(with: "# A\n\n## SectionA\n")
        // Simulate loading from fileA
        doc1.injectBookmarkStoreForTesting(store)
        // Manually set fileURL via private method? We can use save to set fileURL: use temp file
        // Instead test directly that adding bookmark to doc1 doesn't affect doc2's bookmarks
        let outlineDoc1 = makeOutline(from: doc1.text)
        doc1.addBookmark(for: outlineDoc1[0], in: outlineDoc1)
        XCTAssertEqual(doc1.bookmarks.count, 1)
        XCTAssertEqual(doc2.bookmarks.count, 0, "second doc should remain isolated")
    }

    // 19. Save As clone semantics.
    func testSaveAsCloneSemantics() throws {
        let (store, dir) = try tempStore()
        let sourceURL = try createTempFile(at: dir, name: "source.md", contents: "# Source\n\n## Sec\n")
        let destURL = dir.appending(path: "dest.md")
        // Create dest file empty first
        try Data("".utf8).write(to: destURL)
        let outline = makeOutline(from: "# Source\n\n## Sec\n")
        let bm = DocumentBookmark.make(for: outline[1], in: outline)
        store.saveBookmarks([bm], for: sourceURL)
        XCTAssertEqual(store.loadBookmarks(for: sourceURL).count, 1)
        XCTAssertEqual(store.loadBookmarks(for: destURL).count, 0)
        // Simulate Save As
        store.handleSaveAs(from: sourceURL, to: destURL)
        XCTAssertEqual(store.loadBookmarks(for: sourceURL).count, 1, "original keeps")
        XCTAssertEqual(store.loadBookmarks(for: destURL).count, 1, "destination gets clone")
        XCTAssertEqual(store.loadBookmarks(for: destURL).first?.target.title, "Sec")
        // Ensure IDs are same? Clone should copy same bookmarks (including UUID) per spec's "cloned bookmark set" - implies same bookmarks cloned
        XCTAssertEqual(store.loadBookmarks(for: destURL).first?.id, bm.id)
        // Ensure original record not deleted, and dest is separate record (different PersistedDocumentBookmarks id)
        let records = store.allRecords()
        XCTAssertEqual(records.count, 2)
        XCTAssertNotEqual(records[0].id, records[1].id)
    }

    // 20. Unresolvable persisted record cannot attach to an unrelated file.
    func testUnresolvablePersistedRecordCannotAttachToUnrelatedFile() throws {
        let (store, dir) = try tempStore()
        let fileA = try createTempFile(at: dir, name: "a.md", contents: "# A\n")
        let outlineA = makeOutline(from: "# A\n")
        let bmA = DocumentBookmark.make(for: outlineA[0], in: outlineA)
        store.saveBookmarks([bmA], for: fileA)
        // Create unrelated file B
        let fileB = try createTempFile(at: dir, name: "b.md", contents: "# B\n")
        // Manually craft a record with bookmark data for fileA but try to attach to fileB via path fallback should not happen
        // Store's loadBookmarks(for: fileB) should return empty, not bmA, because path is not primary identity
        let loadedB = store.loadBookmarks(for: fileB)
        XCTAssertEqual(loadedB.count, 0, "unrelated file should not inherit bookmarks via path")
        // Even if we corrupt bookmark data for fileA to be unresolvable, it should not attach to B
        // Simulate by creating a new store with a record that has invalid bookmarkData but lastKnownPath == fileA path
        let badData = Data([0xFF, 0x00, 0x01])
        let badRecord = PersistedDocumentBookmarks(id: UUID(), fileBookmarkData: badData, lastKnownPath: fileA.path, bookmarks: [bmA])
        var archive = store.currentArchive()
        archive.documents.append(badRecord)
        // Persist this bad record via direct file write? Instead test via store that contains bad record: create new store with injected archive that includes bad record
        let dir2 = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir2, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir2) }
        let archiveURL2 = dir2.appending(path: "Bookmarks2.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(archive)
        try data.write(to: archiveURL2, options: [.atomic])
        let store2 = DocumentBookmarkStore(archiveURL: archiveURL2)
        let loadedB2 = store2.loadBookmarks(for: fileB)
        XCTAssertEqual(loadedB2.count, 0, "bad record should not attach to unrelated file")
        // Also ensure fileA's good record still loads
        let loadedA = store2.loadBookmarks(for: fileA)
        // Should still find the good record (first one) for fileA, not the bad one
        XCTAssertTrue(loadedA.contains(where: { $0.id == bmA.id }))
    }

    // 21. Corrupt/unsupported archives remain untouched while bookmarks work for the session.
    func testCorruptOrUnsupportedArchiveIsPreservedAndSessionOnly() throws {
        let dir = try makeTemporaryDirectoryForTest()
        let archiveURL = dir.appending(path: "Bookmarks.json")
        let fileURL = try createTempFile(at: dir, name: "session.md", contents: "# Session\n")
        let outline = makeOutline(from: "# Session\n")
        let bookmark = DocumentBookmark.make(for: outline[0], in: outline)

        let corruptBytes = Data("not-json".utf8)
        try corruptBytes.write(to: archiveURL)
        let corruptStore = DocumentBookmarkStore(archiveURL: archiveURL)
        corruptStore.saveBookmarks([bookmark], for: fileURL)
        XCTAssertEqual(corruptStore.loadBookmarks(for: fileURL), [bookmark])
        XCTAssertEqual(try Data(contentsOf: archiveURL), corruptBytes, "session mutations must not overwrite corrupt archive")

        let unsupportedArchive = BookmarkArchive(schemaVersion: 999, documents: [])
        let unsupportedBytes = try JSONEncoder().encode(unsupportedArchive)
        try unsupportedBytes.write(to: archiveURL)
        let unsupportedStore = DocumentBookmarkStore(archiveURL: archiveURL)
        unsupportedStore.saveBookmarks([bookmark], for: fileURL)
        XCTAssertEqual(unsupportedStore.loadBookmarks(for: fileURL), [bookmark])
        XCTAssertEqual(try Data(contentsOf: archiveURL), unsupportedBytes, "session mutations must not overwrite unsupported archive")
    }

    // 22. Untitled bookmarks do not create a phantom record and bind on first save.
    func testUntitledBookmarksBindOnFirstSave() async throws {
        let (store, dir) = try tempStore()
        let destinationURL = dir.appending(path: "first-save.md")
        let document = MarkdownDocument()
        document.injectBookmarkStoreForTesting(store)
        document.replaceText(with: "# First Save\n")
        let outline = makeOutline(from: document.text)

        document.addBookmark(for: outline[0], in: outline)
        let bookmark = try XCTUnwrap(document.bookmarks.first)
        XCTAssertNil(document.fileURL)
        XCTAssertTrue(store.allRecords().isEmpty, "untitled session bookmarks must not create a record")

        try await save(document, to: destinationURL)
        XCTAssertEqual(document.fileURL?.standardizedFileURL, destinationURL.standardizedFileURL)
        XCTAssertEqual(document.bookmarks, [bookmark])
        XCTAssertEqual(store.loadBookmarks(for: destinationURL), [bookmark])
        XCTAssertEqual(store.allRecords().count, 1)
    }

    // 23. Ordinary save keeps one binding; Save As clones without moving the source record.
    func testSaveAsLifecycleOrderingAndCloneSemantics() async throws {
        let (store, dir) = try tempStore()
        let sourceURL = try createTempFile(at: dir, name: "source-lifecycle.md", contents: "# Source\n\n## Section\n")
        let destinationURL = dir.appending(path: "destination-lifecycle.md")
        let document = try MarkdownDocument(contentsOf: sourceURL, ofType: MarkdownDocument.typeIdentifier)
        document.injectBookmarkStoreForTesting(store)
        let sourceOutline = makeOutline(from: document.text)
        document.addBookmark(for: sourceOutline[1], in: sourceOutline)
        let bookmark = try XCTUnwrap(document.bookmarks.first)

        try await save(document, to: sourceURL, operation: .saveOperation)
        XCTAssertEqual(store.allRecords().count, 1, "ordinary save must not clone the record")
        XCTAssertEqual(store.loadBookmarks(for: sourceURL), [bookmark])

        try await save(document, to: destinationURL, operation: .saveAsOperation)
        XCTAssertEqual(document.fileURL?.standardizedFileURL, destinationURL.standardizedFileURL)
        XCTAssertEqual(document.bookmarks, [bookmark])
        XCTAssertEqual(store.loadBookmarks(for: sourceURL), [bookmark], "Save As must retain source record")
        XCTAssertEqual(store.loadBookmarks(for: destinationURL), [bookmark], "Save As must clone current bookmarks")
        XCTAssertEqual(store.allRecords().count, 2)
    }

    // MARK: - Helpers for undo test

    private func replaceText(
        _ newText: String,
        in document: MarkdownDocument,
        registeringWith undoManager: UndoManager
    ) {
        let previousText = document.text
        undoManager.registerUndo(withTarget: document) { [weak self, weak undoManager] target in
            guard let self, let undoManager else { return }
            self.replaceText(previousText, in: target, registeringWith: undoManager)
        }
        document.replaceText(with: newText)
    }

    private func makeTemporaryDirectoryForTest() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
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
}

private extension BookmarkArchive {
    // Needed for test 15 helper? Already Equatable
}

import XCTest

@MainActor
final class DocumentBookmarkUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    private func makeApplication() -> XCUIApplication {
        XCUIApplication(url: targetApplicationURL)
    }

    private func makeApplicationWithIsolatedStore(storeURL: URL) -> XCUIApplication {
        let app = makeApplication()
        app.launchEnvironment["FORKSVIEW_BOOKMARK_ARCHIVE_PATH"] = storeURL.path
        app.launchEnvironment["FORKSVIEW_BOOKMARKS_PATH"] = storeURL.path
        return app
    }

    private var targetApplicationURL: URL {
        Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appending(path: "Forksview.app", directoryHint: .isDirectory)
    }

    private func readingView(in app: XCUIApplication) -> XCUIElement {
        app.scrollViews["markdownReadingView"]
    }

    private func inspector(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["documentInspector"]
    }

    private func outline(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["documentOutline"]
    }

    private func bookmarksSection(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["bookmarksSection"]
    }

    private func bookmarksContainer(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["documentBookmarks"]
    }

    private func emptyState(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["documentBookmarksEmptyState"]
    }

    private func bookmarkToggles(in app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "documentBookmarkToggle-"))
    }

    private func bookmarkItems(in app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "documentBookmarkItem-"))
    }

    private func removeButtons(in app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "removeDocumentBookmark-"))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func waitForWindowCount(_ count: Int, in app: XCUIApplication) {
        let predicate = NSPredicate(format: "count == %d", count)
        expectation(for: predicate, evaluatedWith: app.windows)
        waitForExpectations(timeout: 5)
    }

    // MARK: - 1. Empty → add → remove

    func testEmptyAddRemove() throws {
        let dir = try makeTemporaryDirectory()
        let url = dir.appending(path: "bookmarks.md")
        let md = "# Title\n\n## Installation\n\nBody\n\n## Usage\n\nMore\n"
        try Data(md.utf8).write(to: url)
        let storeURL = dir.appending(path: "Bookmarks.json")
        let app = makeApplicationWithIsolatedStore(storeURL: storeURL)
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", url.path]
        app.launch()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(inspector(in: app).waitForExistence(timeout: 2))
        XCTAssertTrue(bookmarksSection(in: app).waitForExistence(timeout: 2))
        XCTAssertTrue(emptyState(in: app).waitForExistence(timeout: 2), "initially No bookmarks yet")
        XCTAssertEqual(removeButtons(in: app).count, 0)
        XCTAssertTrue(bookmarkToggles(in: app).count >= 2, "each heading should have a toggle")

        // Add bookmark via first heading toggle
        let firstToggle = bookmarkToggles(in: app).firstMatch
        XCTAssertTrue(firstToggle.waitForExistence(timeout: 2))
        XCTAssertTrue(firstToggle.label.contains("Add bookmark"))
        firstToggle.click()
        Thread.sleep(forTimeInterval: 0.5)
        // Empty state should disappear, bookmark row appears
        XCTAssertFalse(emptyState(in: app).exists, "after add, empty state should disappear")
        XCTAssertTrue(bookmarksContainer(in: app).waitForExistence(timeout: 2))
        XCTAssertEqual(bookmarkItems(in: app).count, 1, "one bookmark row should appear")
        XCTAssertEqual(removeButtons(in: app).count, 1)

        // Toggle should now be filled/bookmarked
        // Wait a bit and check value
        Thread.sleep(forTimeInterval: 0.3)
        let togglesAfter = bookmarkToggles(in: app)
        // At least one toggle should be bookmarked
        let bookmarkedFound = togglesAfter.allElementsBoundByIndex.contains { $0.value as? String == "Bookmarked" }
        XCTAssertTrue(bookmarkedFound, "toggle should expose Bookmarked value")

        // Remove via remove button
        let remove = removeButtons(in: app).firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 2))
        remove.click()
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertTrue(emptyState(in: app).waitForExistence(timeout: 2), "after remove, empty state returns")
        XCTAssertEqual(removeButtons(in: app).count, 0)
        XCTAssertEqual(bookmarkItems(in: app).count, 0)
    }

    // MARK: - 2. Reading navigation

    func testReadingNavigation() throws {
        let dir = try makeTemporaryDirectory()
        let url = dir.appending(path: "readnav.md")
        var md = "# Top\n\n"
        for i in 1...20 { md += "Block \(i)\n\n" }
        md += "## Target Heading\n\nTarget body\n\n"
        for i in 21...40 { md += "Block \(i)\n\n" }
        try Data(md.utf8).write(to: url)
        let storeURL = dir.appending(path: "Bookmarks.json")
        let app = makeApplicationWithIsolatedStore(storeURL: storeURL)
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", url.path]
        app.launch()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        // Add bookmark
        let toggle = bookmarkToggles(in: app).firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 2))
        toggle.click()
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertEqual(bookmarkItems(in: app).count, 1)
        let bookmarkItem = bookmarkItems(in: app).firstMatch
        XCTAssertTrue(bookmarkItem.waitForExistence(timeout: 2))
        // Should be in reading mode
        XCTAssertTrue(readingView(in: app).exists)
        XCTAssertFalse(app.textViews["markdownTextEditor"].isHittable)
        // Click bookmark navigation
        bookmarkItem.click()
        Thread.sleep(forTimeInterval: 0.8)
        // Still in reading mode after bookmark navigation
        XCTAssertTrue(readingView(in: app).exists, "should remain in reading after bookmark navigation")
        XCTAssertFalse(app.textViews["markdownTextEditor"].isHittable, "should not switch to editing")
    }

    // MARK: - 3. Editing navigation

    func testEditingNavigation() throws {
        let dir = try makeTemporaryDirectory()
        let url = dir.appending(path: "editnav.md")
        let md = "# Top\n\n## Section One\n\nContent\n\n## Section Two\n\nMore content\n"
        try Data(md.utf8).write(to: url)
        let storeURL = dir.appending(path: "Bookmarks.json")
        let app = makeApplicationWithIsolatedStore(storeURL: storeURL)
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", url.path]
        app.launch()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        // Add bookmark for Section Two
        let toggles = bookmarkToggles(in: app)
        XCTAssertTrue(toggles.count >= 2)
        // Find toggle for Section Two (second heading's toggle)
        let outlineButtons = outline(in: app).buttons
        XCTAssertTrue(outlineButtons.count >= 2)
        // Use second outline toggle (corresponds to Section Two)
        let secondToggle = toggles.element(boundBy: 1)
        XCTAssertTrue(secondToggle.waitForExistence(timeout: 2))
        secondToggle.click()
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertEqual(bookmarkItems(in: app).count, 1, "bookmark should exist")
        // Switch to editing
        app.buttons["togglePresentationModeButton"].click()
        let editor = app.textViews["markdownTextEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.click()
        // Bookmark navigation while editing
        let bookmarkItem = bookmarkItems(in: app).firstMatch
        XCTAssertTrue(bookmarkItem.waitForExistence(timeout: 2))
        bookmarkItem.click()
        Thread.sleep(forTimeInterval: 0.5)
        // Should remain in editing, editor hittable, reading not hittable
        XCTAssertTrue(editor.waitForExistence(timeout: 2))
        XCTAssertTrue(editor.isHittable, "should preserve editing mode and focus")
        XCTAssertFalse(readingView(in: app).isHittable)
        // Verify typing works at new location (caret moved to heading)
        editor.typeText(" EDITED")
        XCTAssertTrue((editor.value as? String)?.contains("EDITED") == true)
        XCTAssertTrue((editor.value as? String)?.contains("Section Two") == true)
    }

    // MARK: - 4. Duplicate headings

    func testDuplicateHeadings() throws {
        let dir = try makeTemporaryDirectory()
        let url = dir.appending(path: "dup.md")
        let md = "## Installation\n\nFirst\n\n## Installation\n\nSecond\n\n## Other\n"
        try Data(md.utf8).write(to: url)
        let storeURL = dir.appending(path: "Bookmarks.json")
        let app = makeApplicationWithIsolatedStore(storeURL: storeURL)
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", url.path]
        app.launch()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        let toggles = bookmarkToggles(in: app)
        XCTAssertEqual(toggles.count, 3, "3 headings => 3 toggles")
        let labels = toggles.allElementsBoundByIndex.map { $0.label }
        // First two should contain Installation with occurrence
        XCTAssertTrue(labels[0].contains("Installation"))
        XCTAssertTrue(labels[0].contains("heading level 2"))
        XCTAssertTrue(labels[0].contains("1 of 2"), "first dup label \(labels[0]) should contain 1 of 2")
        XCTAssertTrue(labels[1].contains("2 of 2"), "second dup label \(labels[1]) should contain 2 of 2")
        // Independently bookmarkable
        toggles.element(boundBy: 0).click()
        Thread.sleep(forTimeInterval: 0.4)
        toggles.element(boundBy: 1).click()
        Thread.sleep(forTimeInterval: 0.4)
        XCTAssertEqual(bookmarkItems(in: app).count, 2, "both duplicates independently bookmarkable")
        let bookmarkLabels = bookmarkItems(in: app).allElementsBoundByIndex.map { $0.label }
        XCTAssertTrue(bookmarkLabels[0].contains("1 of 2") || bookmarkLabels[1].contains("1 of 2"))
        XCTAssertTrue(bookmarkLabels[0].contains("2 of 2") || bookmarkLabels[1].contains("2 of 2"))
        // Verify toggles both show Bookmarked
        let bookmarkedCount = toggles.allElementsBoundByIndex.filter { ($0.value as? String) == "Bookmarked" }.count
        XCTAssertEqual(bookmarkedCount, 2)
    }

    // MARK: - 5. Stale

    func testStaleBookmark() throws {
        let dir = try makeTemporaryDirectory()
        let url = dir.appending(path: "stale.md")
        let md = "## Installation\n\nBody\n\n## Usage\n"
        try Data(md.utf8).write(to: url)
        let storeURL = dir.appending(path: "Bookmarks.json")
        let app = makeApplicationWithIsolatedStore(storeURL: storeURL)
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", url.path]
        app.launch()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        // Bookmark Installation
        let firstToggle = bookmarkToggles(in: app).firstMatch
        XCTAssertTrue(firstToggle.waitForExistence(timeout: 2))
        firstToggle.click()
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertEqual(bookmarkItems(in: app).count, 1)
        let bookmarkItem = bookmarkItems(in: app).firstMatch
        XCTAssertTrue(bookmarkItem.isEnabled, "initially resolved should be enabled")
        // Rename heading via editor
        app.buttons["togglePresentationModeButton"].click()
        let editor = app.textViews["markdownTextEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.click()
        app.typeKey("a", modifierFlags: .command)
        // Type renamed content
        editor.typeText("## Installed\n\nBody\n\n## Usage\n")
        // Wait for outline to update
        Thread.sleep(forTimeInterval: 0.8)
        // Go back to reading to see stale? But stale visible in both modes (inspector always visible)
        // Check bookmark now stale: navigation disabled, shows unavailable, but remove enabled
        // Need to wait for inspector to reflect stale
        let staleItem = bookmarkItems(in: app).firstMatch
        XCTAssertTrue(staleItem.waitForExistence(timeout: 3))
        // Stale item should be disabled/unavailable
        XCTAssertFalse(staleItem.isEnabled, "stale bookmark navigation should be disabled")
        XCTAssertEqual(staleItem.value as? String, "unavailable", "stale should expose unavailable")
        // Remove should still be enabled
        let remove = removeButtons(in: app).firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 2))
        XCTAssertTrue(remove.isEnabled, "remove should remain enabled for stale")
        remove.click()
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertEqual(removeButtons(in: app).count, 0)
        XCTAssertTrue(emptyState(in: app).waitForExistence(timeout: 2))

        // Second case: delete heading
        // Recreate bookmark for Usage
        app.typeKey("a", modifierFlags: .command)
        editor.typeText("## Installation\n\nBody\n\n## Usage\n")
        Thread.sleep(forTimeInterval: 0.8)
        app.buttons["togglePresentationModeButton"].click() // back to reading to add bookmark via toggle
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        let toggles = bookmarkToggles(in: app)
        XCTAssertTrue(toggles.count >= 2)
        toggles.element(boundBy: 1).click() // Usage
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertEqual(bookmarkItems(in: app).count, 1)
        // Delete Usage heading via editing
        app.buttons["togglePresentationModeButton"].click()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.click()
        app.typeKey("a", modifierFlags: .command)
        editor.typeText("## Installation\n\nBody\n")
        Thread.sleep(forTimeInterval: 0.8)
        let deletedStale = bookmarkItems(in: app).firstMatch
        XCTAssertTrue(deletedStale.waitForExistence(timeout: 3))
        XCTAssertFalse(deletedStale.isEnabled)
        XCTAssertEqual(deletedStale.value as? String, "unavailable")
    }

    // MARK: - 6. Clean document: Bookmark ops not dirty

    func testCleanDocumentBookmarkOpsNotDirty() throws {
        let dir = try makeTemporaryDirectory()
        let url = dir.appending(path: "clean.md")
        try Data("# Head\n\nBody".utf8).write(to: url)
        let storeURL = dir.appending(path: "Bookmarks.json")
        let app = makeApplicationWithIsolatedStore(storeURL: storeURL)
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", url.path]
        app.launch()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.sheets.firstMatch.exists)
        // Add bookmark
        let toggle = bookmarkToggles(in: app).firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 2))
        toggle.click()
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertEqual(bookmarkItems(in: app).count, 1)
        // Navigate bookmark
        bookmarkItems(in: app).firstMatch.click()
        Thread.sleep(forTimeInterval: 0.5)
        // Remove bookmark
        removeButtons(in: app).firstMatch.click()
        Thread.sleep(forTimeInterval: 0.5)
        // Try to close window - should not show save sheet (since only bookmark ops, not text edits)
        app.typeKey("w", modifierFlags: .command)
        waitForWindowCount(0, in: app)
        XCTAssertFalse(app.sheets.firstMatch.exists, "bookmark add/remove/navigation must not dirty document")
    }

    // MARK: - 7. Undo: Bookmark ops not disturb text Undo

    func testBookmarkOpsDoNotDisturbUndo() throws {
        XCUIApplication().terminate()
        Thread.sleep(forTimeInterval: 0.5)
        let app = makeApplicationWithIsolatedStore(storeURL: try makeTemporaryDirectory().appending(path: "Bookmarks.json"))
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        app.buttons["togglePresentationModeButton"].click()
        let editor = app.textViews["markdownTextEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.click()
        editor.typeText("# First\n\nBody\n")
        Thread.sleep(forTimeInterval: 0.8)
        // Bookmark the heading
        let toggle = bookmarkToggles(in: app).firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 2))
        toggle.click()
        Thread.sleep(forTimeInterval: 0.8)
        editor.click()
        Thread.sleep(forTimeInterval: 0.3)
        editor.typeText(" typedAfterBookmark")
        Thread.sleep(forTimeInterval: 0.5)
        // Undo should remove typedAfterBookmark, not bookmark
        app.typeKey("z", modifierFlags: .command)
        let predicate = NSPredicate(format: "value CONTAINS %@", "# First")
        expectation(for: predicate, evaluatedWith: editor)
        waitForExpectations(timeout: 3)
        let val = editor.value as? String ?? ""
        XCTAssertFalse(val.contains("typedAfterBookmark"), "undo should remove typed text")
        XCTAssertTrue(val.contains("# First"))
        // Bookmark should still exist after undo
        XCTAssertEqual(bookmarkItems(in: app).count, 1, "bookmark should survive text undo")
        // Remove bookmark shouldn't affect redo
        removeButtons(in: app).firstMatch.click()
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertEqual(bookmarkItems(in: app).count, 0)
        app.typeKey("z", modifierFlags: [.command, .shift]) // redo
        let redoPredicate = NSPredicate(format: "value CONTAINS %@", "typedAfterBookmark")
        expectation(for: redoPredicate, evaluatedWith: editor)
        waitForExpectations(timeout: 3)
        XCTAssertTrue((editor.value as? String)?.contains("typedAfterBookmark") == true, "redo should restore typed text even after bookmark remove")
        app.terminate()
    }

    // MARK: - 8. ⌘E must still make exactly one transition per keypress

    func testCmdEOneTransition() throws {
        let app = makeApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.textViews["markdownTextEditor"].isHittable)
        app.windows["documentWindow"].click()
        app.typeKey("e", modifierFlags: .command)
        XCTAssertTrue(app.textViews["markdownTextEditor"].waitForExistence(timeout: 5))
        XCTAssertFalse(readingView(in: app).isHittable, "after one Cmd+E should be editing")
        app.typeKey("e", modifierFlags: .command)
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.textViews["markdownTextEditor"].isHittable, "after second Cmd+E should be reading")
        // Ensure no double-toggle: verify mode stable
        app.typeKey("e", modifierFlags: .command)
        XCTAssertTrue(app.textViews["markdownTextEditor"].waitForExistence(timeout: 5))
    }

    // MARK: - 9. Multi-document

    func testMultiDocumentIndependentBookmarks() throws {
        XCUIApplication().terminate()
        Thread.sleep(forTimeInterval: 0.5)
        let dir = try makeTemporaryDirectory()
        let url1 = dir.appending(path: "doc1.md")
        let url2 = dir.appending(path: "doc2.md")
        try Data("# Doc1\n\n## SectionA\n".utf8).write(to: url1)
        try Data("# Doc2\n\n## SectionB\n".utf8).write(to: url2)
        let storeURL = dir.appending(path: "Bookmarks.json")
        // Keep one document window visible per interaction. The app centers
        // multiple windows on the same frame, so directly interacting with a
        // background window is occlusion-dependent rather than user-equivalent.
        var app = makeApplicationWithIsolatedStore(storeURL: storeURL)
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", url1.path]
        app.launch()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(inspector(in: app).waitForExistence(timeout: 2))
        let doc1Toggle = bookmarkToggles(in: app).firstMatch
        XCTAssertTrue(doc1Toggle.waitForExistence(timeout: 2))
        doc1Toggle.click()
        XCTAssertTrue(bookmarkItems(in: app).firstMatch.waitForExistence(timeout: 2))
        XCTAssertEqual(bookmarkItems(in: app).count, 1)
        XCTAssertTrue(bookmarkItems(in: app).firstMatch.label.contains("Doc1"))
        app.terminate()

        app = makeApplicationWithIsolatedStore(storeURL: storeURL)
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", url2.path]
        app.launch()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(inspector(in: app).waitForExistence(timeout: 2))
        XCTAssertEqual(bookmarkItems(in: app).count, 0, "document B must not inherit document A's bookmark")
        let doc2Toggle = bookmarkToggles(in: app).firstMatch
        XCTAssertTrue(doc2Toggle.waitForExistence(timeout: 2))
        doc2Toggle.click()
        XCTAssertTrue(bookmarkItems(in: app).firstMatch.waitForExistence(timeout: 2))
        XCTAssertEqual(bookmarkItems(in: app).count, 1)
        XCTAssertTrue(bookmarkItems(in: app).firstMatch.label.contains("Doc2"))
        app.terminate()

        app = makeApplicationWithIsolatedStore(storeURL: storeURL)
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", url1.path]
        app.launch()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(inspector(in: app).waitForExistence(timeout: 2))
        XCTAssertTrue(bookmarkItems(in: app).firstMatch.waitForExistence(timeout: 3), "document A bookmark must survive document B mutation")
        XCTAssertEqual(bookmarkItems(in: app).count, 1)
        XCTAssertTrue(bookmarkItems(in: app).firstMatch.label.contains("Doc1"))
        removeButtons(in: app).firstMatch.click()
        XCTAssertTrue(emptyState(in: app).waitForExistence(timeout: 2))
        app.terminate()

        app = makeApplicationWithIsolatedStore(storeURL: storeURL)
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", url2.path]
        app.launch()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(inspector(in: app).waitForExistence(timeout: 2))
        XCTAssertTrue(bookmarkItems(in: app).firstMatch.waitForExistence(timeout: 3), "mutating document A must not remove document B bookmark")
        XCTAssertEqual(bookmarkItems(in: app).count, 1)
        XCTAssertTrue(bookmarkItems(in: app).firstMatch.label.contains("Doc2"))
    }

    // MARK: - 10. Persistence

    func testPersistenceSurvivesCloseReopen() throws {
        let dir = try makeTemporaryDirectory()
        let url = dir.appending(path: "persist.md")
        try Data("# Title\n\n## PersistMe\n".utf8).write(to: url)
        let storeURL = dir.appending(path: "Bookmarks-Persist.json")
        var app = makeApplicationWithIsolatedStore(storeURL: storeURL)
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", url.path]
        app.launch()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        let toggle = bookmarkToggles(in: app).firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 2))
        toggle.click() // bookmark first heading (Title)
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertEqual(bookmarkItems(in: app).count, 1)
        let bookmarkLabelBefore = bookmarkItems(in: app).firstMatch.label
        app.terminate()
        Thread.sleep(forTimeInterval: 0.5)
        // Reopen same file with same isolated store
        app = makeApplicationWithIsolatedStore(storeURL: storeURL)
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", url.path]
        app.launch()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(inspector(in: app).waitForExistence(timeout: 2))
        XCTAssertEqual(bookmarkItems(in: app).count, 1, "bookmark should survive close/reopen")
        let bookmarkLabelAfter = bookmarkItems(in: app).firstMatch.label
        XCTAssertEqual(bookmarkLabelBefore, bookmarkLabelAfter)
    }

    // MARK: - 11. Rename/move retains bookmark

    func testRenameMoveRetainsBookmark() throws {
        let dir = try makeTemporaryDirectory()
        let url = dir.appending(path: "original.md")
        try Data("# Title\n\n## KeepMe\n".utf8).write(to: url)
        let storeURL = dir.appending(path: "Bookmarks-Rename.json")
        var app = makeApplicationWithIsolatedStore(storeURL: storeURL)
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", url.path]
        app.launch()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        // Bookmark
        let toggle = bookmarkToggles(in: app).firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 2))
        toggle.click()
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertEqual(bookmarkItems(in: app).count, 1)
        app.terminate()
        Thread.sleep(forTimeInterval: 0.5)
        // Rename file via FileManager
        let renamedURL = dir.appending(path: "renamed.md")
        try FileManager.default.moveItem(at: url, to: renamedURL)
        // Reopen renamed file with same store
        app = makeApplicationWithIsolatedStore(storeURL: storeURL)
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", renamedURL.path]
        app.launch()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(inspector(in: app).waitForExistence(timeout: 2))
        // Bookmark should be retained via URL bookmark identity
        XCTAssertEqual(bookmarkItems(in: app).count, 1, "bookmark should be retained after rename/move")
    }
}

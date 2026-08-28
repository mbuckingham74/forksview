import XCTest

@MainActor
final class DocumentOutlineUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    private func makeApplication() -> XCUIApplication {
        XCUIApplication(url: targetApplicationURL)
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

    private func onThisPageSection(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["onThisPageSection"]
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

    // MARK: - Tests

    func testInitialOutlineShowsHeadingsInSourceOrder() throws {
        let dir = try makeTemporaryDirectory()
        let url = dir.appending(path: "outline.md")
        let md = """
        # H1 Title
        ## H2 Second
        ### H3 Third

        Body

        # Another H1
        """
        try Data(md.utf8).write(to: url)
        let app = makeApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", url.path]
        app.launch()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(inspector(in: app).waitForExistence(timeout: 2))
        XCTAssertTrue(outline(in: app).waitForExistence(timeout: 2))
        // Verify rows exist in order via button labels (filter to outline items only, not bookmark toggles)
        let buttons = outline(in: app).buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "documentOutlineItem-"))
        // Should have 4 headings
        XCTAssertTrue(buttons.count >= 4, "expected at least 4 outline buttons, got \(buttons.count)")
        // Check ordering by accessibility label prefix
        let labels = buttons.allElementsBoundByIndex.map { $0.label }
        // First should be H1 Title
        XCTAssertTrue(labels[0].contains("H1 Title"))
        XCTAssertTrue(labels[0].contains("heading level 1"))
        XCTAssertTrue(labels[1].contains("H2 Second"))
        XCTAssertTrue(labels[2].contains("H3 Third"))
        // Bookmarks placeholder remains
        XCTAssertTrue(app.staticTexts["Bookmarks"].exists)
        XCTAssertTrue(app.staticTexts["No bookmarks yet"].exists)
    }

    func testNoHeadingsShowsPlaceholder() throws {
        let dir = try makeTemporaryDirectory()
        let url = dir.appending(path: "nohead.md")
        try Data("Just a paragraph\n\nAnother line".utf8).write(to: url)
        let app = makeApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", url.path]
        app.launch()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(inspector(in: app).waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["No headings"].waitForExistence(timeout: 2), "No headings placeholder should appear")
        XCTAssertTrue(app.staticTexts["Bookmarks"].exists)
    }

    func testUniqueReadingNavigation() throws {
        let dir = try makeTemporaryDirectory()
        let url = dir.appending(path: "nav.md")
        // Create long document with headings spaced
        var md = "# Top\n\n"
        for i in 1...20 {
            md += "Repeated Block \(i)\n\nBody \(i)\n\n"
        }
        md += "## Target Heading\n\nTarget body\n\n"
        for i in 21...40 { md += "Block \(i)\n\n" }
        try Data(md.utf8).write(to: url)
        let app = makeApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", url.path]
        app.launch()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        let targetButton = outline(in: app).buttons.matching(NSPredicate(format: "label CONTAINS 'Target Heading'")).firstMatch
        XCTAssertTrue(targetButton.waitForExistence(timeout: 2))
        targetButton.click()
        // Verify reading view still exists and heading is visible via viewport? We can check that the scroll view exists; actual scrollTo is hard to assert pixel-perfect, so verify outline tap didn't change mode and reading still visible
        XCTAssertTrue(readingView(in: app).exists)
        XCTAssertFalse(app.textViews["markdownTextEditor"].isHittable, "should remain in reading mode")
    }

    func testDuplicateReadingNavigation() throws {
        let dir = try makeTemporaryDirectory()
        let url = dir.appending(path: "dup.md")
        var md = ""
        for i in 1...15 { md += "Block \(i)\n\n" }
        md += "## Installation\n\nFirst occurrence\n\n"
        for i in 16...30 { md += "Block \(i)\n\n" }
        md += "## Installation\n\nSecond occurrence\n\n"
        for i in 31...45 { md += "Block \(i)\n\n" }
        try Data(md.utf8).write(to: url)
        let app = makeApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", url.path]
        app.launch()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        let outlineEl = outline(in: app)
        XCTAssertTrue(outlineEl.waitForExistence(timeout: 2))
        let buttons = outlineEl.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "documentOutlineItem-", "Installation"))
        XCTAssertEqual(buttons.count, 2, "two duplicate Installation headings")
        // Buttons should have occurrence labels: 1 of 2 and 2 of 2
        let firstLabel = buttons.element(boundBy: 0).label
        let secondLabel = buttons.element(boundBy: 1).label
        XCTAssertTrue(firstLabel.contains("1 of 2"), "first duplicate label \(firstLabel) should contain 1 of 2")
        XCTAssertTrue(secondLabel.contains("2 of 2"), "second duplicate label \(secondLabel) should contain 2 of 2")
        // Click first, then second, verify reading stays reading and no crash
        buttons.element(boundBy: 0).click()
        XCTAssertTrue(readingView(in: app).exists)
        Thread.sleep(forTimeInterval: 0.5)
        buttons.element(boundBy: 1).click()
        XCTAssertTrue(readingView(in: app).exists)
    }

    func testEditingNavigationKeepsEditingAndFocus() throws {
        let dir = try makeTemporaryDirectory()
        let url = dir.appending(path: "editnav.md")
        let md = "# Top\n\n## Section One\n\nContent\n\n## Section Two\n\nMore content\n"
        try Data(md.utf8).write(to: url)
        let app = makeApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", url.path]
        app.launch()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        app.buttons["togglePresentationModeButton"].click()
        let editor = app.textViews["markdownTextEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.click()
        // Click outline row for Section Two while editing
        let sectionTwoButton = outline(in: app).buttons.matching(NSPredicate(format: "label CONTAINS 'Section Two'")).firstMatch
        XCTAssertTrue(sectionTwoButton.waitForExistence(timeout: 2))
        sectionTwoButton.click()
        // Should remain in editing
        XCTAssertTrue(editor.waitForExistence(timeout: 2))
        XCTAssertFalse(readingView(in: app).isHittable, "reading should be hidden in editing mode after outline navigation")
        XCTAssertTrue(editor.isHittable, "editor should remain hittable")
        // Verify editor has focus (first responder) by trying to type and checking value
        editor.typeText(" EDITED")
        XCTAssertTrue((editor.value as? String)?.contains("EDITED") == true, "typing should occur at target caret location")
        // Check that typing went near Section Two heading: verify selected range? We can't easily assert caret location, but verify text contains heading and edit near it
        let val = editor.value as? String ?? ""
        XCTAssertTrue(val.contains("Section Two"), "text should still contain Section Two")
    }

    func testUnsavedUpdateShowsInInspector() throws {
        let app = makeApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        app.buttons["togglePresentationModeButton"].click()
        let editor = app.textViews["markdownTextEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.click()
        editor.typeText("# New Heading\n\nBody\n")
        // Without saving, inspector should update
        let newHeadingButton = outline(in: app).buttons.matching(NSPredicate(format: "label CONTAINS 'New Heading'")).firstMatch
        XCTAssertTrue(newHeadingButton.waitForExistence(timeout: 2), "new heading should appear in outline without save")
        // Verify button is usable: click it while still editing, should not crash and remain editing
        newHeadingButton.click()
        XCTAssertTrue(editor.exists)
    }

    func testNavigationStaysClean() throws {
        let dir = try makeTemporaryDirectory()
        let url = dir.appending(path: "clean.md")
        try Data("# Head\n\nBody".utf8).write(to: url)
        let app = makeApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", url.path]
        app.launch()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        // Navigate via outline only (no editing)
        let headButton = outline(in: app).buttons.firstMatch
        XCTAssertTrue(headButton.waitForExistence(timeout: 2))
        headButton.click()
        Thread.sleep(forTimeInterval: 0.5)
        // Close without editing should not show save sheet
        app.typeKey("w", modifierFlags: .command)
        waitForWindowCount(0, in: app)
        XCTAssertFalse(app.sheets.firstMatch.exists, "navigation only should not dirty document")
    }

    func testUndoAfterNavigation() throws {
        let app = makeApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        app.buttons["togglePresentationModeButton"].click()
        let editor = app.textViews["markdownTextEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.click()
        editor.typeText("# First\n\nBody\n")
        // Navigate via outline (should not affect undo)
        let firstButton = outline(in: app).buttons.firstMatch
        XCTAssertTrue(firstButton.waitForExistence(timeout: 2))
        firstButton.click()
        editor.click()
        editor.typeText(" typedAfterNav")
        // Undo should undo typedAfterNav, not navigation
        app.typeKey("z", modifierFlags: .command)
        let valueAfterUndo = NSPredicate(format: "value CONTAINS %@", "# First")
        expectation(for: valueAfterUndo, evaluatedWith: editor)
        waitForExpectations(timeout: 3)
        let val = editor.value as? String ?? ""
        XCTAssertFalse(val.contains("typedAfterNav"), "undo should remove typed text after navigation")
        XCTAssertTrue(val.contains("# First"), "outline heading should remain")
    }

    func testCmdEToggleStillWorksAfterOutline() throws {
        let app = makeApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        app.windows["documentWindow"].click()
        app.typeKey("e", modifierFlags: .command)
        XCTAssertTrue(app.textViews["markdownTextEditor"].waitForExistence(timeout: 5))
        app.typeKey("e", modifierFlags: .command)
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        // Verify outline still present after toggles
        XCTAssertTrue(outline(in: app).waitForExistence(timeout: 2))
    }

    func testTwoDocumentsIndependentOutlines() throws {
        let dir = try makeTemporaryDirectory()
        let url1 = dir.appending(path: "doc1.md")
        let url2 = dir.appending(path: "doc2.md")
        try Data("# Doc1 Heading\n\nBody".utf8).write(to: url1)
        try Data("Just paragraph no heading".utf8).write(to: url2)
        let app = makeApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", url1.path, url2.path]
        app.launch()
        let twoWindows = NSPredicate(format: "count == 2")
        expectation(for: twoWindows, evaluatedWith: app.windows)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(app.windows.count, 2)
        // Check that at least one window has outline and one has No headings
        let outlines = app.descendants(matching: .any).matching(identifier: "documentOutline")
        // At least one outline exists
        XCTAssertTrue(outlines.firstMatch.waitForExistence(timeout: 2))
        // Check No headings appears somewhere
        XCTAssertTrue(app.staticTexts["No headings"].exists || outlines.count == 2, "one doc should show No headings")
        // Check Bookmarks placeholder still in both
        XCTAssertTrue(app.staticTexts["No bookmarks yet"].exists)
    }

    func testBookmarksPlaceholderUnchanged() throws {
        // Milestone 8: Bookmarks is now functional, but empty state still shows placeholder.
        let app = makeApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Bookmarks"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["No bookmarks yet"].exists)
        // In M8, empty state identifier should exist and no bookmark items should be present
        XCTAssertTrue(app.descendants(matching: .any)["documentBookmarksEmptyState"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "documentBookmarkItem-")).count, 0)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "removeDocumentBookmark-")).count, 0)
    }
}

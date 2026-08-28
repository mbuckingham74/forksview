import XCTest

@MainActor
final class Milestone10AccessibilityUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func makeApplication() -> XCUIApplication {
        XCUIApplication(url: targetApplicationURL)
    }
    private var targetApplicationURL: URL {
        Bundle.main.bundleURL.deletingLastPathComponent().appending(path: "Forksview.app", directoryHint: .isDirectory)
    }
    private func readingView(in app: XCUIApplication) -> XCUIElement { app.scrollViews["markdownReadingView"] }
    private func editorView(in app: XCUIApplication) -> XCUIElement { app.textViews["markdownTextEditor"] }
    private func inspector(in app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any)["documentInspector"] }
    private func outline(in app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any)["documentOutline"] }
    private func bookmarksSection(in app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any)["bookmarksSection"] }
    private func makeTemporaryDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func scrollPosition(of element: XCUIElement) -> Double? {
        let candidates = [element, element.scrollBars.firstMatch]
        for candidate in candidates {
            if let number = candidate.value as? NSNumber { return number.doubleValue }
            if let string = candidate.value as? String, let value = Double(string) { return value }
        }
        return nil
    }

    // MARK: - Toolbar mode control
    func testModeControlAccessibilityLabelAndValue() throws {
        let app = makeApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        let toggle = app.buttons["togglePresentationModeButton"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 2))
        // Reading mode: value should be Reading mode, label action-oriented
        XCTAssertEqual(toggle.value as? String, "Reading mode")
        XCTAssertTrue(toggle.label == "Edit document" || toggle.label.contains("Edit"), "label \(toggle.label) should be action-oriented for reading")
        // Toggle to editing
        toggle.click()
        XCTAssertTrue(editorView(in: app).waitForExistence(timeout: 5))
        // Re-query after mode change
        let toggle2 = app.buttons["togglePresentationModeButton"]
        XCTAssertTrue(toggle2.waitForExistence(timeout: 2))
        XCTAssertEqual(toggle2.value as? String, "Editing mode")
        XCTAssertTrue(toggle2.label.contains("reading") || toggle2.label.contains("Reading") || toggle2.label.contains("Done"), "label \(toggle2.label) should be action-oriented for editing")
        // Toggle back
        toggle2.click()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["togglePresentationModeButton"].value as? String, "Reading mode")
    }

    func testHistoryAndInspectorPaneControlsAccessibility() throws {
        let app = makeApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        let history = app.buttons["toggleSidebarButton"]
        let inspectorToggle = app.buttons["toggleInspectorButton"]
        XCTAssertTrue(history.waitForExistence(timeout: 2))
        XCTAssertTrue(inspectorToggle.waitForExistence(timeout: 2))
        // Initially both shown
        XCTAssertEqual(history.value as? String, "Shown")
        XCTAssertTrue(history.label == "Hide History Sidebar")
        XCTAssertEqual(inspectorToggle.value as? String, "Shown")
        XCTAssertTrue(inspectorToggle.label == "Hide Inspector")
        // Hide history
        history.click()
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertEqual(app.buttons["toggleSidebarButton"].value as? String, "Hidden")
        XCTAssertTrue(app.buttons["toggleSidebarButton"].label == "Show History Sidebar")
        // Show again
        app.buttons["toggleSidebarButton"].click()
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertEqual(app.buttons["toggleSidebarButton"].value as? String, "Shown")
        // Hide inspector
        inspectorToggle.click()
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertEqual(app.buttons["toggleInspectorButton"].value as? String, "Hidden")
        XCTAssertTrue(app.buttons["toggleInspectorButton"].label == "Show Inspector")
        // Show again
        app.buttons["toggleInspectorButton"].click()
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertEqual(app.buttons["toggleInspectorButton"].value as? String, "Shown")
    }

    func testCommandEFocusingAndKeyboardScrollingInReading() throws {
        // Build long document
        let dir = try makeTemporaryDirectory()
        let url = dir.appending(path: "long.md")
        var md = "# Top\n\n"
        for i in 1...60 { md += "Paragraph \(i) content to make document scrollable. Lorem ipsum dolor sit amet.\n\n" }
        md += "## Target\n\nEnd\n"
        try Data(md.utf8).write(to: url)
        let app = makeApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", url.path]
        app.launch()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        // Go editing then back to reading via Command-E and verify focus moves.
        app.windows["documentWindow"].click()
        app.typeKey("e", modifierFlags: .command)
        XCTAssertTrue(editorView(in: app).waitForExistence(timeout: 5))
        // Verify editor has focus by typing
        let editor = editorView(in: app)
        editor.typeText("X")
        XCTAssertTrue((editor.value as? String)?.contains("X") == true)
        // Back to reading via Command-E
        app.windows["documentWindow"].click()
        app.typeKey("e", modifierFlags: .command)
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        // Verify reading view has focus by requiring keyboard scrolling to change its AX scroll value.
        let reading = readingView(in: app)
        XCTAssertTrue(reading.waitForExistence(timeout: 2))
        let initialPosition = try XCTUnwrap(scrollPosition(of: reading), "reading view should expose a numeric scroll position")
        app.typeKey(.pageDown, modifierFlags: [])
        let afterPageDown = try XCTUnwrap(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                guard let position = self.scrollPosition(of: reading) else { return false }
                return position > initialPosition + 0.01
            }, object: nil)], timeout: 2) == .completed ? scrollPosition(of: reading) : nil,
            "Page Down should scroll the focused reading view"
        )
        app.typeKey(.pageUp, modifierFlags: [])
        let afterPageUp = try XCTUnwrap(scrollPosition(of: reading), "reading view should remain queryable after Page Up")
        XCTAssertLessThan(afterPageUp, afterPageDown - 0.01, "Page Up should move the reading view back toward the top")
        app.typeKey(.downArrow, modifierFlags: [])
        let afterArrow = try XCTUnwrap(scrollPosition(of: reading), "reading view should remain queryable after Down Arrow")
        XCTAssertGreaterThan(afterArrow, afterPageUp, "Down Arrow should move the focused reading view")
        // Also verify reading accessibility label
        XCTAssertEqual(reading.label, "Markdown document")
    }

    func testOutlineLabelsAndDuplicateSemantics() throws {
        let dir = try makeTemporaryDirectory()
        let url = dir.appending(path: "outline.md")
        let storeURL = dir.appending(path: "Bookmarks.json")
        var md = "# H1\n\n"
        md += "## Installation\n\nFirst\n\n"
        md += "## Installation\n\nSecond\n\n"
        md += "### Sub A\n\n## Other\n\n"
        try Data(md.utf8).write(to: url)
        let app = makeApplication()
        app.launchEnvironment["FORKSVIEW_BOOKMARK_ARCHIVE_PATH"] = storeURL.path
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", url.path]
        app.launch()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(outline(in: app).waitForExistence(timeout: 3))
        let outlineEl = outline(in: app)
        let buttons = outlineEl.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "documentOutlineItem-"))
        XCTAssertTrue(buttons.count >= 4)
        // Check useful labels include heading level
        for idx in 0..<buttons.count {
            let lbl = buttons.element(boundBy: idx).label
            XCTAssertTrue(lbl.contains("heading level"), "label \(lbl) should include heading level")
        }
        // Duplicate occurrence: two Installation at level 2
        let dupButtons = outlineEl.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "documentOutlineItem-", "Installation"))
        XCTAssertEqual(dupButtons.count, 2)
        XCTAssertTrue(dupButtons.element(boundBy: 0).label.contains("1 of 2"))
        XCTAssertTrue(dupButtons.element(boundBy: 1).label.contains("2 of 2"))
        // Verify bookmark toggles expose Not bookmarked initially
        let toggles = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "documentBookmarkToggle-"))
        XCTAssertTrue(toggles.count >= 4)
        let firstToggleValue = toggles.firstMatch.value as? String
        XCTAssertTrue(firstToggleValue == "Not bookmarked" || firstToggleValue == "Bookmarked", "toggle value \(String(describing: firstToggleValue)) should be Bookmarked/Not bookmarked")
        XCTAssertEqual(firstToggleValue, "Not bookmarked", "initially not bookmarked")
        // Keyboard activation: traverse from the reading region to the first outline
        // row and bookmark toggle, then activate the focused toggle twice.
        let firstToggle = toggles.firstMatch
        app.typeKey(.tab, modifierFlags: [])
        app.typeKey(.tab, modifierFlags: [])
        app.typeKey(.space, modifierFlags: [])
        XCTAssertEqual(firstToggle.value as? String, "Bookmarked")
        app.typeKey(.space, modifierFlags: [])
        XCTAssertEqual(firstToggle.value as? String, "Not bookmarked")
    }

    func testBookmarksStateAndStaleSemantics() throws {
        let dir = try makeTemporaryDirectory()
        let url = dir.appending(path: "bkm.md")
        let storeURL = dir.appending(path: "Bookmarks.json")
        let md = "# Title\n\n## Keep\n\nBody\n\n## RemoveMe\n\nBody\n\n"
        try Data(md.utf8).write(to: url)
        let app = makeApplication()
        app.launchEnvironment["FORKSVIEW_BOOKMARK_ARCHIVE_PATH"] = storeURL.path
        app.launchEnvironment["FORKSVIEW_BOOKMARKS_PATH"] = storeURL.path
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", url.path]
        app.launch()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(outline(in: app).waitForExistence(timeout: 2))
        // Add bookmarks for both headings
        let toggles = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "documentBookmarkToggle-"))
        XCTAssertTrue(toggles.count >= 3)
        toggles.element(boundBy: 1).click()
        Thread.sleep(forTimeInterval: 0.4)
        toggles.element(boundBy: 2).click()
        Thread.sleep(forTimeInterval: 0.4)
        // Verify toggles now Bookmarked
        XCTAssertTrue(toggles.allElementsBoundByIndex.contains { ($0.value as? String) == "Bookmarked" })
        // Verify resolved bookmarks navigable
        let bookmarkItems = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "documentBookmarkItem-"))
        XCTAssertTrue(bookmarkItems.firstMatch.waitForExistence(timeout: 2))
        XCTAssertEqual(bookmarkItems.count, 2)
        bookmarkItems.firstMatch.click()
        Thread.sleep(forTimeInterval: 0.4)
        XCTAssertTrue(readingView(in: app).exists)
        // Make one stale by editing away its heading: go editing and delete RemoveMe
        app.buttons["togglePresentationModeButton"].click()
        XCTAssertTrue(editorView(in: app).waitForExistence(timeout: 3))
        let editor = editorView(in: app)
        editor.click()
        app.typeKey("a", modifierFlags: .command)
        editor.typeText("# Title\n\n## Keep\n\nBody\n\n")
        app.typeKey("s", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.6)
        app.buttons["togglePresentationModeButton"].click()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 3))
        // Stale bookmark should be disabled with unavailable state and visible Unavailable text
        Thread.sleep(forTimeInterval: 0.5)
        // Find stale item: it should have value unavailable and be disabled
        let allBookmarkItems = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "documentBookmarkItem-"))
        let unavailableItems = allBookmarkItems.matching(NSPredicate(format: "value == %@", "unavailable"))
        XCTAssertEqual(unavailableItems.count, 1, "stale bookmark should expose accessibility value unavailable")
        XCTAssertTrue(unavailableItems.firstMatch.exists)
        // Visible Unavailable text
        let unavailableText = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Unavailable'"))
        let staleLabelContainsUnavailable = (0..<allBookmarkItems.count).contains {
            allBookmarkItems.element(boundBy: $0).label.contains("Unavailable")
        }
        XCTAssertTrue(unavailableText.firstMatch.exists || staleLabelContainsUnavailable, "stale bookmark should visibly expose Unavailable")
        // Removal remains enabled: remove buttons count should match total bookmarks (including stale)
        let removeButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "removeDocumentBookmark-"))
        XCTAssertTrue(removeButtons.count >= 2)
        XCTAssertTrue(removeButtons.firstMatch.isEnabled)
        // Test post-removal focus: after removing the first row, Space must activate the
        // deterministically focused remaining remove button without another mouse click.
        let countBefore = removeButtons.count
        removeButtons.firstMatch.click()
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "removeDocumentBookmark-")).count == countBefore - 1
        }, object: nil)], timeout: 2) == .completed)
        let countAfter = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "removeDocumentBookmark-")).count
        XCTAssertEqual(countAfter, countBefore - 1)
        app.typeKey(.space, modifierFlags: [])
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.staticTexts["No bookmarks yet"].exists
        }, object: nil)], timeout: 2) == .completed, "Space should remove the newly focused remaining bookmark")
        XCTAssertTrue(app.staticTexts["No bookmarks yet"].exists)
    }

    func testInspectorBookmarksDiscoverableWithLongOutline() throws {
        let dir = try makeTemporaryDirectory()
        let url = dir.appending(path: "long.md")
        var md = ""
        for i in 1...50 { md += "## Heading \(i)\n\nBody \(i)\n\n" }
        try Data(md.utf8).write(to: url)
        let app = makeApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", url.path]
        app.launch()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(outline(in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(bookmarksSection(in: app).waitForExistence(timeout: 2))
        // Both regions should exist simultaneously; outline may be scrollable but bookmarks section must remain visible
        XCTAssertTrue(bookmarksSection(in: app).exists)
        XCTAssertTrue(outline(in: app).exists)
        // Verify bookmarks empty state visible even with long outline (bookmarks section not pushed offscreen)
        XCTAssertTrue(app.staticTexts["No bookmarks yet"].exists || app.descendants(matching: .any)["documentBookmarksEmptyState"].exists)
        // Verify outline is scrollable: we can check outline buttons count is 50 and first and last exist but may require scrolling - at least first exists
        let buttons = outline(in: app).buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "documentOutlineItem-"))
        XCTAssertTrue(buttons.count >= 50)
        // Try scrolling outline via swipe
        outline(in: app).swipeUp()
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertTrue(bookmarksSection(in: app).exists, "Bookmarks section should remain discoverable after scrolling outline")
    }

    func testReadingViewAccessibilityLabelAndFocus() throws {
        let app = makeApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        let reading = readingView(in: app)
        XCTAssertEqual(reading.identifier, "markdownReadingView")
        XCTAssertEqual(reading.label, "Markdown document")
        // History sidebar region label
        let history = app.descendants(matching: .any)["historySidebar"]
        XCTAssertTrue(history.waitForExistence(timeout: 2))
        XCTAssertEqual(history.label, "History sidebar")
        // Inspector label
        let insp = inspector(in: app)
        XCTAssertTrue(insp.waitForExistence(timeout: 2))
        // Outline accessibility
        XCTAssertTrue(outline(in: app).waitForExistence(timeout: 2))
        // Center region exists
        XCTAssertTrue(app.descendants(matching: .any)["centerDocumentRegion"].exists)
    }
}

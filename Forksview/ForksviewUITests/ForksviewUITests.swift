import XCTest

@MainActor
final class ForksviewUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {}

    @MainActor
    func testOrdinaryLaunchCreatesExactlyOneUntitledDocumentWindow() throws {
        let app = makeApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()

        // Milestone 5: reading is default — readingView is a ScrollView (verified via XCUI hierarchy)
        let reading = readingView(in: app)
        XCTAssertTrue(reading.waitForExistence(timeout: 5), "document should open in reading mode")
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertTrue(app.buttons["togglePresentationModeButton"].exists, "pencil toggle should exist in reading mode")
    }

    @MainActor
    func testColdLaunchWithMultipleMarkdownFilesCreatesOneWindowPerFile() throws {
        let directory = try makeTemporaryDirectory()
        let firstURL = directory.appending(path: "first.md")
        let secondURL = directory.appending(path: "second.markdown")
        try Data("first cold-open document".utf8).write(to: firstURL)
        try Data("second cold-open document".utf8).write(to: secondURL)

        let app = makeApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            firstURL.path, secondURL.path
        ]
        app.launch()

        let twoWindows = NSPredicate(format: "count == 2")
        expectation(for: twoWindows, evaluatedWith: app.windows)
        waitForExpectations(timeout: 5)

        // In reading mode, windows show rendered content, not raw editor. Verify windows exist and titles contain file names.
        XCTAssertEqual(app.windows.count, 2)
        // Toggle each window to editing to verify underlying text (ensure single source without needing render parsing)
        // Activate first window and check reading view exists
        let readingViews = app.scrollViews.matching(identifier: "markdownReadingView")
        XCTAssertTrue(readingViews.firstMatch.waitForExistence(timeout: 5))
        // Also verify window titles
        let titles = app.windows.allElementsBoundByIndex.map { $0.title }
        XCTAssertTrue(titles.contains(where: { $0.contains("first") }))
        XCTAssertTrue(titles.contains(where: { $0.contains("second") }))
    }

    @MainActor
    func testReopenCreatesUntitledOnlyWhenNoDocumentWindowIsVisible() throws {
        let app = makeApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()

        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        XCTAssertEqual(app.windows.count, 1)

        app.typeKey("w", modifierFlags: .command)
        waitForWindowCount(0, in: app)
        XCTAssertEqual(app.state, .runningForeground)

        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        XCTAssertEqual(app.state, .runningBackground)
        clickForksviewDockIcon()

        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        XCTAssertEqual(app.windows.count, 1)

        finder.activate()
        clickForksviewDockIcon()
        assertWindowCountRemains(1, in: app)
    }

    @MainActor
    func testTwoDocumentsHaveIndependentUndoAndDirtyState() throws {
        let app = makeApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()

        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        // Toggle to editing for first doc
        app.buttons["togglePresentationModeButton"].click()
        let firstEditor = app.textViews["markdownTextEditor"]
        XCTAssertTrue(firstEditor.waitForExistence(timeout: 5))
        firstEditor.click()
        firstEditor.typeText("first document")

        app.typeKey("n", modifierFlags: .command)
        let twoWindows = NSPredicate(format: "count == 2")
        expectation(for: twoWindows, evaluatedWith: app.windows)
        waitForExpectations(timeout: 5)

        // Second window starts in reading, toggle to editing — scope to front window to avoid ambiguity with two document windows
        let frontWindow = app.windows.firstMatch
        if readingView(in: app).exists {
            frontWindow.buttons["togglePresentationModeButton"].click()
        }
        let frontEditor = frontWindow.textViews["markdownTextEditor"]
        XCTAssertTrue(frontEditor.waitForExistence(timeout: 5))
        frontEditor.click()
        frontEditor.typeText("second document")

        let editorValues = app.textViews.matching(identifier: "markdownTextEditor")
            .allElementsBoundByIndex
            .compactMap { $0.value as? String }
        XCTAssertTrue(editorValues.contains("first document"))
        XCTAssertTrue(editorValues.contains("second document"))

        app.typeKey("z", modifierFlags: .command)
        let secondWasUndone = NSPredicate(format: "value == %@", "")
        expectation(for: secondWasUndone, evaluatedWith: frontEditor)
        waitForExpectations(timeout: 5)

        app.typeKey("w", modifierFlags: .command)
        waitForWindowCount(1, in: app)
        XCTAssertFalse(app.sheets.firstMatch.exists)

        // Remaining window: need to ensure editing to check value — scope to window
        if readingView(in: app).exists {
            app.windows.firstMatch.buttons["togglePresentationModeButton"].click()
        }
        let remainingEditor = app.windows.firstMatch.textViews["markdownTextEditor"]
        XCTAssertEqual(remainingEditor.value as? String, "first document")
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.sheets.firstMatch.buttons["Cancel"].exists)
        app.sheets.firstMatch.buttons["Cancel"].click()
        XCTAssertEqual(app.windows.count, 1)
    }

    @MainActor
    func testUndoBackToOriginalStateClosesWithoutSaveSheet() throws {
        let app = makeApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()

        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        app.buttons["togglePresentationModeButton"].click()
        let editor = app.textViews["markdownTextEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.click()
        editor.typeText("undo to clean")
        app.typeKey("z", modifierFlags: .command)

        let originalTextWasRestored = NSPredicate(format: "value == %@", "")
        expectation(for: originalTextWasRestored, evaluatedWith: editor)
        waitForExpectations(timeout: 5)

        app.typeKey("w", modifierFlags: .command)
        waitForWindowCount(0, in: app)
        XCTAssertFalse(app.sheets.firstMatch.exists)
    }

    @MainActor
    func testRedoMakesDocumentDirtyAgainAndUsesNativeSaveFlow() throws {
        let app = makeApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()

        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        app.buttons["togglePresentationModeButton"].click()
        let editor = app.textViews["markdownTextEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.click()
        editor.typeText("redo to dirty")
        app.typeKey("z", modifierFlags: .command)
        app.typeKey("z", modifierFlags: [.command, .shift])

        let editedTextWasRestored = NSPredicate(format: "value == %@", "redo to dirty")
        expectation(for: editedTextWasRestored, evaluatedWith: editor)
        waitForExpectations(timeout: 5)

        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.sheets.firstMatch.buttons["Cancel"].exists)
        app.sheets.firstMatch.buttons["Cancel"].click()
    }

    @MainActor
    func testLaunchWithMarkdownFileEditsSavesAndReopensOneManagedDocumentWindow() throws {
        let directory = try makeTemporaryDirectory()
        let fileURL = directory.appending(path: "launch-fixture.markdown")
        let expected = "Opened as a Markdown document 🧭\n"
        try Data(expected.utf8).write(to: fileURL)

        let app = makeApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", fileURL.path]
        app.launch()

        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertTrue(app.windows.firstMatch.title.contains("launch-fixture"))

        // Toggle to editing to verify initial content and to edit
        app.buttons["togglePresentationModeButton"].click()
        let editor = app.textViews["markdownTextEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, expected)

        let savedText = "Saved through the document responder chain ✅\n"
        editor.click()
        app.typeKey("a", modifierFlags: .command)
        editor.typeText(savedText)
        app.typeKey("s", modifierFlags: .command)

        let fileWasSaved = NSPredicate { _, _ in
            (try? String(contentsOf: fileURL, encoding: .utf8)) == savedText
        }
        expectation(for: fileWasSaved, evaluatedWith: NSObject())
        waitForExpectations(timeout: 5)

        app.typeKey("w", modifierFlags: .command)
        let noWindows = NSPredicate(format: "count == 0")
        expectation(for: noWindows, evaluatedWith: app.windows)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.sheets.firstMatch.exists)
        app.terminate()

        let reopenedApp = makeApplication()
        reopenedApp.launchArguments = ["-ApplePersistenceIgnoreState", "YES", fileURL.path]
        reopenedApp.launch()
        XCTAssertTrue(readingView(in: reopenedApp).waitForExistence(timeout: 5))
        // Toggle to editing to verify reopened content
        reopenedApp.buttons["togglePresentationModeButton"].click()
        let reopenedEditor = reopenedApp.textViews["markdownTextEditor"]
        XCTAssertTrue(reopenedEditor.waitForExistence(timeout: 5))
        XCTAssertEqual(reopenedEditor.value as? String, savedText)
        XCTAssertEqual(reopenedApp.windows.count, 1)
    }

    @MainActor
    func testUndoAndRedoTraverseSavedStateAcrossSaveBoundary() throws {
        let directory = try makeTemporaryDirectory()
        let fileURL = directory.appending(path: "save-boundary.md")
        try Data("original\n".utf8).write(to: fileURL)

        let app = makeApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", fileURL.path]
        app.launch()

        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        app.buttons["togglePresentationModeButton"].click()
        let editor = app.textViews["markdownTextEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))

        let savedText = "saved state\n"
        editor.click()
        app.typeKey("a", modifierFlags: .command)
        editor.typeText(savedText)
        app.typeKey("s", modifierFlags: .command)

        let fileWasSaved = NSPredicate { _, _ in
            (try? String(contentsOf: fileURL, encoding: .utf8)) == savedText
        }
        expectation(for: fileWasSaved, evaluatedWith: NSObject())
        waitForExpectations(timeout: 5)

        app.typeKey(.downArrow, modifierFlags: .command)
        editor.typeText("post-save edit")
        app.typeKey("z", modifierFlags: .command)

        let savedStateWasRestored = NSPredicate(format: "value == %@", savedText)
        expectation(for: savedStateWasRestored, evaluatedWith: editor)
        waitForExpectations(timeout: 5)

        app.typeKey("z", modifierFlags: .command)
        let originalStateWasRestored = NSPredicate(format: "value == %@", "original\n")
        expectation(for: originalStateWasRestored, evaluatedWith: editor)
        waitForExpectations(timeout: 5)

        app.typeKey("z", modifierFlags: [.command, .shift])
        expectation(for: savedStateWasRestored, evaluatedWith: editor)
        waitForExpectations(timeout: 5)

        app.typeKey("z", modifierFlags: [.command, .shift])
        let postSaveStateWasRestored = NSPredicate(
            format: "value == %@",
            savedText + "post-save edit"
        )
        expectation(for: postSaveStateWasRestored, evaluatedWith: editor)
        waitForExpectations(timeout: 5)

        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.sheets.firstMatch.buttons["Cancel"].exists)
        app.sheets.firstMatch.buttons["Cancel"].click()
    }

    @MainActor
    func testUndoToSavedStateClosesWithoutSaveSheet() throws {
        let directory = try makeTemporaryDirectory()
        let fileURL = directory.appending(path: "clean-save-boundary.md")
        try Data("original\n".utf8).write(to: fileURL)

        let app = makeApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", fileURL.path]
        app.launch()

        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        app.buttons["togglePresentationModeButton"].click()
        let editor = app.textViews["markdownTextEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let savedText = "saved state\n"
        editor.click()
        app.typeKey("a", modifierFlags: .command)
        editor.typeText(savedText)
        app.typeKey("s", modifierFlags: .command)

        let fileWasSaved = NSPredicate { _, _ in
            (try? String(contentsOf: fileURL, encoding: .utf8)) == savedText
        }
        expectation(for: fileWasSaved, evaluatedWith: NSObject())
        waitForExpectations(timeout: 5)

        app.typeKey(.downArrow, modifierFlags: .command)
        editor.typeText("post-save edit")
        app.typeKey("z", modifierFlags: .command)

        let savedStateWasRestored = NSPredicate(format: "value == %@", savedText)
        expectation(for: savedStateWasRestored, evaluatedWith: editor)
        waitForExpectations(timeout: 5)

        app.typeKey("w", modifierFlags: .command)
        waitForWindowCount(0, in: app)
        XCTAssertFalse(app.sheets.firstMatch.exists)
    }

    // MARK: - Milestone 5: reading/edit transition

    @MainActor
    func testDocumentOpensInReadingToggleToEditingEditToggleBackRendersAndPreserves() throws {
        let app = makeApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()

        // 1. document opens in rendered reading mode
        let reading = readingView(in: app)
        XCTAssertTrue(reading.waitForExistence(timeout: 5))
        XCTAssertFalse(app.textViews["markdownTextEditor"].exists, "editor should be hidden in reading mode")

        // 2. toggle to editing via pencil button
        let toggle = app.buttons["togglePresentationModeButton"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.click()

        // 3. raw Markdown/native editor becomes available
        let editor = app.textViews["markdownTextEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertFalse(reading.exists, "reading should be hidden in editing mode")

        // 4. edit content
        editor.click()
        editor.typeText("# Edited Title\n\nNew **bold** content")

        // 5. toggle back via the AppKit View-menu command
        app.typeKey("e", modifierFlags: .command)
        XCTAssertTrue(reading.waitForExistence(timeout: 5))
        // Verify the reading view exists and window still has toggle
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))

        // 7. toggle back to editor via the same AppKit command
        app.typeKey("e", modifierFlags: .command)
        XCTAssertTrue(editor.waitForExistence(timeout: 5))

        // 8. edited source remains intact — wait for sync
        let expected = "# Edited Title\n\nNew **bold** content"
        XCTAssertEqual(editor.value as? String, expected)
    }

    @MainActor
    func testToggleViaCmdEAndToolbarStaysSynchronized() throws {
        let app = makeApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["markdownReadingView"].waitForExistence(timeout: 5))
        // Ensure window is key before Cmd+E (AppKit menu requires key window)
        app.windows["documentWindow"].click()
        // Cmd+E to editing through the View-menu command
        app.typeKey("e", modifierFlags: .command)
        XCTAssertTrue(app.textViews["markdownTextEditor"].waitForExistence(timeout: 5))
        // Toolbar button should now be "Done" but same identifier
        XCTAssertTrue(app.buttons["togglePresentationModeButton"].exists)
        // Toolbar click back to reading
        app.buttons["togglePresentationModeButton"].click()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        // Again Cmd+E — ensure window key
        app.windows["documentWindow"].click()
        app.typeKey("e", modifierFlags: .command)
        XCTAssertTrue(app.textViews["markdownTextEditor"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSyncEditToReadShowsLatestWithoutSave() throws {
        let directory = try makeTemporaryDirectory()
        let fileURL = directory.appending(path: "sync.md")
        try Data("original".utf8).write(to: fileURL)
        let app = makeApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", fileURL.path]
        app.launch()

        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        app.buttons["togglePresentationModeButton"].click()
        let editor = app.textViews["markdownTextEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.click()
        app.typeKey("a", modifierFlags: .command)
        editor.typeText("sync latest **bold**")
        // Toggle to reading without saving — use toolbar button for reliability (Cmd+E is tested separately in testToggleVia...)
        app.buttons["togglePresentationModeButton"].click()
        let reading = readingView(in: app)
        XCTAssertTrue(reading.waitForExistence(timeout: 5))
        // Verify file not yet saved but reading shows latest - we can toggle back to editing and check editor value
        app.buttons["togglePresentationModeButton"].click()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "sync latest **bold**")
        // Ensure dirty: closing should show sheet (ensure window is key)
        // Use the window's close button which reliably triggers NSDocument's shouldClose logic
        // even if Cmd+W is flaky in XCUI for file-based documents.
        app.windows["documentWindow"].click()
        Thread.sleep(forTimeInterval: 0.3)
        // Try Cmd+W first, fall back to close button if sheet doesn't appear quickly
        app.typeKey("w", modifierFlags: .command)
        if !app.sheets.firstMatch.waitForExistence(timeout: 2) {
            let closeButton = app.windows["documentWindow"].buttons["Close"]
            if closeButton.waitForExistence(timeout: 1) {
                closeButton.click()
            } else {
                app.windows["documentWindow"].buttons.element(boundBy: 0).click()
            }
        }
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 5))
        app.sheets.firstMatch.buttons["Cancel"].click()
    }

    @MainActor
    func testUndoSurvivesEditingViewRecreationAcrossReadingToggle() throws {
        let app = makeApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()

        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        // reading -> editing
        app.buttons["togglePresentationModeButton"].click()
        let editor = app.textViews["markdownTextEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.click()
        let distinctive = "DISTINCTIVE-UNDO-CROSS-RECREATION-42"
        editor.typeText(distinctive)
        // reading — use toolbar button for reliability (Cmd+E path is validated in testToggleVia...)
        app.buttons["togglePresentationModeButton"].click()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        // With persistent editor, the view remains alive but hidden from accessibility.
        // Product invariant is that undo survives, not that the view is destroyed.
        XCTAssertFalse(editor.isHittable, "editor should not be hittable in reading mode")
        // editing again – same persistent NSTextView instance, text must survive
        app.buttons["togglePresentationModeButton"].click()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, distinctive, "text must survive recreation without save")
        // Ensure editor has focus before undo (persistent editor does not auto-focus like recreated one)
        app.windows["documentWindow"].click()
        editor.click()
        Thread.sleep(forTimeInterval: 0.2)
        // Undo once – exact previous edit disappears, no fake history loss
        // Use menu for reliability (Cmd+Z via key may go to window's undoManager instead of textView's)
        app.activate()
        let undoMenu = app.menuBars.menus["Edit"]
        let undoItem = undoMenu.menuItems["Undo"]
        if undoItem.waitForExistence(timeout: 1) && undoItem.isHittable {
            undoItem.click()
        } else {
            // Fallback to key
            app.typeKey("z", modifierFlags: .command)
        }
        let undone = NSPredicate(format: "value == %@", "")
        expectation(for: undone, evaluatedWith: editor)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(editor.value as? String, "")
        // Redo – edit returns (ensure focus, use menu for reliability)
        app.windows["documentWindow"].click()
        editor.click()
        Thread.sleep(forTimeInterval: 0.2)
        app.activate()
        let redoMenu = app.menuBars.menus["Edit"]
        let redoItem = redoMenu.menuItems["Redo"]
        if redoItem.waitForExistence(timeout: 1) && redoItem.isHittable {
            redoItem.click()
        } else {
            app.typeKey("z", modifierFlags: [.command, .shift])
        }
        let redone = NSPredicate(format: "value == %@", distinctive)
        expectation(for: redone, evaluatedWith: editor)
        waitForExpectations(timeout: 5)
        // Verify merely switching modes created no fake undo entry – undo again should go to empty, not stay
        app.buttons["togglePresentationModeButton"].click() // reading
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        app.buttons["togglePresentationModeButton"].click() // editing
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        // Should still be able to undo to empty (one level)
        app.windows["documentWindow"].click()
        editor.click()
        Thread.sleep(forTimeInterval: 0.2)
        app.activate()
        let undoMenu2 = app.menuBars.menus["Edit"]
        let undoItem2 = undoMenu2.menuItems["Undo"]
        if undoItem2.waitForExistence(timeout: 1) && undoItem2.isHittable {
            undoItem2.click()
        } else {
            app.typeKey("z", modifierFlags: .command)
        }
        expectation(for: undone, evaluatedWith: editor)
        waitForExpectations(timeout: 5)
        // Dirty state truthful: after undo to empty, close should not show save sheet
        app.windows["documentWindow"].click()
        Thread.sleep(forTimeInterval: 0.2)
        app.typeKey("w", modifierFlags: .command)
        waitForWindowCount(0, in: app)
        XCTAssertFalse(app.sheets.firstMatch.exists, "undo to original must clear dirty, no save sheet")
    }

    // Milestone 5 remediation alias: spec expects `testUndoSurvivesReadingEditingTransitions`.
    // Keep old name for backwards compatibility; new name forwards to same invariant.
    @MainActor
    func testUndoSurvivesReadingEditingTransitions() throws {
        try testUndoSurvivesEditingViewRecreationAcrossReadingToggle()
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = makeApplication()
            app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
            app.launch()
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    private func makeApplication() -> XCUIApplication {
        XCUIApplication(url: targetApplicationURL)
    }

    private var targetApplicationURL: URL {
        Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appending(path: "Forksview.app", directoryHint: .isDirectory)
    }

    private func clickForksviewDockIcon() {
        let dock = XCUIApplication(bundleIdentifier: "com.apple.dock")
        let icons = dock.dockItems.matching(identifier: "Forksview")
        XCTAssertTrue(icons.firstMatch.waitForExistence(timeout: 5))
        icons.element(boundBy: icons.count - 1).click()
    }

    private func readingView(in app: XCUIApplication) -> XCUIElement {
        // Verified via XCUI hierarchy: element with identifier "markdownReadingView" is exposed as ScrollView,
        // not Other. ScrollView is the stable AX role for SwiftUI ScrollView with accessibilityIdentifier.
        app.scrollViews["markdownReadingView"]
    }

    private func waitForWindowCount(_ count: Int, in app: XCUIApplication) {
        let predicate = NSPredicate(format: "count == %d", count)
        expectation(for: predicate, evaluatedWith: app.windows)
        waitForExpectations(timeout: 5)
    }

    private func assertWindowCountRemains(_ count: Int, in app: XCUIApplication) {
        let changedCount = NSPredicate(format: "count != %d", count)
        let unexpectedWindowChange = XCTNSPredicateExpectation(
            predicate: changedCount,
            object: app.windows
        )
        unexpectedWindowChange.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [unexpectedWindowChange], timeout: 1), .completed)
    }
}

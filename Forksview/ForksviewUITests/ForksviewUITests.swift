//
//  ForksviewUITests.swift
//  ForksviewUITests
//
//  Created by Michael Buckingham on 8/24/26.
//

import XCTest

@MainActor
final class ForksviewUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testOrdinaryLaunchCreatesExactlyOneUntitledDocumentWindow() throws {
        let app = makeApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()

        let editor = app.textViews["markdownTextEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(app.windows.count, 1)
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

        let editorValues = app.textViews.matching(identifier: "markdownTextEditor")
            .allElementsBoundByIndex
            .compactMap { $0.value as? String }
        XCTAssertEqual(Set(editorValues), ["first cold-open document", "second cold-open document"])
    }

    @MainActor
    func testReopenCreatesUntitledOnlyWhenNoDocumentWindowIsVisible() throws {
        let app = makeApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()

        XCTAssertTrue(app.textViews["markdownTextEditor"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.windows.count, 1)

        app.typeKey("w", modifierFlags: .command)
        waitForWindowCount(0, in: app)
        XCTAssertEqual(app.state, .runningForeground)

        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        XCTAssertEqual(app.state, .runningBackground)
        clickForksviewDockIcon()

        XCTAssertTrue(app.textViews["markdownTextEditor"].waitForExistence(timeout: 5))
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

        let firstEditor = app.textViews["markdownTextEditor"]
        XCTAssertTrue(firstEditor.waitForExistence(timeout: 5))
        firstEditor.click()
        firstEditor.typeText("first document")

        app.typeKey("n", modifierFlags: .command)
        let twoWindows = NSPredicate(format: "count == 2")
        expectation(for: twoWindows, evaluatedWith: app.windows)
        waitForExpectations(timeout: 5)

        let frontEditor = app.windows.firstMatch.textViews["markdownTextEditor"]
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

        let remainingEditor = app.textViews["markdownTextEditor"]
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

        let editor = app.textViews["markdownTextEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, expected)
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertTrue(app.windows.firstMatch.title.contains("launch-fixture"))

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

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
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

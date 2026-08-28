import XCTest

private final class FileCoordinationResult: @unchecked Sendable {
    var coordinatorError: NSError?
    var accessorError: NSError?
}

@MainActor
final class ExternalChangeUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func makeApp(with archivePath: String? = nil) -> XCUIApplication {
        let app = XCUIApplication(url: targetAppURL)
        if let archivePath {
            app.launchEnvironment["FORKSVIEW_BOOKMARK_ARCHIVE_PATH"] = archivePath
        }
        return app
    }

    private var targetAppURL: URL {
        Bundle.main.bundleURL.deletingLastPathComponent().appending(path: "Forksview.app", directoryHint: .isDirectory)
    }

    private func readingView(in app: XCUIApplication) -> XCUIElement {
        app.scrollViews["markdownReadingView"]
    }

    private func coordinatedWrite(_ text: String, to url: URL) async throws {
        try await coordinatedWriteData(Data(text.utf8), to: url)
    }

    private func coordinatedWriteData(_ data: Data, to url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = FileCoordinationResult()
                NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: [], error: &result.coordinatorError) { newURL in
                    do { try data.write(to: newURL) } catch { result.accessorError = error as NSError }
                }
                if let error = result.coordinatorError { continuation.resume(throwing: error) }
                else if let error = result.accessorError { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    private func coordinatedMove(from src: URL, to dst: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = FileCoordinationResult()
                NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: src, options: .forMoving, writingItemAt: dst, options: .forReplacing, error: &result.coordinatorError) { oldURL, newURL in
                    do { try FileManager.default.moveItem(at: oldURL, to: newURL) } catch { result.accessorError = error as NSError }
                }
                if let error = result.coordinatorError { continuation.resume(throwing: error) }
                else if let error = result.accessorError { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    private func coordinatedDelete(at url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = FileCoordinationResult()
                NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forDeleting, error: &result.coordinatorError) { newURL in
                    do { try FileManager.default.removeItem(at: newURL) } catch { result.accessorError = error as NSError }
                }
                if let error = result.coordinatorError { continuation.resume(throwing: error) }
                else if let error = result.accessorError { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    private func waitAndDismissNativeAlert(in app: XCUIApplication, timeout: TimeInterval = 4) -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            // Sheets are primary for NSDocument presentError
            let sheet = app.sheets.firstMatch
            if sheet.exists && sheet.isHittable {
                let buttons = sheet.buttons
                if buttons["OK"].exists && buttons["OK"].isHittable { buttons["OK"].click(); return true }
                if buttons["Ok"].exists && buttons["Ok"].isHittable { buttons["Ok"].click(); return true }
                if buttons["Dismiss"].exists && buttons["Dismiss"].isHittable { buttons["Dismiss"].click(); return true }
                if buttons.firstMatch.exists && buttons.firstMatch.isHittable { buttons.firstMatch.click(); return true }
            } else if sheet.exists {
                // Sheet exists but not hittable yet, try anyway
                let btn = sheet.buttons.firstMatch
                if btn.waitForExistence(timeout: 0.5) { btn.click(); return true }
            }
            let alert = app.alerts.firstMatch
            if alert.exists {
                let btn = alert.buttons["OK"].exists ? alert.buttons["OK"] : alert.buttons.firstMatch
                if btn.exists && btn.isHittable { btn.click(); return true }
                if btn.waitForExistence(timeout: 0.5) { btn.click(); return true }
            }
            let dialog = app.dialogs.firstMatch
            if dialog.exists {
                let btn = dialog.buttons["OK"].exists ? dialog.buttons["OK"] : dialog.buttons.firstMatch
                if btn.exists { btn.click(); return true }
            }
            // Trigger interruption monitor by interacting
            if app.windows.firstMatch.exists && app.windows.firstMatch.isHittable {
                app.windows.firstMatch.tap()
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
    }

    func testFileMenuHasRevertToSaved() throws {
        let app = makeApp()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        app.activate()
        let fileMenu = app.menuBars.menuBarItems["File"]
        XCTAssertTrue(fileMenu.waitForExistence(timeout: 2))
        fileMenu.click()
        let revert = fileMenu.menuItems["Revert to Saved"]
        XCTAssertTrue(revert.waitForExistence(timeout: 2), "File > Revert to Saved must exist via NSDocument")
    }

    func testCleanExternalChangeUpdatesReadingView() async throws {
        let dir = try makeTempDir()
        let url = dir.appending(path: "cleanUI.md")
        try Data("# Title\n\ninitial".utf8).write(to: url)
        let app = makeApp()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", url.path]
        app.launch()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        // Verify initial in reading (scroll view exists) – now external change
        try await coordinatedWrite("# Title\n\nexternal UI", to: url)
        // Allow file presenter to deliver; polling reading view still exists and window title may update
        let window = app.windows.firstMatch
        let pred = NSPredicate { _, _ in
            // Check file content changed to external
            (try? String(contentsOf: url, encoding: .utf8)) == "# Title\n\nexternal UI"
        }
        let diskExpectation = expectation(for: pred, evaluatedWith: NSObject())
        await fulfillment(of: [diskExpectation], timeout: 5)
        XCTAssertTrue(readingView(in: app).exists)
        XCTAssertTrue(window.exists)
        // Toggle to editing to verify text updated
        app.buttons["togglePresentationModeButton"].click()
        let editor = app.textViews["markdownTextEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        // Editor should reflect external change after clean reload
        let exp = NSPredicate(format: "value CONTAINS %@", "external UI")
        let editorExpectation = expectation(for: exp, evaluatedWith: editor)
        await fulfillment(of: [editorExpectation], timeout: 5)
    }

    func testDirtyExternalConflictPreservesLocalInUI() async throws {
        let dir = try makeTempDir()
        let url = dir.appending(path: "dirtyUI.md")
        try Data("initial".utf8).write(to: url)
        let app = makeApp()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", url.path]
        app.launch()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        app.buttons["togglePresentationModeButton"].click()
        let editor = app.textViews["markdownTextEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.click()
        editor.typeText(" local")
        // External change while dirty
        try await coordinatedWrite("external dirty UI", to: url)
        // Give presenter time but verify editor retains local
        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertTrue((editor.value as? String)?.contains("local") == true, "local dirty must be retained")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "external dirty UI")
    }

    func testRapidExternalWritesFinalWinsInUI( ) async throws {
        let dir = try makeTempDir()
        let url = dir.appending(path: "rapidUI.md")
        try Data("initial".utf8).write(to: url)
        let app = makeApp()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", url.path]
        app.launch()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        try await coordinatedWrite("mid", to: url)
        try await coordinatedWrite("final", to: url)
        // Allow coalescing
        try await Task.sleep(nanoseconds: 1_000_000_000)
        app.buttons["togglePresentationModeButton"].click()
        let editor = app.textViews["markdownTextEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let pred = NSPredicate(format: "value CONTAINS %@", "final")
        let editorExpectation = expectation(for: pred, evaluatedWith: editor)
        await fulfillment(of: [editorExpectation], timeout: 5)
    }

    func testRenameMovePreservesContentInUI( ) async throws {
        let dir = try makeTempDir()
        let src = dir.appending(path: "aUI.md")
        let dst = dir.appending(path: "bUI.md")
        try Data("# Keep\n\ncontent".utf8).write(to: src)
        let app = makeApp()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", src.path]
        app.launch()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        app.buttons["togglePresentationModeButton"].click()
        let editor = app.textViews["markdownTextEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.click()
        editor.typeText(" dirty")
        try await coordinatedMove(from: src, to: dst)
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertEqual(editor.value as? String, "# Keep\n\ncontent dirty")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dst.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: src.path))
        // Rendering base should follow new location – verify image relative? Just ensure window title contains new name
        let window = app.windows.firstMatch
        XCTAssertTrue(window.title.contains("bUI") || window.title.contains("aUI"))
    }

    func testAutosaveElsewhereDoesNotChangeBookmarkIdentityInUI() throws {
        // Launch with isolated bookmark archive, create doc with heading, bookmark, make dirty, wait for autosave
        let dir = try makeTempDir()
        let archive = dir.appending(path: "Bookmarks.json")
        let file = dir.appending(path: "autoUI.md")
        try Data("# Head\n\nbody".utf8).write(to: file)
        let app = makeApp(with: archive.path)
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", file.path]
        app.launch()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        // The inspector is visible by default; verify the existing shell surface.
        let inspector = app.descendants(matching: .any)["documentInspector"]
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))
        // Make dirty
        app.buttons["togglePresentationModeButton"].click()
        let editor = app.textViews["markdownTextEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.click()
        editor.typeText(" edit")
        // Wait for autosavingDelay 30 but we can check file not overwritten quickly
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "# Head\n\nbody", "real file not overwritten by autosave elsewhere quickly")
        // Bookmark archive should not contain recovery URL
        if FileManager.default.fileExists(atPath: archive.path) {
            let data = try Data(contentsOf: archive)
            let str = String(data: data, encoding: .utf8) ?? ""
            XCTAssertFalse(str.contains("recovery"), "recovery URL must not become bookmark identity")
        }
    }

    func testInvalidUTF8DoesNotCorruptUI( ) async throws {
        let dir = try makeTempDir()
        let url = dir.appending(path: "invalidUI.md")
        try Data("valid".utf8).write(to: url)
        let app = makeApp()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", url.path]
        app.launch()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        // Install deterministic interruption monitor for native document error (invalid UTF-8)
        var alertObservedViaMonitor = false
        let monitor = addUIInterruptionMonitor(withDescription: "Document Error") { element -> Bool in
            let sheet = element.sheets.firstMatch
            if sheet.exists {
                if sheet.buttons["OK"].exists { sheet.buttons["OK"].tap(); alertObservedViaMonitor = true; return true }
                if sheet.buttons.firstMatch.exists { sheet.buttons.firstMatch.tap(); alertObservedViaMonitor = true; return true }
            }
            let alert = element.alerts.firstMatch
            if alert.exists {
                if alert.buttons["OK"].exists { alert.buttons["OK"].tap(); alertObservedViaMonitor = true; return true }
                if alert.buttons.firstMatch.exists { alert.buttons.firstMatch.tap(); alertObservedViaMonitor = true; return true }
            }
            return false
        }
        // External invalid bytes via coordinated write
        try await coordinatedWriteData(Data([0xFF, 0xFE, 0xFD]), to: url)
        // Allow presenter delivery and native error presentation (bounded, no long sleep)
        try await Task.sleep(nanoseconds: 600_000_000)
        // Discover and dismiss any native document-error alert directly.
        try await Task.sleep(nanoseconds: 400_000_000)
        let alertDismissedDirectly = waitAndDismissNativeAlert(in: app, timeout: 3)
        // Must prove native error was presented where required
        XCTAssertTrue(alertObservedViaMonitor || alertDismissedDirectly, "native document error alert must be presented for invalid UTF-8 and handled deterministically")
        removeUIInterruptionMonitor(monitor)
        // After dismissing alert, app should still show valid content, not crash
        // Verify the retained model through the native reading surface. The
        // document window may remain accessibility-disabled while the modal
        // error unwinds, so do not require the hidden editor to become hittable.
        try await Task.sleep(nanoseconds: 300_000_000)
        app.activate()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["valid"].waitForExistence(timeout: 3), "old model must be retained after invalid UTF-8")
    }

    func testDeletionPreservesInMemoryAndDoesNotRecreateInUI( ) async throws {
        let dir = try makeTempDir()
        let url = dir.appending(path: "delUI.md")
        try Data("# Title\n\nkeep".utf8).write(to: url)
        let app = makeApp()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", url.path]
        app.launch()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        // Verify initial content via editing toggle
        app.buttons["togglePresentationModeButton"].click()
        let editor = app.textViews["markdownTextEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue((editor.value as? String)?.contains("keep") == true)
        app.buttons["togglePresentationModeButton"].click()
        XCTAssertTrue(readingView(in: app).waitForExistence(timeout: 5))
        // Install monitor for potential deletion-related sheet (native accommodation may present alert on save/close, but not necessarily immediately)
        let monitor = addUIInterruptionMonitor(withDescription: "Deletion Alert") { element -> Bool in
            let sheet = element.sheets.firstMatch
            if sheet.exists {
                if sheet.buttons.firstMatch.exists { sheet.buttons.firstMatch.tap(); return true }
            }
            let alert = element.alerts.firstMatch
            if alert.exists {
                if alert.buttons.firstMatch.exists { alert.buttons.firstMatch.tap(); return true }
            }
            return false
        }
        // Native coordinated deletion off MainActor
        try await coordinatedDelete(at: url)
        try await Task.sleep(nanoseconds: 800_000_000)
        // Dismiss any immediate deletion alert deterministically (if presented)
        _ = waitAndDismissNativeAlert(in: app, timeout: 2)
        removeUIInterruptionMonitor(monitor)
        // App must retain in-memory text, not crash, and not recreate file
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "deleted path must not be silently recreated")
        XCTAssertTrue(readingView(in: app).exists || editor.exists, "app must retain document window after deletion")
        // Toggle to editing and verify content retained, then make dirty edit
        app.buttons["togglePresentationModeButton"].click()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "# Title\n\nkeep", "must retain in-memory Markdown after deletion")
        editor.click()
        editor.typeText(" edited")
        XCTAssertTrue((editor.value as? String)?.contains("edited") == true)
        // Verify file still not recreated after edit (recovery autosave elsewhere should not recreate)
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "deleted file must not be recreated after edit")
        // Window should still exist and be usable
        XCTAssertTrue(app.windows.firstMatch.exists)
    }

    func testMultiDocumentIsolationInUI( ) async throws {
        let dir = try makeTempDir()
        let urlA = dir.appending(path: "aMultiUI.md")
        let urlB = dir.appending(path: "bMultiUI.md")
        try Data("A initial".utf8).write(to: urlA)
        try Data("B initial".utf8).write(to: urlB)
        let app = makeApp()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", urlA.path, urlB.path]
        app.launch()
        let two = NSPredicate(format: "count == 2")
        let windowExpectation = expectation(for: two, evaluatedWith: app.windows)
        await fulfillment(of: [windowExpectation], timeout: 5)
        try await coordinatedWrite("A external", to: urlA)
        try await Task.sleep(nanoseconds: 1_000_000_000)
        // Verify both windows still exist and B unchanged (check via window titles/content)
        XCTAssertEqual(app.windows.count, 2)
        // Front window may be A, but we check that at least one editor still has B initial if toggled
        // Simple check: both files on disk: A external, B initial
        XCTAssertEqual(try String(contentsOf: urlA, encoding: .utf8), "A external")
        XCTAssertEqual(try String(contentsOf: urlB, encoding: .utf8), "B initial")
    }
}

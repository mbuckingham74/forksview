import AppKit
import SwiftUI

// MARK: - RendererSpikeHost
// Milestone 4 acceptance harness — deliberately temporary, not Milestone 5.
// This is the smallest executable path that exercises the real MarkdownReadingView
// with real fixture content and real baseURL behavior. It does NOT replace the
// native NSDocument editor, does NOT introduce a second document architecture,
// and is clearly marked as a spike to be replaced by the final read/edit toggle.

@MainActor
final class RendererSpikeHost {
    static let shared = RendererSpikeHost()
    private var window: NSWindow?

    private init() {}

    func show() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let (markdown, baseURL) = Self.loadFixture()
        let readingView = MarkdownReadingView(markdown: markdown, baseURL: baseURL)
            .accessibilityIdentifier("renderedMarkdownContent")
        let hosting = NSHostingController(rootView: readingView)
        hosting.view.setAccessibilityIdentifier("rendererSpikeHostingView")

        let window = NSWindow(contentViewController: hosting)
        window.title = "Forksview — Renderer Spike (Milestone 4)"
        window.setContentSize(NSSize(width: 860, height: 700))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("RendererSpikeWindow")
        window.backgroundColor = .textBackgroundColor
        window.setAccessibilityIdentifier("rendererSpikeWindow")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window

        // Ensure window closes cleanly and reference is cleared.
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.window = nil
        }
    }

    // MARK: - Fixture loading

    static func loadFixture() -> (markdown: String, baseURL: URL?) {
        if let url = locateFixtureURL(), let content = try? String(contentsOf: url, encoding: .utf8) {
            return (content, url.deletingLastPathComponent())
        }
        // Fallback: minimal content explaining missing fixture (never crash).
        let fallback = """
        # Fixture not found

        The acceptance fixture could not be located. Expected at:
        `Forksview/Forksview/Fixtures/AcceptanceFixture.md`

        This window proves MarkdownReadingView is exercised, but the full fixture
        is missing from the bundle/filesystem search.
        """
        return (fallback, nil)
    }

    /// Searches bundle first (if Fixtures still ships), then filesystem fallbacks.
    /// Mirrors the test helper so spike works even if Fixtures are later excluded
    /// from the production bundle via synchronized-group exceptions.
    static func locateFixtureURL() -> URL? {
        let bundles: [Bundle] = [.main, Bundle(for: RendererSpikeHost.self)]
        for bundle in bundles {
            if let url = bundle.url(forResource: "AcceptanceFixture", withExtension: "md") {
                return url
            }
            if let url = bundle.url(forResource: "AcceptanceFixture", withExtension: "md", subdirectory: "Fixtures") {
                return url
            }
            // Also try Fixtures folder as resource subdirectory via path search.
            if let path = bundle.path(forResource: "AcceptanceFixture", ofType: "md", inDirectory: "Fixtures"),
               let url = URL(string: "file://\(path)") {
                return url
            }
        }
        // Filesystem fallbacks — works when running from repo checkout via Xcode.
        let fm = FileManager.default
        let candidatePaths: [String] = [
            "Forksview/Forksview/Fixtures/AcceptanceFixture.md",
            "Forksview/Fixtures/AcceptanceFixture.md",
            "Fixtures/AcceptanceFixture.md",
        ]
        let searchRoots: [URL] = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent(),
            URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent(),
            URL(fileURLWithPath: #filePath).deletingLastPathComponent(),
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
}

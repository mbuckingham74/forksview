import SwiftUI
import AppKit

/// Milestone 6: Application shell that establishes the three-pane layout around
/// the existing document reading/editing component.
///
/// Hierarchy target:
///   NSDocumentController
///   └── MarkdownDocument
///       └── MarkdownDocumentWindowController
///           └── NSWindow
///               └── NSHostingController<DocumentShellView>
///                   └── DocumentShellView
///                       ├── NavigationSplitView (two-column)
///                       │   ├── HistorySidebarPlaceholderView
///                       │   └── DocumentRootView (center canvas)
///                       └── inspector
///                           └── DocumentInspectorPlaceholderView
///
/// Uses native two-column NavigationSplitView + .inspector(isPresented:),
/// preserving DocumentRootView as the center document content and moving
/// toolbar ownership to the shell.

@MainActor
struct DocumentShellView: View {
    @ObservedObject var document: MarkdownDocument
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isInspectorPresented: Bool = true
    @State private var navigationRequest: DocumentNavigationRequest? = nil

    private var isSidebarVisible: Bool { columnVisibility == .all }

    // Derived outline recomputed synchronously from current source (no cache, no debounce)
    private var outline: [DocumentOutlineItem] {
        DocumentOutlineParser.outline(from: document.text)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            HistorySidebarPlaceholderView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            DocumentRootView(document: document, outline: outline, navigationRequest: $navigationRequest)
                .frame(minWidth: 420)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("centerDocumentRegion")
        }
        .navigationSplitViewStyle(.balanced)
        .inspector(isPresented: $isInspectorPresented) {
            DocumentInspectorPlaceholderView(
                outline: outline,
                bookmarks: document.bookmarks,
                onSelect: { item in
                    navigationRequest = DocumentNavigationRequest(anchor: DocumentAnchor(from: item))
                },
                onToggleBookmark: { item in
                    document.toggleBookmark(for: item, in: outline)
                },
                onSelectBookmark: { bookmark in
                    if case let .resolved(item) = DocumentBookmarkResolver.resolve(bookmark, in: outline) {
                        // Reuse exact existing M7 route: bookmark -> resolvedOutlineItem -> DocumentAnchor -> fresh navigationRequest
                        navigationRequest = DocumentNavigationRequest(anchor: DocumentAnchor(from: item))
                    }
                },
                onRemoveBookmark: { bookmark in
                    document.removeBookmark(id: bookmark.id)
                },
                isEditing: document.presentationMode == .editing
            )
            .inspectorColumnWidth(min: 220, ideal: 260, max: 360)
        }
        .toolbar { toolbarContent }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("documentShell")
        .onChange(of: document.presentationMode) { _, newMode in
            if newMode == .reading, let anchor = document.lastAnchor {
                // Reuse anchor for edit-to-reading restoration; this uses real parser now
                // Only navigate if anchor corresponds to a heading that still exists
                let currentOutline = DocumentOutlineParser.outline(from: document.text)
                let isStale = !currentOutline.contains(where: { $0.sourceRange.location == anchor.offset && $0.title == anchor.heading })
                // If no heading, don't navigate (allow normal reading top)
                if anchor.heading != nil && !isStale {
                    navigationRequest = DocumentNavigationRequest(anchor: anchor)
                } else if anchor.heading == nil {
                    // No heading anchor, clear any pending navigation
                }
            }
        }
        .onChange(of: document.externalReloadNavigationRequest) { _, newReq in
            if let req = newReq {
                navigationRequest = req
                // Clear after forwarding on the next main-actor turn so the
                // request remains a transient M7 navigation event.
                Task { @MainActor in
                    await Task.yield()
                    if document.externalReloadNavigationRequest?.token == req.token {
                        document.externalReloadNavigationRequest = nil
                    }
                }
            }
        }
        .onChange(of: columnVisibility) { _, newValue in
            if newValue == .detailOnly {
                rescueFocusIfNeeded(forHiddenPane: "historySidebar", fallbackToggleIdentifier: "toggleSidebarButton")
            }
        }
        .onChange(of: isInspectorPresented) { _, isPresented in
            if !isPresented {
                rescueFocusIfNeeded(forHiddenPane: "documentInspector", fallbackToggleIdentifier: "toggleInspectorButton")
            }
        }
    }

    private func toggleSidebar() {
        withAnimation {
            if columnVisibility == .all {
                columnVisibility = .detailOnly
            } else {
                columnVisibility = .all
            }
        }
    }

    private func rescueFocusIfNeeded(forHiddenPane paneIdentifier: String, fallbackToggleIdentifier: String) {
        DispatchQueue.main.async {
            guard let window = document.windowControllers.first?.window ?? NSApp.keyWindow,
                  let contentView = window.contentView else { return }
            guard let firstResponder = window.firstResponder as? NSView else { return }
            // Determine if firstResponder is inside the hidden pane
            if isView(firstResponder, insideIdentifier: paneIdentifier, root: contentView) {
                // Try to focus the corresponding toolbar toggle, otherwise center region
                if let toggle = findView(withIdentifier: fallbackToggleIdentifier, in: contentView) {
                    window.makeFirstResponder(toggle)
                } else if let center = findView(withIdentifier: "centerDocumentRegion", in: contentView) {
                    // If reading view is active, prefer its scroll view; otherwise fallback to center
                    if let reading = findView(withIdentifier: "markdownReadingView", in: contentView) {
                        // Make reading view first responder if it can become it; else center
                        if reading.acceptsFirstResponder {
                            window.makeFirstResponder(reading)
                        } else {
                            // Attempt to make its enclosing scroll view first responder
                            window.makeFirstResponder(reading)
                            if window.firstResponder !== reading, let scrollAncestor = reading.enclosingScrollView {
                                window.makeFirstResponder(scrollAncestor)
                            }
                        }
                    } else {
                        window.makeFirstResponder(center)
                    }
                } else if let reading = findView(withIdentifier: "markdownReadingView", in: contentView) {
                    window.makeFirstResponder(reading)
                } else if let editor = findView(withIdentifier: "markdownTextEditor", in: contentView) {
                    window.makeFirstResponder(editor)
                }
            }
        }
    }

    private func isView(_ view: NSView, insideIdentifier identifier: String, root: NSView) -> Bool {
        // Walk up from view to root, checking ancestor identifiers
        var current: NSView? = view
        while let c = current {
            if c.accessibilityIdentifier() == identifier {
                return true
            }
            if c === root { break }
            current = c.superview
        }
        // Also check if the hidden pane ancestor exists and view is descendant of it via hierarchy search
        if let pane = findView(withIdentifier: identifier, in: root) {
            return view.isDescendant(of: pane)
        }
        return false
    }

    private func findView(withIdentifier identifier: String, in root: NSView) -> NSView? {
        if root.accessibilityIdentifier() == identifier {
            return root
        }
        for sub in root.subviews {
            if let found = findView(withIdentifier: identifier, in: sub) {
                return found
            }
        }
        return nil
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(action: toggleSidebar) {
                Label(isSidebarVisible ? "Hide History Sidebar" : "Show History Sidebar", systemImage: "sidebar.left")
            }
            .help(isSidebarVisible ? "Hide History Sidebar" : "Show History Sidebar")
            .accessibilityLabel(isSidebarVisible ? "Hide History Sidebar" : "Show History Sidebar")
            .accessibilityValue(isSidebarVisible ? "Shown" : "Hidden")
            .accessibilityIdentifier("toggleSidebarButton")
        }
        ToolbarItem(placement: .primaryAction) {
            Button(action: { isInspectorPresented.toggle() }) {
                Label(isInspectorPresented ? "Hide Inspector" : "Show Inspector", systemImage: "sidebar.right")
            }
            .help(isInspectorPresented ? "Hide Inspector" : "Show Inspector")
            .accessibilityLabel(isInspectorPresented ? "Hide Inspector" : "Show Inspector")
            .accessibilityValue(isInspectorPresented ? "Shown" : "Hidden")
            .accessibilityIdentifier("toggleInspectorButton")
        }
        ToolbarItem(placement: .primaryAction) {
            Button(action: { document.togglePresentationMode(nil) }) {
                Label(
                    document.presentationMode == .reading ? "Edit document" : "Show reading view",
                    systemImage: document.presentationMode == .reading ? "pencil" : "eye"
                )
            }
            .help(document.presentationMode == .reading ? "Edit (⌘E)" : "Done — Back to Reading (⌘E)")
            .accessibilityValue(document.presentationMode == .reading ? "Reading mode" : "Editing mode")
            .accessibilityIdentifier("togglePresentationModeButton")
        }
    }
}

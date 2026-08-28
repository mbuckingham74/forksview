import SwiftUI

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
                }
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

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(action: toggleSidebar) {
                Label("Toggle History", systemImage: "sidebar.left")
            }
            .help("Toggle History Sidebar")
            .accessibilityIdentifier("toggleSidebarButton")
        }
        ToolbarItem(placement: .primaryAction) {
            Button(action: { isInspectorPresented.toggle() }) {
                Label("Toggle Inspector", systemImage: "sidebar.right")
            }
            .help("Toggle Inspector")
            .accessibilityIdentifier("toggleInspectorButton")
        }
        ToolbarItem(placement: .primaryAction) {
            Button(action: { document.togglePresentationMode(nil) }) {
                Label(
                    document.presentationMode == .reading ? "Edit" : "Done",
                    systemImage: document.presentationMode == .reading ? "pencil" : "eye"
                )
            }
            .help(document.presentationMode == .reading ? "Edit (⌘E)" : "Done — Back to Reading (⌘E)")
            .accessibilityIdentifier("togglePresentationModeButton")
        }
    }
}

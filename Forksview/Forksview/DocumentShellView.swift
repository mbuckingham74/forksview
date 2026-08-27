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

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            HistorySidebarPlaceholderView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            DocumentRootView(document: document)
                .frame(minWidth: 420)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("centerDocumentRegion")
        }
        .navigationSplitViewStyle(.balanced)
        .inspector(isPresented: $isInspectorPresented) {
            DocumentInspectorPlaceholderView()
                .inspectorColumnWidth(min: 220, ideal: 260, max: 360)
        }
        .toolbar { toolbarContent }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("documentShell")
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

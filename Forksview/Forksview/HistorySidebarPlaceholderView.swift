import SwiftUI

@MainActor
struct HistorySidebarPlaceholderView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("History")
                    .font(.headline)
                Text("No history yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("History sidebar")
        .accessibilityIdentifier("historySidebar")
    }
}

import SwiftUI

@MainActor
struct DocumentInspectorPlaceholderView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("On This Page")
                        .font(.headline)
                    Text("Outline coming in a later milestone")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Bookmarks")
                        .font(.headline)
                    Text("No bookmarks yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("documentInspector")
    }
}

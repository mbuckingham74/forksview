import SwiftUI

@MainActor
struct DocumentInspectorPlaceholderView: View {
    var outline: [DocumentOutlineItem] = []
    var onSelect: ((DocumentOutlineItem) -> Void)? = nil

    // Default init for backward compat / previews
    init() {
        self.outline = []
        self.onSelect = nil
    }

    init(outline: [DocumentOutlineItem], onSelect: @escaping (DocumentOutlineItem) -> Void) {
        self.outline = outline
        self.onSelect = onSelect
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("On This Page")
                        .font(.headline)
                        .accessibilityIdentifier("onThisPageSection")
                    // Outline container
                    Group {
                        if outline.isEmpty {
                            Text("No headings")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("documentOutline")
                        } else {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(outline) { item in
                                    let occurrence = occurrenceInfo(for: item)
                                    let label: String = {
                                        let base = "\(item.title), heading level \(item.level)"
                                        if occurrence.total > 1 {
                                            return "\(base), \(occurrence.index) of \(occurrence.total)"
                                        }
                                        return base
                                    }()
                                    Button(action: {
                                        onSelect?(item)
                                    }) {
                                        Text(item.title)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                            .multilineTextAlignment(.leading)
                                            .lineLimit(2)
                                            .truncationMode(.tail)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.leading, CGFloat(max(0, item.level - 1)) * 12)
                                            .padding(.vertical, 4)
                                            .padding(.horizontal, 6)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(label)
                                    .accessibilityIdentifier("documentOutlineItem-\(item.sourceRange.location)")
                                    .help(item.title)
                                }
                            }
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("documentOutline")
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("onThisPageSection")

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

    private func occurrenceInfo(for item: DocumentOutlineItem) -> (index: Int, total: Int) {
        let same = outline.filter { $0.level == item.level && $0.title == item.title }
        let total = same.count
        guard let idx = same.firstIndex(of: item) else { return (1, total) }
        return (idx + 1, total)
    }
}

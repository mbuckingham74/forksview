import SwiftUI
import MarkdownUI

/// App-owned reading view. This is the only place Forksview depends on MarkdownUI.
/// The rest of the app uses this view without importing renderer-specific APIs.
///
/// Milestone 4: The view now configures hybrid image providers so both network
/// (`http`/`https`) and local filesystem (`file:`) Markdown images render.
/// Relative image sources are resolved against `baseURL` (typically the document's
/// directory). The provider split keeps all renderer-specific behavior inside this
/// reading layer — `MarkdownDocument` only supplies an ordinary directory URL.
@MainActor
struct MarkdownReadingView: View {
    let markdown: String
    let baseURL: URL?

    init(markdown: String, baseURL: URL? = nil) {
        self.markdown = markdown
        self.baseURL = baseURL
    }

    var body: some View {
        ScrollView(.vertical) {
            Markdown(markdown, baseURL: baseURL)
                .markdownTheme(.gitHub)
                .markdownImageProvider(HybridBlockImageProvider())
                .markdownInlineImageProvider(HybridInlineImageProvider())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("markdownReadingView")
    }
}

#Preview {
    MarkdownReadingView(
        markdown: """
        # Hello MarkdownUI

        This is **bold**, *italic*, and a [link](https://example.com).

        - task one
        - [x] completed
        - [ ] open

        | A | B |
        | --- | --- |
        | 1 | 2 |

        ```swift
        let x = 42
        ```

        ![Remote](https://picsum.photos/200/100)
        """,
        baseURL: nil
    )
    .frame(width: 600, height: 400)
}

import SwiftUI
import MarkdownUI

/// App-owned reading view. This is the only place Forksview depends on MarkdownUI.
/// The rest of the app uses this view without importing renderer-specific APIs.
///
/// Milestone 7: Wraps reading scroll with ScrollViewReader and publishes heading
/// targets via public Theme block-style APIs. Each heading publishes level, plain
/// title, and a transient UUID for scrollTo. Duplicate handling via (level, title,
/// occurrence) resolver. Stale requests discarded, pending retained until targets
/// for newest source snapshot publish.

@MainActor
struct MarkdownReadingView: View {
    let markdown: String
    let baseURL: URL?
    var outline: [DocumentOutlineItem] = []
    @Binding var navigationRequest: DocumentNavigationRequest?

    init(markdown: String, baseURL: URL? = nil, outline: [DocumentOutlineItem] = [], navigationRequest: Binding<DocumentNavigationRequest?> = .constant(nil)) {
        self.markdown = markdown
        self.baseURL = baseURL
        self.outline = outline
        self._navigationRequest = navigationRequest
    }

    @State private var renderedTargets: [RenderedHeadingTarget] = []
    @State private var pendingRequest: DocumentNavigationRequest? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                Markdown(markdown, baseURL: baseURL)
                    .markdownTheme(readingTheme)
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
            .onPreferenceChange(RenderedHeadingsPreferenceKey.self) { newTargets in
                renderedTargets = newTargets
                if let pending = pendingRequest {
                    if attemptScroll(for: pending, proxy: proxy, outline: outline) {
                        pendingRequest = nil
                    } else if OutlineRenderedResolver.isStale(request: pending, outline: outline) {
                        pendingRequest = nil
                    }
                } else if let req = navigationRequest {
                    if !attemptScroll(for: req, proxy: proxy, outline: outline) {
                        if OutlineRenderedResolver.isStale(request: req, outline: outline) {
                        } else {
                            pendingRequest = req
                        }
                    }
                }
            }
            .onChange(of: navigationRequest) { _, newReq in
                guard let req = newReq else { return }
                if OutlineRenderedResolver.isStale(request: req, outline: outline) {
                    return
                }
                if !attemptScroll(for: req, proxy: proxy, outline: outline) {
                    pendingRequest = req
                } else {
                    pendingRequest = nil
                }
            }
            .onChange(of: markdown) { _, _ in
            }
            .onChange(of: outline) { _, newOutline in
                if let pending = pendingRequest, OutlineRenderedResolver.isStale(request: pending, outline: newOutline) {
                    pendingRequest = nil
                }
                if let req = navigationRequest, OutlineRenderedResolver.isStale(request: req, outline: newOutline) {
                    pendingRequest = nil
                }
            }
        }
    }

    private func attemptScroll(for request: DocumentNavigationRequest, proxy: ScrollViewProxy, outline: [DocumentOutlineItem]) -> Bool {
        guard let outlineItem = outline.first(where: { $0.sourceRange.location == request.anchor.offset }) ?? outline.first(where: { $0.sourceRange.location == request.anchor.offset && $0.title == request.anchor.heading }) else {
            return true
        }
        guard let target = OutlineRenderedResolver.resolve(outlineItem: outlineItem, outline: outline, renderedTargets: renderedTargets) else {
            return false
        }
        let shouldAnimate = !reduceMotion
        if shouldAnimate {
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(target.id, anchor: .top)
            }
        } else {
            proxy.scrollTo(target.id, anchor: .top)
        }
        return true
    }

    private var readingTheme: Theme {
        Theme.gitHub
            .heading1 { cfg in
                let plain = cfg.content.renderPlainText().trimmingCharacters(in: .whitespacesAndNewlines)
                let hid = UUID()
                VStack(alignment: .leading, spacing: 0) {
                    cfg.label
                        .relativePadding(.bottom, length: .em(0.3))
                        .relativeLineSpacing(.em(0.125))
                        .markdownMargin(top: 24, bottom: 16)
                        .markdownTextStyle {
                            FontWeight(.semibold)
                            FontSize(.em(2))
                        }
                    Divider().overlay(readingDivider)
                }
                .id(hid)
                .preference(key: RenderedHeadingsPreferenceKey.self, value: [RenderedHeadingTarget(id: hid, level: 1, plainTitle: plain)])
            }
            .heading2 { cfg in
                let plain = cfg.content.renderPlainText().trimmingCharacters(in: .whitespacesAndNewlines)
                let hid = UUID()
                VStack(alignment: .leading, spacing: 0) {
                    cfg.label
                        .relativePadding(.bottom, length: .em(0.3))
                        .relativeLineSpacing(.em(0.125))
                        .markdownMargin(top: 24, bottom: 16)
                        .markdownTextStyle {
                            FontWeight(.semibold)
                            FontSize(.em(1.5))
                        }
                    Divider().overlay(readingDivider)
                }
                .id(hid)
                .preference(key: RenderedHeadingsPreferenceKey.self, value: [RenderedHeadingTarget(id: hid, level: 2, plainTitle: plain)])
            }
            .heading3 { cfg in
                let plain = cfg.content.renderPlainText().trimmingCharacters(in: .whitespacesAndNewlines)
                let hid = UUID()
                cfg.label
                    .relativeLineSpacing(.em(0.125))
                    .markdownMargin(top: 24, bottom: 16)
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(1.25))
                    }
                    .id(hid)
                    .preference(key: RenderedHeadingsPreferenceKey.self, value: [RenderedHeadingTarget(id: hid, level: 3, plainTitle: plain)])
            }
            .heading4 { cfg in
                let plain = cfg.content.renderPlainText().trimmingCharacters(in: .whitespacesAndNewlines)
                let hid = UUID()
                cfg.label
                    .relativeLineSpacing(.em(0.125))
                    .markdownMargin(top: 24, bottom: 16)
                    .markdownTextStyle {
                        FontWeight(.semibold)
                    }
                    .id(hid)
                    .preference(key: RenderedHeadingsPreferenceKey.self, value: [RenderedHeadingTarget(id: hid, level: 4, plainTitle: plain)])
            }
            .heading5 { cfg in
                let plain = cfg.content.renderPlainText().trimmingCharacters(in: .whitespacesAndNewlines)
                let hid = UUID()
                cfg.label
                    .relativeLineSpacing(.em(0.125))
                    .markdownMargin(top: 24, bottom: 16)
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(0.875))
                    }
                    .id(hid)
                    .preference(key: RenderedHeadingsPreferenceKey.self, value: [RenderedHeadingTarget(id: hid, level: 5, plainTitle: plain)])
            }
            .heading6 { cfg in
                let plain = cfg.content.renderPlainText().trimmingCharacters(in: .whitespacesAndNewlines)
                let hid = UUID()
                cfg.label
                    .relativeLineSpacing(.em(0.125))
                    .markdownMargin(top: 24, bottom: 16)
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(0.85))
                        ForegroundColor(readingTertiary)
                    }
                    .id(hid)
                    .preference(key: RenderedHeadingsPreferenceKey.self, value: [RenderedHeadingTarget(id: hid, level: 6, plainTitle: plain)])
            }
    }

    private var readingDivider: Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ?
                NSColor(red: 0x33/255.0, green: 0x34/255.0, blue: 0x38/255.0, alpha: 1) :
                NSColor(red: 0xd0/255.0, green: 0xd0/255.0, blue: 0xd3/255.0, alpha: 1)
        }))
    }

    private var readingTertiary: Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ?
                NSColor(red: 0x6d/255.0, green: 0x70/255.0, blue: 0x7d/255.0, alpha: 1) :
                NSColor(red: 0x6b/255.0, green: 0x6e/255.0, blue: 0x7b/255.0, alpha: 1)
        }))
    }
}

private struct RenderedHeadingsPreferenceKey: PreferenceKey {
    static var defaultValue: [RenderedHeadingTarget] = []
    static func reduce(value: inout [RenderedHeadingTarget], nextValue: () -> [RenderedHeadingTarget]) {
        value.append(contentsOf: nextValue())
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

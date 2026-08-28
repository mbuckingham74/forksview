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
/// Milestone 10: Centered readable width, semantic colors, accessible reading region.

@MainActor
struct MarkdownReadingView: View {
    let markdown: String
    let baseURL: URL?
    let isActive: Bool
    var outline: [DocumentOutlineItem] = []
    @Binding var navigationRequest: DocumentNavigationRequest?

    init(markdown: String, baseURL: URL? = nil, isActive: Bool = true, outline: [DocumentOutlineItem] = [], navigationRequest: Binding<DocumentNavigationRequest?> = .constant(nil)) {
        self.markdown = markdown
        self.baseURL = baseURL
        self.isActive = isActive
        self.outline = outline
        self._navigationRequest = navigationRequest
    }

    @State private var renderedTargets: [RenderedHeadingTarget] = []
    @State private var pendingRequest: DocumentNavigationRequest? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .center, spacing: 0) {
                    Markdown(markdown, baseURL: baseURL)
                        .markdownTheme(readingTheme)
                        .markdownImageProvider(HybridBlockImageProvider())
                        .markdownInlineImageProvider(HybridInlineImageProvider())
                        .textSelection(.enabled)
                        // Centered readable column: max 760, with required padding
                        .frame(maxWidth: 760, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        // Allow wide tables/code to remain usable: do not clip, allow horizontal scroll if content exceeds readable width
                        // The Markdown container itself is constrained to 760 but internal scrollable elements (code/table) handle overflow
                        .fixedSize(horizontal: false, vertical: false)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                // SwiftUI's focus system does not make a ScrollView an AppKit
                // first responder on macOS. Keep the renderer in SwiftUI, but
                // place a hidden native responder in this scroll view's content
                // so keyboard scrolling is a real event path.
                .background {
                    ReadingKeyboardFocusView(isActive: isActive)
                        .frame(width: 1, height: 1)
                        .accessibilityHidden(true)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Markdown document")
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
        Color(nsColor: .separatorColor)
    }

    private var readingTertiary: Color {
        Color(nsColor: .secondaryLabelColor)
    }
}

private struct ReadingKeyboardFocusView: NSViewRepresentable {
    let isActive: Bool

    func makeNSView(context: Context) -> ReadingKeyboardFocusNSView {
        ReadingKeyboardFocusNSView(isActive: isActive)
    }

    func updateNSView(_ nsView: ReadingKeyboardFocusNSView, context: Context) {
        nsView.isActive = isActive
        if isActive {
            nsView.requestFocus()
        } else if nsView.window?.firstResponder === nsView {
            nsView.window?.makeFirstResponder(nil)
        }
    }
}

@MainActor
private final class ReadingKeyboardFocusNSView: NSView {
    var isActive: Bool

    init(isActive: Bool) {
        self.isActive = isActive
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { isActive }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        requestFocus()
    }

    func requestFocus() {
        guard isActive, let window else { return }
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, self.isActive, let window else { return }
            window.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isActive, let scrollView = enclosingScrollView else {
            super.keyDown(with: event)
            return
        }

        let clipView = scrollView.contentView
        var origin = clipView.bounds.origin
        let lineDistance = max(24, clipView.bounds.height * 0.1)
        let pageDistance = max(24, clipView.bounds.height * 0.9)

        switch event.keyCode {
        case 126: // Up arrow
            origin.y -= lineDistance
        case 125: // Down arrow
            origin.y += lineDistance
        case 116: // Page Up
            origin.y -= pageDistance
        case 121: // Page Down
            origin.y += pageDistance
        default:
            super.keyDown(with: event)
            return
        }

        let documentHeight = scrollView.documentView?.frame.height ?? 0
        let maximumY = max(0, documentHeight - clipView.bounds.height)
        origin.y = min(max(0, origin.y), maximumY)
        clipView.scroll(to: origin)
        scrollView.reflectScrolledClipView(clipView)
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

import AppKit
import SwiftUI
import MarkdownUI

// MARK: - MarkdownImageResolver
// Pure helpers for URL resolution; kept app-owned and testable without SwiftUI rendering.
// This remains compatible with future renderer replacement.

enum MarkdownImageResolver {
    /// Resolves a Markdown image source string against a base URL, mirroring MarkdownUI's internal logic.
    static func resolvedURL(for source: String, baseURL: URL?) -> URL? {
        URL(string: source, relativeTo: baseURL)
    }

    /// True only for file: URLs that can be loaded from the local filesystem.
    static func isLocalFileURL(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.isFileURL
    }

    /// Whether a local file URL points to an existing file on disk.
    static func localFileExists(at url: URL?) -> Bool {
        guard let url, url.isFileURL else { return false }
        // url.path may be percent-encoded; using path(percentEncoded:false) equivalent via .path
        return FileManager.default.fileExists(atPath: url.path)
    }
}

// MARK: - Hybrid Block Image Provider
// Routes file: URLs to local filesystem, http/https to network (via MarkdownUI's DefaultImageProvider).

struct HybridBlockImageProvider: ImageProvider {
    private let fallback = DefaultImageProvider()

    func makeImage(url: URL?) -> some View {
        Group {
            if let url, url.isFileURL {
                LocalFileImage(url: url)
            } else {
                fallback.makeImage(url: url)
            }
        }
    }
}

// MARK: - Hybrid Inline Image Provider

struct HybridInlineImageProvider: InlineImageProvider {
    func image(with url: URL, label: String) async throws -> Image {
        if url.isFileURL {
            // Attempt synchronous local load; throw if missing so MarkdownUI can handle gracefully.
            if let nsImage = NSImage(contentsOf: url) {
                return Image(nsImage: nsImage)
            }
            throw URLError(.fileDoesNotExist)
        }
        // Local instance avoids capturing main-actor-isolated state across suspension.
        let fallback = DefaultInlineImageProvider()
        return try await fallback.image(with: url, label: label)
    }
}

// MARK: - LocalFileImage

private struct LocalFileImage: View {
    let url: URL

    var body: some View {
        Group {
            if let nsImage = NSImage(contentsOf: url) {
                // Mirror MarkdownUI's ResizeToFit pattern to avoid unbounded image width.
                LocalResizeToFit(idealSize: nsImage.size) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .accessibilityLabel(url.lastPathComponent)
                }
            } else {
                // Graceful fallback for missing files — no crash, no placeholder asset, just transparent.
                Color.clear
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - LocalResizeToFit
// Local copy of MarkdownUI Demo's ResizeToFit to keep bundled image sizing consistent
// without depending on internal API. Resize only if width exceeds container.

private struct LocalResizeToFit: Layout {
    var idealSize: CGSize

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let view = subviews.first else { return .zero }
        var size = view.sizeThatFits(.unspecified)
        // Prefer image's ideal size unless container is narrower.
        if let width = proposal.width, size.width > width {
            let aspect = size.width / max(size.height, 1)
            size.width = width
            size.height = width / aspect
        } else if idealSize.width > 0, idealSize.height > 0 {
            // Clamp to ideal size if proposal is nil (e.g., preview).
            size = idealSize
        }
        return size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let view = subviews.first else { return }
        view.place(at: bounds.origin, proposal: .init(bounds.size))
    }
}

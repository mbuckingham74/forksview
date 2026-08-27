import Foundation

/// Window/document presentation state for Milestone 5.
/// This is UI state, not persisted Markdown content.
/// Default is reading per product contract.
enum DocumentPresentationMode: String, Equatable, Sendable {
    case reading
    case editing
}

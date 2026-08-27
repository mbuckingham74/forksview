import Foundation

/// Transient navigation request envelope. Token ensures same row twice still observable.
struct DocumentNavigationRequest: Equatable, Sendable {
    let anchor: DocumentAnchor
    let token: UUID

    init(anchor: DocumentAnchor) {
        self.anchor = anchor
        self.token = UUID()
    }

    init(anchor: DocumentAnchor, token: UUID) {
        self.anchor = anchor
        self.token = token
    }
}

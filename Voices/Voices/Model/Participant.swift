import Foundation

struct Participant: Identifiable, Hashable, Sendable {
    let id: UUID
    let displayName: String
}

extension Participant {
    /// Sentinel identities used by the legacy single-user fixtures that
    /// pre-date the multi-user model. New code should always pass a real
    /// Participant; these only exist so existing single-user tests keep
    /// compiling and passing while the multi-user model rolls out.
    static let legacyViewer = Participant(id: UUID(), displayName: "Legacy Viewer")
    static let legacyAuthor = Participant(id: UUID(), displayName: "Legacy Author")
}

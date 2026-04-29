import Foundation

struct Participant: Identifiable, Hashable, Sendable {
    let id: UUID
    let displayName: String
}

extension Participant {
    /// Single-user-mode identities. Single-user mode is the journaling
    /// flow: one human records, the same human plays back, chunks they
    /// have heard are marked as listened. The listenership model is
    /// multi-user (it tracks *who* heard *what*) and includes the rule
    /// "hearing your own voice doesn't count as listening." To keep
    /// playback correctly marking chunks in solo mode, the convenience
    /// inits supply two distinct sentinels — `solo` as the viewer and
    /// `soloAuthor` as the implicit recording author. Both represent
    /// the same human; the split exists only so the listenership rule
    /// fires the way the single-user flow expects.
    static let solo       = Participant(id: UUID(), displayName: "Solo (viewer)")
    static let soloAuthor = Participant(id: UUID(), displayName: "Solo (author)")
}

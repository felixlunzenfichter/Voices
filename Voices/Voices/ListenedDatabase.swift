import Foundation

/// Persistent record of which chunks have been listened to at least once.
/// Survives scrub, replay, and (in future implementations) app restarts.
protocol ListenedDatabase {
    func markHeard(_ id: UUID)
    func hasBeenHeard(_ id: UUID) -> Bool
    func allHeard(_ ids: [UUID]) -> Bool
}

/// In-memory implementation — persists for the lifetime of the app process.
final class InMemoryListenedDatabase: ListenedDatabase {
    private var heardIDs: Set<UUID> = []

    func markHeard(_ id: UUID) {
        heardIDs.insert(id)
    }

    func hasBeenHeard(_ id: UUID) -> Bool {
        heardIDs.contains(id)
    }

    func allHeard(_ ids: [UUID]) -> Bool {
        !ids.isEmpty && Set(ids).isSubset(of: heardIDs)
    }
}

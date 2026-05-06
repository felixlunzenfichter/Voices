import Foundation
import Observation

/// Local persistent `Database` backed by a single JSON file for
/// metadata and a reserved directory layout for future audio
/// payloads. Drop-in replacement for `InMemoryDatabase` behind the
/// existing `Database` protocol — no protocol changes required.
///
/// Storage layout under the configured root:
///
///   <root>/metadata.json                            recordings + chunks (no audio bytes)
///   <root>/audio/<recording-uuid>/<chunk-index>.bin reserved; created when AudioChunk gains a payload
///
/// The split is deliberate: `metadata.json` stays small and migratable
/// (today; into Postgres tomorrow), while binary audio payloads
/// (when they exist) end up as one file per chunk in the audio
/// directory (today on disk; tomorrow keyed by content hash in
/// S3-compatible object storage). The metadata file never embeds
/// audio bytes — when chunks gain a payload, the model carries a
/// reference (file URL / object key) and the bytes live in
/// `audio/`, not inline.
@Observable @MainActor
final class FileSystemDatabase: Database {
    private(set) var recordings: [Recording] = []

    @ObservationIgnored
    private let metadataURL: URL
    @ObservationIgnored
    private let audioDirectoryURL: URL

    /// Convenience initializer pointing at the running app's
    /// Documents directory under `voices/`. Use this in production.
    convenience init() throws {
        let docs = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        try self.init(rootDirectory: docs.appending(path: "voices", directoryHint: .isDirectory))
    }

    /// Initializes against a specific root directory. Tests use a
    /// temp directory; the production path is the Documents
    /// convenience init above.
    init(rootDirectory: URL) throws {
        self.metadataURL = rootDirectory.appending(path: "metadata.json", directoryHint: .notDirectory)
        self.audioDirectoryURL = rootDirectory.appending(path: "audio", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: audioDirectoryURL, withIntermediateDirectories: true)
        self.recordings = Self.loadRecordings(from: metadataURL)
    }

    // MARK: - Database (mutators)

    func addRecording(_ recording: Recording) {
        recordings.append(recording)
        persist()
    }

    func appendChunk(_ chunk: AudioChunk, to recordingID: UUID) {
        guard let rIdx = recordings.firstIndex(where: { $0.id == recordingID }) else { return }
        recordings[rIdx].audioChunks.append(chunk)
        persist()
    }

    func removeRecording(_ recordingID: UUID) {
        recordings.removeAll { $0.id == recordingID }
        persist()
    }

    func markListened(recordingID: UUID, chunkIndex: Int) {
        guard let rIdx = recordings.firstIndex(where: { $0.id == recordingID }),
              chunkIndex < recordings[rIdx].audioChunks.count else { return }
        recordings[rIdx].audioChunks[chunkIndex].listened = true
        persist()
    }

    /// Author-aware mark: a viewer who is the recording's author cannot
    /// turn their own chunk listened. Otherwise marks it listened.
    /// Mirrors `InMemoryDatabase.markListened(...:by:)`.
    func markListened(recordingID: UUID, chunkIndex: Int, by viewerID: UUID) {
        guard let rIdx = recordings.firstIndex(where: { $0.id == recordingID }),
              chunkIndex < recordings[rIdx].audioChunks.count,
              recordings[rIdx].author != viewerID else { return }
        recordings[rIdx].audioChunks[chunkIndex].listened = true
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        do {
            let data = try JSONEncoder().encode(recordings)
            try data.write(to: metadataURL, options: [.atomic])
        } catch {
            logError("FileSystemDatabase: write failed: \(error)")
        }
    }

    private static func loadRecordings(from url: URL) -> [Recording] {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([Recording].self, from: data)
        } catch {
            // Don't crash — surface and start empty so the user can
            // investigate via logs. Future PRs may quarantine the
            // bad file or surface a UI error.
            Task { @MainActor in
                logError("FileSystemDatabase: decode failed at \(url.path(percentEncoded: false)): \(error)")
            }
            return []
        }
    }
}

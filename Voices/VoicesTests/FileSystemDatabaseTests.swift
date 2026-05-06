import Foundation
import Testing
@testable import Voices

@MainActor
struct FileSystemDatabaseTests {

    /// Survives a full process-style boundary: write through one
    /// instance, drop it, construct a fresh instance pointing at the
    /// same directory, observe identical recordings. This is the
    /// core acceptance criterion ("recordings survive app relaunch")
    /// expressed at the Database seam.
    @Test("Recordings persist across separate FileSystemDatabase instances")
    func persistsAcrossInstances() throws {
        let root = Self.makeTempDirectory()
        let me = UUID()
        let other = UUID()

        let writer = try FileSystemDatabase(rootDirectory: root)
        let recID = UUID()
        writer.addRecording(Recording(
            id: recID,
            author: me,
            audioChunks: [AudioChunk(index: 0), AudioChunk(index: 1)]
        ))
        writer.appendChunk(AudioChunk(index: 2), to: recID)
        writer.markListened(recordingID: recID, chunkIndex: 0, by: other)

        let reader = try FileSystemDatabase(rootDirectory: root)

        let restored = try #require(reader.recordings.first)
        #expect(restored.id == recID)
        #expect(restored.author == me)
        #expect(restored.audioChunks.count == 3)
        #expect(restored.audioChunks[0].listened == true)
        #expect(restored.audioChunks[1].listened == false)
        #expect(restored.audioChunks[2].listened == false)
    }

    @Test("Empty start when no metadata file exists")
    func emptyStartFromMissingFile() throws {
        let root = Self.makeTempDirectory()
        let db = try FileSystemDatabase(rootDirectory: root)
        #expect(db.recordings.isEmpty)
    }

    @Test("removeRecording is persisted")
    func removeRecordingPersists() throws {
        let root = Self.makeTempDirectory()
        let me = UUID()

        let writer = try FileSystemDatabase(rootDirectory: root)
        let recID = UUID()
        writer.addRecording(Recording(id: recID, author: me, audioChunks: [AudioChunk(index: 0)]))
        writer.removeRecording(recID)

        let reader = try FileSystemDatabase(rootDirectory: root)
        #expect(reader.recordings.isEmpty)
    }

    /// Author-aware markListened (the rule landed in PR #37) survives
    /// the disk round-trip — listening to your own recording does not
    /// flip listened, even when the assertion runs against a fresh
    /// instance reading from disk.
    @Test("Own-message rule round-trips through disk")
    func ownMessageRuleRoundTrips() throws {
        let root = Self.makeTempDirectory()
        let me = UUID()

        let writer = try FileSystemDatabase(rootDirectory: root)
        let recID = UUID()
        writer.addRecording(Recording(id: recID, author: me, audioChunks: [AudioChunk(index: 0)]))
        writer.markListened(recordingID: recID, chunkIndex: 0, by: me) // own → no-op

        let reader = try FileSystemDatabase(rootDirectory: root)
        #expect(reader.recordings.first?.audioChunks.first?.listened == false)
    }

    /// Storage layout: metadata file is JSON-decodable, audio bytes are
    /// not embedded in it. Pins the contract that future binary audio
    /// payloads land in `audio/` instead of inflating `metadata.json`.
    @Test("Metadata file is pure JSON metadata, not audio")
    func metadataFileShapeIsClean() throws {
        let root = Self.makeTempDirectory()
        let me = UUID()
        let db = try FileSystemDatabase(rootDirectory: root)
        let recID = UUID()
        db.addRecording(Recording(id: recID, author: me, audioChunks: [AudioChunk(index: 0)]))

        let metadataURL = root.appending(path: "metadata.json", directoryHint: .notDirectory)
        let data = try Data(contentsOf: metadataURL)
        let decoded = try JSONDecoder().decode([Recording].self, from: data)
        #expect(decoded.count == 1)
        #expect(decoded.first?.id == recID)

        let audioDir = root.appending(path: "audio", directoryHint: .isDirectory)
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: audioDir.path(percentEncoded: false), isDirectory: &isDir)
        #expect(exists, "audio/ directory should be reserved on init")
        #expect(isDir.boolValue, "audio/ should be a directory")
    }

    // MARK: - helpers

    static func makeTempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "voices-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        return url
    }
}

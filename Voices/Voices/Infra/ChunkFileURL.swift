import Foundation

/// Conventional on-disk location for a recorded chunk's AAC file.
/// The producer writes here, the uploader reads here, the playback
/// cache reads here, and tests verify here. Single source of truth.
func chunkFileURL(recordingID: UUID, chunkIndex: Int) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("voices-recordings/\(recordingID.uuidString)", isDirectory: true)
        .appendingPathComponent("chunk-\(chunkIndex).m4a")
}

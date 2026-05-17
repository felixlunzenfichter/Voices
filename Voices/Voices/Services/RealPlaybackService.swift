import Foundation
import Observation
import AVFoundation

@Observable @MainActor
final class RealPlaybackService: PlaybackService {
    var playbackPosition: PlaybackPosition?
    private(set) var isPlaying = false

    @ObservationIgnored private let database: any Database
    @ObservationIgnored private let viewer: UUID
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var playerNode: AVAudioPlayerNode?

    init(database: any Database, viewer: UUID = UUID()) {
        self.database = database
        self.viewer = viewer
    }

    func play() {
        let recordings = database.recordings
        let resume: (recordingIndex: Int, chunkIndex: Int)
        if let pos = playbackPosition,
           let rIdx = recordings.firstIndex(where: { $0.id == pos.recordingID }) {
            resume = (rIdx, pos.chunkIndex)
        } else if let next = resumePoint(in: recordings) {
            resume = next
        } else {
            return
        }
        isPlaying = true
        playbackPosition = PlaybackPosition(
            recordingID: recordings[resume.recordingIndex].id,
            chunkIndex: resume.chunkIndex
        )
        task = Task { await self.consumePlayback(from: resume) }
    }

    func stop() {
        task?.cancel()
        task = nil
        playerNode?.stop()
        engine?.stop()
        playerNode = nil
        engine = nil
        isPlaying = false
    }

    private func resumePoint(in recordings: [Recording]) -> (recordingIndex: Int, chunkIndex: Int)? {
        for (rIdx, recording) in recordings.enumerated() {
            guard recording.author != viewer else { continue }
            for (cIdx, chunk) in recording.audioChunks.enumerated() {
                if !chunk.listened { return (rIdx, cIdx) }
            }
        }
        return nil
    }

    private func consumePlayback(from start: (recordingIndex: Int, chunkIndex: Int)) async {
        guard let (engine, player) = startEngine() else {
            isPlaying = false
            return
        }
        defer {
            player.stop()
            engine.stop()
            self.playerNode = nil
            self.engine = nil
        }

        let snapshot = database.recordings
        for rIdx in start.recordingIndex..<snapshot.count {
            let recordingID = snapshot[rIdx].id
            var cIdx = (rIdx == start.recordingIndex) ? start.chunkIndex : 0
            while !Task.isCancelled {
                guard let recording = database.recordings.first(where: { $0.id == recordingID }),
                      cIdx < recording.audioChunks.count else { break }
                let chunk = recording.audioChunks[cIdx]
                await playChunk(chunk.data, on: player, engine: engine)
                guard !Task.isCancelled else { return }
                playbackPosition = PlaybackPosition(recordingID: recordingID, chunkIndex: chunk.index)
                database.markListened(recordingID: recordingID, chunkIndex: chunk.index, by: viewer)
                cIdx += 1
            }
        }

        if !Task.isCancelled {
            if let next = resumePoint(in: database.recordings) {
                playbackPosition = PlaybackPosition(
                    recordingID: database.recordings[next.recordingIndex].id,
                    chunkIndex: next.chunkIndex
                )
            } else {
                playbackPosition = nil
            }
            isPlaying = false
        }
    }

    private func startEngine() -> (AVAudioEngine, AVAudioPlayerNode)? {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: nil)
        do {
            try engine.start()
        } catch {
            return nil
        }
        self.engine = engine
        self.playerNode = player
        return (engine, player)
    }

    private func playChunk(_ data: Data, on player: AVAudioPlayerNode, engine: AVAudioEngine) async {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("playback-\(UUID().uuidString).m4a")
        guard (try? data.write(to: tempURL)) != nil,
              let file = try? AVAudioFile(forReading: tempURL) else {
            try? FileManager.default.removeItem(at: tempURL)
            return
        }
        defer { try? FileManager.default.removeItem(at: tempURL) }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            player.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { _ in
                cont.resume()
            }
            if !player.isPlaying { player.play() }
        }
    }
}

import Foundation
import Observation
import AVFoundation

@Observable @MainActor
final class RealPlaybackService: PlaybackService {
    var playbackPosition: PlaybackPosition?
    private(set) var isPlaying = false

    @ObservationIgnored private let database: any Database
    @ObservationIgnored private let viewer: UUID
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var playerNode: AVAudioPlayerNode?
    @ObservationIgnored private var cursorRecordingIndex: Int = 0
    @ObservationIgnored private var cursorChunkIndex: Int = 0
    @ObservationIgnored private var inFlight: Int = 0

    private let lookahead = 2

    init(database: any Database, viewer: UUID = UUID()) {
        self.database = database
        self.viewer = viewer
    }

    func play() {
        guard !isPlaying else { return }
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
        guard let (engine, player) = startEngine() else { return }
        self.engine = engine
        self.playerNode = player
        cursorRecordingIndex = resume.recordingIndex
        cursorChunkIndex = resume.chunkIndex
        inFlight = 0
        isPlaying = true

        for _ in 0..<lookahead { scheduleNext() }
        player.play()
    }

    func stop() {
        tearDown()
    }

    /// Schedules the chunk at the cursor (reading the live database)
    /// and advances. Called from `play()` for the lookahead, and once
    /// from each chunk's completion handler.
    @discardableResult
    private func scheduleNext() -> Bool {
        guard let player = playerNode else { return false }
        let recordings = database.recordings
        while cursorRecordingIndex < recordings.count {
            let recording = recordings[cursorRecordingIndex]
            if cursorChunkIndex < recording.audioChunks.count {
                let chunk = recording.audioChunks[cursorChunkIndex]
                cursorChunkIndex += 1
                schedule(chunk: chunk, recordingID: recording.id, on: player)
                return true
            } else {
                cursorRecordingIndex += 1
                cursorChunkIndex = 0
            }
        }
        return false
    }

    private func schedule(chunk: AudioChunk, recordingID: UUID, on player: AVAudioPlayerNode) {
        let wireFormat = RealRecordingService.wireFormat
        let frameCount = AVAudioFrameCount(chunk.data.count / MemoryLayout<Float>.size)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: wireFormat, frameCapacity: frameCount) else {
            return
        }
        buffer.frameLength = frameCount
        chunk.data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let src = raw.baseAddress,
                  let dest = buffer.floatChannelData?[0] else { return }
            memcpy(dest, src, chunk.data.count)
        }
        inFlight += 1

        let index = chunk.index
        player.scheduleBuffer(buffer, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.playbackPosition = PlaybackPosition(recordingID: recordingID, chunkIndex: index)
                self.database.markListened(recordingID: recordingID, chunkIndex: index, by: self.viewer)
                self.inFlight -= 1
                if !self.scheduleNext(), self.inFlight == 0 {
                    self.tearDown()
                }
            }
        }
    }

    private func tearDown() {
        playerNode?.stop()
        engine?.stop()
        playerNode = nil
        engine = nil
        cursorRecordingIndex = 0
        cursorChunkIndex = 0
        inFlight = 0
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

    private func startEngine() -> (AVAudioEngine, AVAudioPlayerNode)? {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: RealRecordingService.wireFormat)
        do {
            try engine.start()
        } catch {
            return nil
        }
        return (engine, player)
    }
}

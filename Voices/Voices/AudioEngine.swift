import AVFoundation
import Observation

@Observable
@MainActor
final class AudioEngine {
    let db: Database
    let chunkState: ChunkStateTracker
    var isRecording = false
    var isPlaying = false
    var currentlyPlayingChunkId: UUID?

    private var engine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    private var activeRecordingIndex: Int?
    private var chunkSeq = 0

    init(db: Database, chunkState: ChunkStateTracker) {
        self.db = db
        self.chunkState = chunkState
    }

    // All uploaded chunks across all recordings that haven't been played yet.
    var hasPlayable: Bool { !nextPlayableChunks().isEmpty }

    private func nextPlayableChunks() -> [(recordingIndex: Int, chunk: Chunk)] {
        var result: [(recordingIndex: Int, chunk: Chunk)] = []
        for (ri, recording) in db.recordings.enumerated() {
            for chunk in recording.chunks where chunkState.status(of: chunk.id) == .uploaded {
                result.append((ri, chunk))
            }
        }
        return result
    }

    // MARK: - Recording

    func startRecording() {
        if isPlaying { stopPlaying() }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            logError("Audio session error: \(error)")
            return
        }

        engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        let ri = db.insertRecording(id: UUID(), sampleRate: Int(format.sampleRate), channels: Int(format.channelCount))
        activeRecordingIndex = ri
        chunkSeq = 0

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let data = self.bufferToData(buffer)
            let seq = self.chunkSeq
            self.chunkSeq += 1
            Task { @MainActor in
                self.appendChunk(seq: seq, data: data)
            }
        }

        do {
            try engine.start()
            isRecording = true
            let rec = db.recordings[ri]
            log("Recording started (sampleRate: \(rec.sampleRate), channels: \(rec.channels))")
        } catch {
            logError("Engine start error: \(error)")
            inputNode.removeTap(onBus: 0)
        }
    }

    func stopRecording() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        if let ri = activeRecordingIndex {
            log("Recording stopped (\(db.recordings[ri].chunks.count) chunks)")
        }
        activeRecordingIndex = nil
        isRecording = false
    }

    private func appendChunk(seq: Int, data: Data) {
        guard let ri = activeRecordingIndex else { return }
        let id = UUID()
        db.insertChunk(recordingIndex: ri, id: id, seq: seq, data: data)
        chunkState.markRecorded(id)
        chunkState.mockUpload(id)
    }

    // MARK: - Playback

    // Plays the next uploaded chunks — not the next message.
    // Only stops recording if there's actually something to play.
    func startPlaying() {
        let playable = nextPlayableChunks()
        guard !playable.isEmpty else { return }
        if isRecording { stopRecording() }
        playChunks(playable)
    }

    private func playChunks(_ chunks: [(recordingIndex: Int, chunk: Chunk)]) {
        let first = db.recordings[chunks[0].recordingIndex]

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            logError("Audio session error: \(error)")
            return
        }

        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(first.sampleRate),
            channels: AVAudioChannelCount(first.channels),
            interleaved: false
        )!

        engine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)

        for (_, chunk) in chunks {
            if let buffer = dataToBuffer(chunk.data, format: format) {
                let chunkId = chunk.id
                playerNode.scheduleBuffer(buffer) { [weak self] in
                    Task { @MainActor in
                        guard let self, self.isPlaying else { return }
                        self.currentlyPlayingChunkId = chunkId
                        self.chunkState.markPlayed(chunkId)
                    }
                }
            }
        }

        // Sentinel: detect when all scheduled chunks finish
        playerNode.scheduleBuffer(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 0)!) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.playbackFinished()
            }
        }

        do {
            try engine.start()
            currentlyPlayingChunkId = chunks.first?.chunk.id
            playerNode.play()
            isPlaying = true
            log("Playback started (\(chunks.count) chunks)")
        } catch {
            logError("Playback engine error: \(error)")
        }
    }

    func stopPlaying() {
        playerNode.stop()
        engine.stop()
        isPlaying = false
        currentlyPlayingChunkId = nil
        log("Playback paused")
    }

    private func playbackFinished() {
        guard isPlaying else { return }
        playerNode.stop()
        engine.stop()
        currentlyPlayingChunkId = nil
        log("Playback finished")

        // More chunks may have uploaded during playback — continue
        let more = nextPlayableChunks()
        if !more.isEmpty {
            playChunks(more)
        } else {
            isPlaying = false
        }
    }

    // MARK: - PCM Conversion

    private nonisolated func bufferToData(_ buffer: AVAudioPCMBuffer) -> Data {
        let floats = buffer.floatChannelData![0]
        return Data(bytes: floats, count: Int(buffer.frameLength) * MemoryLayout<Float>.size)
    }

    private nonisolated func dataToBuffer(_ data: Data, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frames = UInt32(data.count / MemoryLayout<Float>.size)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buf.frameLength = frames
        data.withUnsafeBytes { raw in
            buf.floatChannelData![0].update(from: raw.bindMemory(to: Float.self).baseAddress!, count: Int(frames))
        }
        return buf
    }
}

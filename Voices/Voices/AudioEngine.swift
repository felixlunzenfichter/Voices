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

    var nextPlayableIndex: Int? {
        db.recordings.firstIndex { chunkState.hasPlayableChunks(in: $0) }
    }

    var hasPlayable: Bool { nextPlayableIndex != nil }

    // MARK: - Recording

    func startRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            logError("Audio session error: \(error)")
            return
        }

        if isPlaying {
            stopPlaying()
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        let index = db.insertRecording(
            id: UUID(),
            sampleRate: Int(format.sampleRate),
            channels: Int(format.channelCount)
        )
        activeRecordingIndex = index
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
            let rec = db.recordings[index]
            log("Recording started (sampleRate: \(rec.sampleRate), channels: \(rec.channels))")
        } catch {
            logError("Engine start error: \(error)")
            inputNode.removeTap(onBus: 0)
        }
    }

    func stopRecording() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        if let index = activeRecordingIndex {
            let count = db.recordings[index].chunks.count
            log("Recording stopped (\(count) chunks)")
        }

        activeRecordingIndex = nil
        isRecording = false
    }

    private func appendChunk(seq: Int, data: Data) {
        guard let ri = activeRecordingIndex else { return }
        let chunkId = UUID()
        let ci = db.insertChunk(recordingIndex: ri, id: chunkId, seq: seq, data: data)
        chunkState.markRecorded(chunkId)
        chunkState.mockUpload(chunkId)
    }

    // MARK: - Playback

    func startPlaying() {
        guard let recordingIndex = nextPlayableIndex else { return }

        if isRecording {
            stopRecording()
        }

        playRecording(at: recordingIndex)
    }

    private func playRecording(at recordingIndex: Int) {
        let recording = db.recordings[recordingIndex]

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
            sampleRate: Double(recording.sampleRate),
            channels: AVAudioChannelCount(recording.channels),
            interleaved: false
        )!

        engine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)

        for chunk in recording.chunks {
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

        let idx = recordingIndex
        playerNode.scheduleBuffer(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 0)!) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.playbackFinished(recordingIndex: idx)
            }
        }

        do {
            try engine.start()
            if let firstChunkId = recording.chunks.first?.id {
                currentlyPlayingChunkId = firstChunkId
            }
            playerNode.play()
            isPlaying = true
            log("Playback started (\(recording.chunks.count) chunks)")
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

    private func playbackFinished(recordingIndex: Int) {
        guard isPlaying else { return }
        chunkState.markAllPlayed(in: db.recordings[recordingIndex])
        playerNode.stop()
        engine.stop()
        currentlyPlayingChunkId = nil
        log("Playback finished")

        if let nextIndex = nextPlayableIndex {
            playRecording(at: nextIndex)
        } else {
            isPlaying = false
        }
    }

    // MARK: - Conversion

    private nonisolated func bufferToData(_ buffer: AVAudioPCMBuffer) -> Data {
        let floatData = buffer.floatChannelData![0]
        let count = Int(buffer.frameLength)
        return Data(bytes: floatData, count: count * MemoryLayout<Float>.size)
    }

    private nonisolated func dataToBuffer(_ data: Data, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameCount = UInt32(data.count / MemoryLayout<Float>.size)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        data.withUnsafeBytes { raw in
            let src = raw.bindMemory(to: Float.self)
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: Int(frameCount))
        }
        return buffer
    }
}

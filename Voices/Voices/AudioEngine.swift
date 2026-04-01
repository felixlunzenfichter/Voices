import AVFoundation
import Observation

@Observable
@MainActor
final class AudioEngine {
    let db: Database
    var isRecording = false
    var isPlaying = false

    private var engine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    private var activeRecordingId: UUID?
    private var chunkSeq = 0
    private var playedChunkIds: Set<UUID> = []

    init(db: Database) {
        self.db = db
    }

    var hasPlayable: Bool { nextUnplayedChunk() != nil }

    private func nextUnplayedChunk() -> (recording: Recording, chunk: Chunk)? {
        for recording in db.recordings {
            for chunk in recording.chunks where !playedChunkIds.contains(chunk.id) {
                return (recording, chunk)
            }
        }
        return nil
    }

    func startRecording() {
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

        let recordingId = UUID()
        db.insertRecording(id: recordingId, sampleRate: Int(format.sampleRate), channels: Int(format.channelCount))
        activeRecordingId = recordingId
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
            log("Recording started (sampleRate: \(Int(format.sampleRate)), channels: \(Int(format.channelCount)))")
        } catch {
            logError("Engine start error: \(error)")
            inputNode.removeTap(onBus: 0)
        }
    }

    func stopRecording() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        if let id = activeRecordingId,
           let recording = db.recordings.first(where: { $0.id == id }) {
            log("Recording stopped (\(recording.chunks.count) chunks)")
        }
        activeRecordingId = nil
        isRecording = false
    }

    private func appendChunk(seq: Int, data: Data) {
        guard let recordingId = activeRecordingId else { return }
        db.insertChunk(recordingId: recordingId, id: UUID(), seq: seq, data: data)
    }

    // MARK: - Playback

    private var playbackQueue: [(recording: Recording, chunk: Chunk)] = []
    private var playbackFormat: AVAudioFormat?

    func startPlaying() {
        playbackQueue = []
        for recording in db.recordings {
            for chunk in recording.chunks where !playedChunkIds.contains(chunk.id) {
                playbackQueue.append((recording, chunk))
            }
        }
        guard let first = playbackQueue.first else { return }
        if isRecording { stopRecording() }

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
            sampleRate: Double(first.recording.sampleRate),
            channels: AVAudioChannelCount(first.recording.channels),
            interleaved: false
        )!
        playbackFormat = format

        engine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
            playerNode.play()
            isPlaying = true
            scheduleChunk(at: 0)
            scheduleChunk(at: 1)
        } catch {
            logError("Playback engine error: \(error)")
        }
    }

    func stopPlaying() {
        playerNode.stop()
        engine.stop()
        isPlaying = false
        log("Playback stopped")
    }

    private func scheduleChunk(at index: Int) {
        guard index < playbackQueue.count,
              let format = playbackFormat,
              let buffer = dataToBuffer(playbackQueue[index].chunk.data, format: format) else { return }

        let chunk = playbackQueue[index].chunk
        playerNode.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor in
                guard let self, self.isPlaying else { return }
                self.playedChunkIds.insert(chunk.id)
                self.scheduleChunk(at: index + 2)
                if index == self.playbackQueue.count - 1 {
                    self.isPlaying = false
                    log("Playback finished")
                }
            }
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

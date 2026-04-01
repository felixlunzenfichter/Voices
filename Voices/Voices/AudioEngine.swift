import AVFoundation
import Observation

@Observable
@MainActor
final class AudioEngine {
    let db: Database
    var isRecording = false

    private var engine = AVAudioEngine()
    private var activeRecordingId: UUID?
    private var chunkSeq = 0

    init(db: Database) {
        self.db = db
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

    private nonisolated func bufferToData(_ buffer: AVAudioPCMBuffer) -> Data {
        let floats = buffer.floatChannelData![0]
        return Data(bytes: floats, count: Int(buffer.frameLength) * MemoryLayout<Float>.size)
    }
}

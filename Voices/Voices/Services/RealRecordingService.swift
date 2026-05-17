import Foundation
import Observation
import AVFoundation

@Observable @MainActor
final class RealRecordingService: RecordingService {
    private(set) var isRecording = false

    @ObservationIgnored private let database: any Database
    @ObservationIgnored private let author: UUID
    @ObservationIgnored private var currentRecordingID: UUID?
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var nextChunkIndex: Int = 0

    /// Canonical wire format: 48 kHz mono float32, non-interleaved.
    /// Producer converts to this; consumer decodes from this. No
    /// per-recording format metadata needed because the format is
    /// fixed at the protocol level.
    static let wireFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 48000,
        channels: 1,
        interleaved: false
    )!

    init(database: any Database, author: UUID = UUID()) {
        self.database = database
        self.author = author
    }

    func start() {
        isRecording = true
        nextChunkIndex = 0

        let recording = Recording(author: author)
        currentRecordingID = recording.id
        database.addRecording(recording)

        AVAudioApplication.requestRecordPermission { _ in }

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .default)
        try? session.setActive(true)

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let wireFormat = Self.wireFormat
        guard let converter = AVAudioConverter(from: inputFormat, to: wireFormat) else {
            return
        }

        let recordingID = recording.id
        inputNode.installTap(onBus: 0, bufferSize: 8192, format: inputFormat) { [weak self] buffer, _ in
            guard let data = Self.serializePCM(buffer, with: converter, wireFormat: wireFormat) else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                let index = self.nextChunkIndex
                self.nextChunkIndex += 1
                self.database.appendChunk(AudioChunk(index: index, data: data), to: recordingID)
            }
        }

        self.engine = engine
        try? engine.start()
    }

    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        try? AVAudioSession.sharedInstance().setActive(false)
        isRecording = false
        currentRecordingID = nil
    }

    /// Converts one input buffer to the wire format and returns the
    /// raw float32 channel-0 bytes. No encoder, no container.
    private static func serializePCM(
        _ buffer: AVAudioPCMBuffer,
        with converter: AVAudioConverter,
        wireFormat: AVAudioFormat
    ) -> Data? {
        let outFrames = AVAudioFrameCount(
            Double(buffer.frameLength) * wireFormat.sampleRate / buffer.format.sampleRate
        )
        guard outFrames > 0,
              let out = AVAudioPCMBuffer(pcmFormat: wireFormat, frameCapacity: outFrames) else {
            return nil
        }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            if consumed { outStatus.pointee = .noDataNow; return nil }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard error == nil, status != .error,
              let ptr = out.floatChannelData?[0] else { return nil }
        let byteCount = Int(out.frameLength) * MemoryLayout<Float>.size
        return Data(bytes: ptr, count: byteCount)
    }
}

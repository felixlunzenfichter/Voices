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

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: inputFormat.sampleRate,
            AVNumberOfChannelsKey: inputFormat.channelCount,
        ]

        let recordingID = recording.id
        inputNode.installTap(onBus: 0, bufferSize: 8192, format: inputFormat) { [weak self] buffer, _ in
            guard let data = Self.encodeBufferToM4A(buffer, settings: settings) else { return }
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

    /// Encodes one PCM buffer into a complete in-memory M4A file.
    /// Each chunk is independently decodable; the file goes out of
    /// scope to flush the AAC stream, then we read the bytes back.
    private static func encodeBufferToM4A(_ buffer: AVAudioPCMBuffer, settings: [String: Any]) -> Data? {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("chunk-\(UUID().uuidString).m4a")
        do {
            let file = try AVAudioFile(forWriting: tempURL, settings: settings)
            try file.write(from: buffer)
            // file goes out of scope here → AAC stream flushed and closed
        } catch {
            return nil
        }
        let data = try? Data(contentsOf: tempURL)
        try? FileManager.default.removeItem(at: tempURL)
        return data
    }
}

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
    @ObservationIgnored private var audioFile: AVAudioFile?
    @ObservationIgnored nonisolated(unsafe) private var firstBufferSeen = false

    init(database: any Database, author: UUID = UUID()) {
        self.database = database
        self.author = author
    }

    func start() {
        isRecording = true
        firstBufferSeen = false

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

        let url = chunkFileURL(recordingID: recording.id, chunkIndex: 0)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: inputFormat.sampleRate,
            AVNumberOfChannelsKey: inputFormat.channelCount,
        ]
        let file = try? AVAudioFile(forWriting: url, settings: settings)
        self.audioFile = file
        self.engine = engine

        let recordingID = recording.id
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self, file] buffer, _ in
            try? file?.write(from: buffer)
            guard let self, !self.firstBufferSeen else { return }
            self.firstBufferSeen = true
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.database.appendChunk(AudioChunk(index: 0), to: recordingID)
            }
        }

        try? engine.start()
    }

    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        audioFile = nil
        try? AVAudioSession.sharedInstance().setActive(false)
        isRecording = false
        currentRecordingID = nil
    }
}

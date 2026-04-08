import Observation
import Testing
@testable import Voices

struct VoicesViewModelTests {
    @Test("Recording and listening are never both true")
    func mutualExclusion() {
        let vm = VoicesViewModel()

        vm.toggleRecording()
        #expect(vm.isRecording == true)
        #expect(vm.isListening == false)

        // Toggle listening while recording — must stop recording first
        vm.toggleListening()
        #expect(vm.isListening == true)
        #expect(vm.isRecording == false, "Recording must stop when listening starts")

        // Toggle recording while listening — must stop listening first
        vm.toggleRecording()
        #expect(vm.isRecording == true)
        #expect(vm.isListening == false, "Listening must stop when recording starts")
    }

    @Test("Stop recording sets isRecording to false")
    func stopSetsFlag() {
        let vm = VoicesViewModel()
        vm.toggleRecording()
        vm.toggleRecording()
        #expect(vm.isRecording == false)
    }

    @Test("Stop recording cancels chunk production", .timeLimit(.minutes(1)))
    func stopCancelsProduction() async {
        let producer = FakeChunkProducer(count: 1000)
        let vm = VoicesViewModel(chunkProducer: producer)

        vm.toggleRecording()

        // Wait for at least one chunk — reactive, not polling
        for await count in Observations({ vm.chunks.count }) {
            if count >= 1 { break }
        }

        vm.toggleRecording()  // stop
        let countAfterStop = vm.chunks.count

        // Wait to see if any more chunks sneak through
        try? await Task.sleep(for: .milliseconds(50))

        #expect(vm.chunks.count == countAfterStop, "No new chunks should arrive after stop")
        #expect(countAfterStop < 1000, "Stream should have been cancelled before completing")
    }
}

import Observation
import Testing
@testable import Voices

struct FakeDatabase: Database {
    var recordings: [[AudioChunk]]
}

struct VoicesViewModelTests {
    @Test("Toggle recording toggles isRecording")
    func toggleRecordingTogglesState() {
        let vm = VoicesViewModel()

        vm.toggleRecording()
        #expect(vm.isRecording == true)

        vm.toggleRecording()
        #expect(vm.isRecording == false)
    }

    @Test("State transitions: record, listen, record")
    func stateTransitions() {
        let db = FakeDatabase(recordings: [[AudioChunk(index: 0)]])
        let vm = VoicesViewModel(database: db)

        // Start recording
        vm.toggleRecording()
        #expect(vm.isRecording == true)
        #expect(vm.isListening == false)

        // Start listening — stops recording
        vm.toggleListening()
        #expect(vm.isListening == true)
        #expect(vm.isRecording == false)

        // Start recording — stops listening
        vm.toggleRecording()
        #expect(vm.isRecording == true)
        #expect(vm.isListening == false)
    }
}

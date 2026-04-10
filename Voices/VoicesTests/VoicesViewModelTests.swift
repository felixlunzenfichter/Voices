import Observation
import Testing
@testable import Voices

struct FakeDatabase: Database {
    var recordings: [[AudioChunk]]

    static func withOneRecording() -> FakeDatabase {
        FakeDatabase(recordings: [[AudioChunk(index: 0)]])
    }
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

    @Test("Listen does nothing when nothing recorded")
    func listenDoesNothingWhenNothingRecorded() {
        let vm = VoicesViewModel()

        #expect(vm.isListening == false)
        vm.toggleListening()
        #expect(vm.isListening == false)
    }

    @Test("Toggle listening toggles isListening")
    func toggleListeningTogglesState() {
        let vm = VoicesViewModel(database: FakeDatabase.withOneRecording())

        #expect(vm.isListening == false)
        vm.toggleListening()
        #expect(vm.isListening == true)

        vm.toggleListening()
        #expect(vm.isListening == false)
    }

    @Test("State transitions: record, listen, record")
    func stateTransitions() {
        let db = FakeDatabase.withOneRecording()
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

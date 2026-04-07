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
}

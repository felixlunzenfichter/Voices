import Foundation

struct Conversation: Identifiable {
    let id: UUID
    var participants: [Participant]
    var recordings: [Recording]

    init(
        id: UUID = UUID(),
        participants: [Participant] = [],
        recordings: [Recording] = []
    ) {
        self.id = id
        self.participants = participants
        self.recordings = recordings
    }
}

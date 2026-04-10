protocol Database {
    var recordings: [[AudioChunk]] { get }
}

struct InMemoryDatabase: Database {
    var recordings: [[AudioChunk]] = []
}

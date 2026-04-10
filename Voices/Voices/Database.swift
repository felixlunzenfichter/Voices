protocol Database {
    var recordings: [Recording] { get }
}

struct InMemoryDatabase: Database {
    var recordings: [Recording] = []
}

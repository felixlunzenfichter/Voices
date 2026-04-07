# TDD in Swift — Practical Guide

Distilled from Gio Lodi's *Test-Driven Development in Swift* (Apress, 2021), adapted to this repo's `@Observable` architecture and Swift Testing.

**Position:** Tests live in the Xcode test target using Swift Testing (`@Test`, `#expect`). Runtime logging (`log()`, `logError()`) is for observability and debugging on device — not a substitute for tests.

---

## The Loop: Red, Green, Refactor

Write a failing `@Test`. Make it pass with the minimum code. Refactor. (Ch 1)

```swift
import Testing

@Test("Toggle recording starts recording when stopped")
func toggleStartsRecording() {
    let vm = VoicesViewModel()
    vm.toggleRecording()
    #expect(vm.isRecording == true)
}
```

### Fake It Till You Make It

Hardcode the return value to go green, then generalize. Each step is a known-good state. (Ch 3)

### Wishful Coding

Write the call site first (the test), even if the function doesn't exist. Let the compiler error guide implementation. A type error is already a failing test. (Ch 3)

---

## Test List

Before coding, enumerate behaviors. Work through them one by one. This IS the spec. (Ch 3)

```
// 1. scrub to chunk 10 moves activeIndex
// 2. chunks 0-10 stay .listened, 11+ become .uploaded
// 3. pressing listen after scrub replays from 11
// 4. all chunks listened after replay
```

---

## Arrange-Act-Assert

Every test has this shape. (Ch 2)

```swift
@Test("Scrub updates active index")
func scrubUpdatesIndex() {
    // Arrange
    let store = ChunkStore(chunks: .fixtures(count: 20))
    // Act
    store.scrub(to: 10)
    // Assert
    #expect(store.activeIndex == 10)
}
```

---

## Assertions & Safety

**Use the strictest assertion.** `#expect(count == 3)` shows the actual value on failure. (Ch 4)

**Use `try #require` to unwrap and halt** — stops the test on nil, prevents cascading failures. (Ch 4)

```swift
@Test func chunkAtIndex() throws {
    let store = ChunkStore(chunks: .fixtures(count: 5))
    let chunk = try #require(store.chunk(at: 3))
    #expect(chunk.status == .uploaded)
}
```

**Don't let tests crash.** Use safe subscripts in assertions. A crash at line 50 loses every assertion after it. (Ch 4)

```swift
extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
```

### Test Naming

Swift Testing: `@Test("description")` with a short function name.

```swift
@Test("Toggling recording when not recording starts recording")
func toggleStartsRecording() { }
```

XCTest (legacy): `test_<what>_<conditions>_<expected>()` (Roy Osherove convention, Ch 4).

---

## Fixture Extensions

Centralize construction with defaults. When the init grows, only the fixture updates. (Ch 5)

```swift
extension ChunkEntry {
    static func fixture(
        id: UUID = UUID(),
        status: ChunkStatus = .uploaded
    ) -> ChunkEntry {
        ChunkEntry(id: id, status: status)
    }
}
```

**Rule of three**: two tests inline is fine. Before the third, extract a fixture. Fixtures compose — `Recording.fixture()` uses `ChunkEntry.fixture()` as its default.

---

## Test Doubles

Four types, one question each. (Ch 8, 10, 12, 15)

| Double | Purpose | Example |
|--------|---------|---------|
| **Stub** | Fixed return value | `ListenedDatabase` returning `true` for `allHeard` |
| **Spy** | Record calls for assertion | Captures all `send()` calls |
| **Fake** | In-memory stateful replacement | `InMemoryListenedDatabase` with `Set<UUID>` |
| **Dummy** | Satisfies init, never used | Empty database when testing recording logic |

---

## Dependency Injection

Inject dependencies behind protocols via init. The ViewModel itself stays concrete — `@Observable` is a macro on a class, can't be enforced through protocol conformance. (Ch 7, 11)

```swift
protocol AudioRecorder {
    func start() async throws
    func stop() -> Data
}

@Observable @MainActor
final class VoicesViewModel {
    private let recorder: AudioRecorder

    init(recorder: AudioRecorder = RealAudioRecorder()) {
        self.recorder = recorder
    }
}
```

For macro-generated spies: [@Spyable](https://github.com/Matejkob/swift-spyable).

---

## Pure Functions First

No state, no side effects — easiest to test. Push logic toward pure functions, keep the impure shell thin. (Ch 4)

```swift
// Pure computed properties — trivially testable
var hasListenable: Bool { allChunks.contains { $0.status == .uploaded } }
var allHeard: Bool { allChunks.allSatisfy { $0.status == .listened } }
```

---

## Bug Fix = Missing Test

A bug is a test that hasn't been written yet. (Ch 14)

1. Write a failing `@Test` that reproduces the bug
2. See it fail — confirms the bug exists
3. Fix the code
4. See the test pass
5. Commit

---

## @Observable in 2026

### Architecture

```
View (dumb) ──reads/calls──▶ ViewModel (@Observable @MainActor) ──delegates──▶ Store/Service (protocol-backed)
```

Views read properties and call methods. No `@State` for business logic, no `Task` creation in views. Data in, callbacks out. (Ch 6)

### What You Get

Plain `var` properties are automatically tracked. No `@Published`, no `sink`, no `AnyCancellable`. Synchronous mutations are directly testable — mutate, then assert.

### Gotchas

| Issue | Detail |
|-------|--------|
| Not a protocol | `@Observable` is a macro on a class. Observation silently fails if missing from a conforming type |
| One-shot tracking | `withObservationTracking` fires once. For continuous observation outside SwiftUI, use `Observations` AsyncSequence (Swift 6.2) |
| `@MainActor` required | Off-main mutations crash at runtime. Always pair with `@MainActor` on UI-driving VMs |
| `@State` re-init | `@State` with `@Observable` calls the initializer every rebuild. SwiftUI preserves the original but intermediates can leak |
| Serial tests | `@MainActor` VMs force serial execution in Swift Testing. Acceptable for small codebases |

### Testing @Observable VMs

Synchronous state needs no observation tracking:

```swift
@Test func initialState() {
    let vm = VoicesViewModel()
    #expect(vm.isRecording == false)
    #expect(vm.isListening == false)
}
```

---

## Logs ≠ Tests

| | Tests (Xcode target) | Logs (WebSocket) |
|-|----------------------|-------------------|
| **Purpose** | Prove correctness | Observe behavior on device |
| **When** | Before merge | At runtime |
| **Speed** | Fast, no device needed | Requires deploy + device |
| **Regression** | Automatic — CI catches it | Manual — someone reads the log |
| **Failure** | Blocks merge | Goes unnoticed unless watched |

Use `log()` / `logError()` for runtime observability. Use `@Test` / `#expect` for correctness proofs.

---

## Incremental Migration

Don't rewrite. Add tests where you're already changing code. (Ch 16, Appendix A, Feathers)

1. **Bug fixes** — write failing test, fix, pass. Lowest friction entry point.
2. **New features** — TDD from scratch.
3. **Extract and test** — pull logic from views into VMs. Now testable.
4. **Sprout method** — new tested function, called from legacy code at a single point.
5. **Wrap method** — rename original, new function calls original + new logic.

### Seams

| Type | Swift equivalent | Use case |
|------|-----------------|----------|
| Object seam | Protocol conformance | Primary. Extract protocol, inject stub/spy |
| Link seam | Module/target boundary | Test target links mock implementation |
| Preprocessing seam | `#if DEBUG` / `#if TESTING` | Escape hatch for hard-to-inject deps |

---

## Reference

### Books
- Gio Lodi, *TDD in Swift* (Apress, 2021)
- Greene & Katz, *iOS TDD by Tutorials* (Kodeco, 2019)
- Feathers, *Working Effectively with Legacy Code* (2004)

### Apple
- [Swift Testing docs](https://developer.apple.com/documentation/testing)
- [Meet Swift Testing (WWDC24)](https://developer.apple.com/videos/play/wwdc2024/10179/)
- [Go Further with Swift Testing (WWDC24)](https://developer.apple.com/videos/play/wwdc2024/10195/)

### @Observable & Testing
- [Jacob Bartlett — Unit Test the Observation Framework](https://blog.jacobstechtavern.com/p/unit-test-the-observation-framework)
- [Fatbobman — Deep Dive Into Observation](https://fatbobman.com/en/posts/mastering-observation/)
- [Use Your Loaf — Swift Observations AsyncSequence](https://useyourloaf.com/blog/swift-observations-asyncsequence-for-state-changes/)
- [Swift Forums — Enforce @Observable through a protocol](https://forums.swift.org/t/enforce-observable-through-a-protocol/72984)
- [Swift Forums — @MainActor @Observable test performance](https://forums.swift.org/t/improving-swift-testing-performance-for-mainactor-observable-view-models/84733)

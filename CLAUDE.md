# Voices

## Logging

All logs go to the shared Claw Control log server via WebSocket. Every app across all devices and branches writes to the same file.

| What | Where |
|------|-------|
| Log server | `ws://felixs-macbook-pro.tailcfdca5.ts.net:9998` |
| Log file | `~/clawcontraw.log` (JSONL, shared across all apps) |

**Finding your logs:** Filter by `device` name to isolate logs from a specific phone/branch.
```bash
# Logs from Felix's iPhone
grep '"device":"Felix'"'"'s iPhone"' ~/clawcontraw.log

# Logs from the device named "iPhone"
grep '"device":"iPhone"' ~/clawcontraw.log

# Live tail for a specific device
tail -f ~/clawcontraw.log | grep --line-buffered '"device":"iPhone"'
```

**API:** `log("message")` and `logError("message")` — sends device name, file, function, message as JSONL.

**Rule:** All logs and error messages in this app MUST go through `log()` and `logError()`. Never use `print()`, `debugPrint()`, or `NSLog()` — they are invisible on device. The WebSocket log is the only way to see what the app is doing.

**Runtime failures:** `logError()` sets `"isError": true` in the JSON payload. Invariant violations, unexpected states, and contract failures all surface through `logError()`. Filter for them:
```bash
# All errors from any device
grep '"isError":true' ~/clawcontraw.log

# Errors from a specific device
grep '"isError":true' ~/clawcontraw.log | grep '"device":"Felix'"'"'s iPhone"'
```

**Logs ≠ Tests:** `@Test` / `#expect` prove correctness before merge. `log()` / `logError()` observe behavior on device at runtime. Tests are fast, automatic, and block merge. Logs require deploy, a device, and someone watching. Both matter — they are complementary, not interchangeable.

**Requires:** Tailscale VPN on the iPhone and `NSAllowsArbitraryLoads` in `Info.plist` for `ws://` connections.

## TDD

Distilled from Gio Lodi's *TDD in Swift* (Apress, 2021), adapted to this repo's `@Observable` architecture and Swift Testing.

**Position:** Tests live in the Xcode test target (`VoicesTests`) using Swift Testing (`@Test`, `#expect`). Runtime logging (`log()`, `logError()`) is for observability — not a substitute for tests.

### The Loop: Red, Green, Refactor

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

**Fake It Till You Make It** — Hardcode the return value to go green, then generalize. Each step is a known-good state. (Ch 3)

**Wishful Coding** — Write the call site first (the test), even if the function doesn't exist. Let the compiler error guide implementation. A type error is already a failing test. (Ch 3)

### Test List

Before coding, enumerate behaviors. Work through them one by one. This IS the spec. (Ch 3)

```
// 1. scrub to chunk 10 moves activeIndex
// 2. chunks 0-10 stay .listened, 11+ become .uploaded
// 3. pressing listen after scrub replays from 11
// 4. all chunks listened after replay
```

### Arrange-Act-Assert

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

### Assertions & Safety

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

**Test naming:** Swift Testing: `@Test("description")` with a short function name. XCTest (legacy): `test_<what>_<conditions>_<expected>()` (Roy Osherove convention, Ch 4).

### Async Tests

Two patterns depending on what you're testing:

**Testing a stream directly** — consume with `for await`. The stream's `finish()` ends the loop. Deterministic, no polling. From `VoicesTests/ChunkOrderingTests.swift`:

```swift
@Test("Fake produces exactly N chunks in order", .timeLimit(.minutes(1)))
func producesCorrectChunks() async {
    let producer = FakeChunkProducer(count: 5)
    var collected: [Int] = []
    for await chunk in producer.chunks() {
        collected.append(chunk.index)
    }
    #expect(collected == [0, 1, 2, 3, 4])
}
```

**Testing a ViewModel with internal async Tasks** — use `Observations` (SE-0475, Swift 6.2 stdlib) to reactively await state changes. No polling, guaranteed to fire on every mutation. From `VoicesTests/VoicesViewModelTests.swift`:

```swift
@Test("Stop recording cancels chunk production", .timeLimit(.minutes(1)))
func stopCancelsProduction() async {
    let producer = FakeChunkProducer(count: 1000)
    let vm = VoicesViewModel(chunkProducer: producer)

    vm.toggleRecording()

    // Reactive: yields every time chunks.count changes
    for await count in Observations({ vm.chunks.count }) {
        if count >= 1 { break }
    }

    vm.toggleRecording()  // stop
    let countAfterStop = vm.chunks.count
    try? await Task.sleep(for: .milliseconds(50))

    #expect(vm.chunks.count == countAfterStop)
    #expect(countAfterStop < 1000)
}
```

**Key rules:**
- `for await` on finite streams for testing producers/services directly
- `Observations({ vm.property })` for awaiting ViewModel state changes from outside — it's an `AsyncSequence` over `@Observable` mutations, shipped in the `Observation` module
- `.timeLimit` as safety net on every async test
- Avoid `while ... { await Task.yield() }` polling — `Observations` replaces it with a real guarantee

### Fixture Extensions

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

### Test Doubles

Four types, one question each. (Ch 8, 10, 12, 15)

| Double | Purpose | Example |
|--------|---------|---------|
| **Stub** | Fixed return value | `ListenedDatabase` returning `true` for `allHeard` |
| **Spy** | Record calls for assertion | Captures all `send()` calls |
| **Fake** | In-memory stateful replacement | `InMemoryListenedDatabase` with `Set<UUID>` |
| **Dummy** | Satisfies init, never used | Empty database when testing recording logic |

### Dependency Injection

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

### Pure Functions First

No state, no side effects — easiest to test. Push logic toward pure functions, keep the impure shell thin. (Ch 4)

```swift
// Pure computed properties — trivially testable
var hasListenable: Bool { allChunks.contains { $0.status == .uploaded } }
var allHeard: Bool { allChunks.allSatisfy { $0.status == .listened } }
```

### Bug Fix = Missing Test

A bug is a test that hasn't been written yet. (Ch 14)

1. Write a failing `@Test` that reproduces the bug
2. See it fail — confirms the bug exists
3. Fix the code
4. See the test pass
5. Commit

### Design by Contract — Codebase Example

**Invariant:** `isRecording` and `isListening` are never both `true`.

This contract is enforced at three levels:

**1. Preventive (code guards).** `startRecording()` stops listening first; `startListening()` stops recording first. From `VoicesViewModel.swift`:

```swift
private func startRecording() {
    if isListening { stopListening() }   // ← guard
    isRecording = true
    // ...
}

private func startListening() {
    if isRecording { stopRecording() }   // ← guard
    isListening = true
    // ...
}
```

**2. Defensive (runtime invariant check).** Both `isRecording` and `isListening` have `didSet { checkMutualExclusion() }`. If the invariant is ever violated despite the guards, `logError()` fires immediately. From `VoicesViewModel.swift`:

```swift
private(set) var isRecording = false {
    didSet { checkMutualExclusion() }
}
private(set) var isListening = false {
    didSet { checkMutualExclusion() }
}

private func checkMutualExclusion() {
    if isRecording && isListening {
        logError("INVARIANT: isRecording=\(isRecording) isListening=\(isListening) — both true simultaneously")
    }
}
```

That `logError()` call sends `"isError": true` in the JSON payload to `~/clawcontraw.log` — see the Logging section above for how to filter for it.

**3. Test-time proof.** The unit test in `VoicesTests/VoicesViewModelTests.swift` exercises all transitions and asserts the invariant holds after each:

```swift
@Test("Recording and listening are never both true")
func mutualExclusion() {
    let vm = VoicesViewModel()

    vm.toggleRecording()
    #expect(vm.isRecording == true)
    #expect(vm.isListening == false)

    vm.toggleListening()
    #expect(vm.isListening == true)
    #expect(vm.isRecording == false, "Recording must stop when listening starts")

    vm.toggleRecording()
    #expect(vm.isRecording == true)
    #expect(vm.isListening == false, "Listening must stop when recording starts")
}
```

**Summary:** Prevention stops it happening. The `didSet` invariant catches it if prevention fails, surfacing the violation via `logError()` into the shared log. The unit test proves the preventive logic is correct before merge. All three layers reference the same contract.

### @Observable in 2026

**Architecture:**

```
View (dumb) ──reads/calls──▶ ViewModel (@Observable @MainActor) ──delegates──▶ Store/Service (protocol-backed)
```

Views read properties and call methods. No `@State` for business logic, no `Task` creation in views. Data in, callbacks out. (Ch 6)

**What you get:** Plain `var` properties are automatically tracked. No `@Published`, no `sink`, no `AnyCancellable`. Synchronous mutations are directly testable — mutate, then assert.

**Gotchas:**

| Issue | Detail |
|-------|--------|
| Not a protocol | `@Observable` is a macro on a class. Observation silently fails if missing from a conforming type |
| One-shot tracking | `withObservationTracking` fires once. For continuous observation outside SwiftUI, use `Observations` AsyncSequence (Swift 6.2) |
| `@MainActor` required | Off-main mutations crash at runtime. Always pair with `@MainActor` on UI-driving VMs |
| `@State` re-init | `@State` with `@Observable` calls the initializer every rebuild. SwiftUI preserves the original but intermediates can leak |
| Serial tests | `@MainActor` VMs force serial execution in Swift Testing. Acceptable for small codebases |

**Testing @Observable VMs** — synchronous state needs no observation tracking:

```swift
@Test func initialState() {
    let vm = VoicesViewModel()
    #expect(vm.isRecording == false)
    #expect(vm.isListening == false)
}
```

### Incremental Migration

Don't rewrite. Add tests where you're already changing code. (Ch 16, Appendix A, Feathers)

1. **Bug fixes** — write failing test, fix, pass. Lowest friction entry point.
2. **New features** — TDD from scratch.
3. **Extract and test** — pull logic from views into VMs. Now testable.
4. **Sprout method** — new tested function, called from legacy code at a single point.
5. **Wrap method** — rename original, new function calls original + new logic.

**Seams:**

| Type | Swift equivalent | Use case |
|------|-----------------|----------|
| Object seam | Protocol conformance | Primary. Extract protocol, inject stub/spy |
| Link seam | Module/target boundary | Test target links mock implementation |
| Preprocessing seam | `#if DEBUG` / `#if TESTING` | Escape hatch for hard-to-inject deps |

### TDD Reference

**Books:** Gio Lodi, *TDD in Swift* (Apress, 2021) · Greene & Katz, *iOS TDD by Tutorials* (Kodeco, 2019) · Feathers, *Working Effectively with Legacy Code* (2004)

**Apple:** [Swift Testing docs](https://developer.apple.com/documentation/testing) · [Meet Swift Testing (WWDC24)](https://developer.apple.com/videos/play/wwdc2024/10179/) · [Go Further with Swift Testing (WWDC24)](https://developer.apple.com/videos/play/wwdc2024/10195/)

**@Observable & Testing:** [Jacob Bartlett — Unit Test the Observation Framework](https://blog.jacobstechtavern.com/p/unit-test-the-observation-framework) · [Fatbobman — Deep Dive Into Observation](https://fatbobman.com/en/posts/mastering-observation/) · [Use Your Loaf — Swift Observations AsyncSequence](https://useyourloaf.com/blog/swift-observations-asyncsequence-for-state-changes/) · [Swift Forums — Enforce @Observable through a protocol](https://forums.swift.org/t/enforce-observable-through-a-protocol/72984) · [Swift Forums — @MainActor @Observable test performance](https://forums.swift.org/t/improving-swift-testing-performance-for-mainactor-observable-view-models/84733)

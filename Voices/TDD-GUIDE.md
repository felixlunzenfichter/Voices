# TDD Guide for Voices

Practical test-driven development adapted to this repo's logging-first infrastructure, `@Observable` architecture, and branch-level proof workflow.

---

## 1. The Voices TDD Loop

Traditional iOS TDD uses XCTest/Swift Testing infrastructure. We use that secondarily. Our primary loop uses the WebSocket log server as the proof system.

### Red — Failing log with trace

Add a `log()` or `logError()` call that proves the behavior doesn't exist yet. Run the app on device, filter by device name, observe the error/absence in `~/clawcontraw.log`.

```swift
func startRecording() {
    log("RED: startRecording called — expect chunk count to increase")
    store.startRecording()
    // ... existing code ...
    log("RED: chunk count after start = \(store.allChunks.count)")  // expect 0 → should become >0
}
```

```bash
# Watch from Mac
tail -f ~/clawcontraw.log | grep --line-buffered '"device":"Felix'"'"'s iPhone"'
```

The log is the failing test. You see the wrong value (or an error) in the terminal.

### Green — Successful log with trace

Write the minimum code to make the log show the correct value. Run again. The log now shows the right state.

```swift
func appendChunk() -> UUID {
    // ... implementation ...
    log("GREEN: appendChunk — total chunks now \(allChunks.count)")
    return id
}
```

### Refactor — Remove traces, clean the diff

Once behavior is confirmed, remove the temporary `log()` traces. The final PR diff contains no debugging logs — only the feature code and any permanent `log()`/`logError()` calls that belong in production.

```
RED:      log("RED: ...")   → observe failure
GREEN:    log("GREEN: ...") → observe success  
REFACTOR: delete RED/GREEN traces → clean commit
```

### Why this works for Voices

| Property | Log-first TDD | XCTest TDD |
|----------|---------------|------------|
| Runs on real device | Yes — the only way we deploy | Simulator or device |
| Proves real audio/network path | Yes — same binary, same hardware | Mocks required |
| Visible from Mac | Yes — `tail -f ~/clawcontraw.log` | Xcode test navigator |
| Branch isolation | Filter by device name | Separate test target |
| Speed | Build + run (~seconds) | Build + test (~seconds) |
| Permanent artifact | Production logs stay; traces removed | Test files stay forever |

The log server at `ws://felixs-macbook-pro.tailcfdca5.ts.net:9998` is shared across all devices and branches. Filter by `"device"` field to isolate one phone's logs from another.

---

## 2. Red-Green-Refactor in Detail

From *iOS TDD by Tutorials* (Greene & Katz, Kodeco), adapted:

**RED** — Write the assertion first. In our case, add a `log()` that shows current state before the feature exists. Compilation failures also count as red. The point: you see proof of the gap before writing any implementation.

**GREEN** — Write the *bare minimum* code to close the gap. Not the elegant version. Not the general version. The minimum that makes the log show the right value. If you write more, your proof falls behind your code.

**REFACTOR** — Now improve. Extract duplicates, rename for clarity, move logic to the right layer. All logs still show correct values after refactoring. Then remove the temporary traces so the commit is clean.

Rules from the book, applied here:

| Rule | Application |
|------|-------------|
| Test before code | `log()` the expected state before implementing |
| Bare minimum to pass | Smallest change that makes the log correct |
| All previous proofs hold | Re-run after each change, watch full log output |
| Compilation errors = red | A type error is already a failing test |
| Refactor both sides | Clean production code *and* remove temporary traces |

Source: Greene & Katz, *iOS Test-Driven Development by Tutorials*, Chapters 1-2.

---

## 3. Observable Architecture: Dumb Views, Smart View Models

Voices already uses `@Observable` (`ChunkStore`). The migration direction: move all behavior out of views into `@Observable` view models. Views become pure rendering functions.

### Current state

`ChunkStore` (in `VoiceBarModel.swift`) is the smart model — `@MainActor @Observable`, owns all state mutations. Good.

`ContentView` (in `VoicesApp.swift`) currently holds behavior that belongs in a view model: recording timer management, listening toggle logic, scrub coordination. This logic can't be tested without launching the full UI.

### Target architecture

```
┌──────────────────────────────────────────────────┐
│  View (dumb)                                     │
│  - Reads @Observable properties                  │
│  - Calls view model methods on user action       │
│  - No logic, no state machines, no Task creation │
└──────────────────┬───────────────────────────────┘
                   │ reads / calls
┌──────────────────▼───────────────────────────────┐
│  ViewModel (@Observable @MainActor)              │
│  - Owns behavior: start/stop recording, toggle   │
│  - Coordinates between Store and side effects    │
│  - Testable without UI                           │
│  - Uses log() for branch-level proof             │
└──────────────────┬───────────────────────────────┘
                   │ delegates to
┌──────────────────▼───────────────────────────────┐
│  Store / Service (protocol-backed)               │
│  - ChunkStore: chunk state machine               │
│  - WSConnection: network                         │
│  - Injectable via init, mockable via protocol    │
└──────────────────────────────────────────────────┘
```

### How @Observable changes seams vs Combine/ObservableObject

With `@Observable`, plain `var` properties are automatically tracked. No `@Published`, no `$publisher` sink chains, no `AnyCancellable` storage. This makes view models simpler to write and test.

**What you gain:**
- Synchronous state mutations are directly testable — mutate, then assert. No observation machinery needed for simple cases.
- Only properties *actually read* in a view's `body` trigger re-renders. Passing the whole view model to child views is fine.
- No Combine import, no cancellable lifecycle management.

**What to watch out for:**
- `@Observable` is a macro on a class, not a protocol. You can't enforce it through a protocol at compile time. If a class conforms to your protocol without `@Observable`, observation silently fails. ([Swift Forums](https://forums.swift.org/t/enforce-observable-through-a-protocol/72984))
- `withObservationTracking` is one-shot — fires once and stops. For continuous observation outside SwiftUI, use Swift 6.2's `Observations` type (an `AsyncSequence`). ([Use Your Loaf](https://useyourloaf.com/blog/swift-observations-asyncsequence-for-state-changes/))
- `@Observable` doesn't enforce main-thread updates. But SwiftUI expects them. Always pair with `@MainActor` on view models that drive UI. Off-main mutations compile without warnings but can crash at runtime. ([Fatbobman](https://fatbobman.com/en/posts/mastering-observation/))
- `@State` with `@Observable` calls the initializer every view hierarchy rebuild (unlike `@StateObject` which deferred). SwiftUI preserves the original instance, but intermediate instances can leak. ([Jesse Squires](https://www.jessesquires.com/blog/2024/09/09/swift-observable-macro/))

Sources: [Jacob Bartlett - Unit Test the Observation Framework](https://blog.jacobstechtavern.com/p/unit-test-the-observation-framework); [Fatbobman - Deep Dive Into Observation](https://fatbobman.com/en/posts/mastering-observation/); [Jared Sinclair - We Need to Talk About Observation (Sept 2025)](https://jaredsinclair.com/2025/09/10/observation.html).

### Dumb view pattern

A dumb view takes data and callbacks. No `@State` for business logic. No `Task` creation.

```swift
// DUMB: data in, callbacks out
struct ChunkStrip: View {
    let chunks: [ChunkEntry]
    var activeIndex: Int?
    var onScrubStart: (() -> Void)?
    var onScrubMove: ((Int) -> Void)?
    var onScrubEnd: ((Int) -> Void)?
    // body renders from data, routes gestures to callbacks
}
```

`ChunkStrip`, `MessageList`, `RecordButton`, and `ListenButton` already follow this pattern.

The work is moving the logic currently in `ContentView` (timer management, recording/listening coordination) into a view model.

### Smart view model pattern

```swift
@Observable @MainActor
final class VoicesViewModel {
    private(set) var isRecording = false
    let store: ChunkStore
    private var chunkTimer: Task<Void, Never>?

    init(store: ChunkStore = ChunkStore()) {
        self.store = store
    }

    func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        if store.isListening { store.stopListening() }
        isRecording = true
        store.startRecording()
        chunkTimer = Task { /* ... */ }
        log("Recording started")
    }

    private func stopRecording() {
        chunkTimer?.cancel()
        chunkTimer = nil
        isRecording = false
        store.stopRecording()
        log("Recording stopped")
    }

    // Testable without UI:
    // let vm = VoicesViewModel(store: mockStore)
    // vm.toggleRecording()
    // #expect(vm.isRecording == true)
}
```

### Testing @Observable view models

**Simple state tests — synchronous, no observation tracking needed:**
```swift
@Test func toggleRecordingStartsRecording() {
    let vm = VoicesViewModel(store: ChunkStore())
    vm.toggleRecording()
    #expect(vm.isRecording == true)
    #expect(vm.store.recordings.count == 1)
}
```

**Side-effect verification — inject a mock, check it was called:**
```swift
@Test func stopRecordingLogsMessage() async {
    let vm = VoicesViewModel(store: ChunkStore())
    vm.toggleRecording()   // start
    vm.toggleRecording()   // stop
    #expect(vm.isRecording == false)
}
```

**Async operations — use `await` directly:**
```swift
@Test func appendChunkIncreasesCount() async throws {
    let store = ChunkStore()
    store.startRecording()
    store.appendChunk()
    #expect(store.allChunks.count == 1)
}
```

**`@MainActor` caveat:** Since our view models are `@MainActor`, Swift Testing runs these tests serially on the main actor. This prevents in-process parallelization but matches the real execution model. For this codebase, correctness matters more than test speed. ([Swift Forums](https://forums.swift.org/t/improving-swift-testing-performance-for-mainactor-observable-view-models/84733))

Source: [Jacob Bartlett - Unit Test the Observation Framework](https://blog.jacobstechtavern.com/p/unit-test-the-observation-framework); [ObservationTestUtils](https://github.com/jacobsapps/ObservationTestUtils).

---

## 4. Dependency Injection for Testability

The view model's dependencies are injected via `init`, with real defaults for production:

```swift
@Observable @MainActor
final class VoicesViewModel {
    let store: ChunkStore

    init(store: ChunkStore = ChunkStore()) {
        self.store = store
    }
}
```

For services behind protocols (network, audio):

```swift
protocol AudioRecorder {
    func start() async throws
    func stop() -> Data
}

@Observable @MainActor
final class VoicesViewModel {
    private let recorder: AudioRecorder
    let store: ChunkStore

    init(store: ChunkStore = ChunkStore(), recorder: AudioRecorder = RealAudioRecorder()) {
        self.store = store
        self.recorder = recorder
    }
}
```

In tests, inject a mock:
```swift
struct MockRecorder: AudioRecorder {
    var startCallCount = 0
    func start() async throws { startCallCount += 1 }
    func stop() -> Data { Data() }
}
```

**Don't put the view model behind a protocol.** Inject its *dependencies* behind protocols. The view model itself is concrete. This sidesteps the problem that `@Observable` can't be enforced through protocols.

For macro-generated mocks, [@Spyable](https://github.com/Matejkob/swift-spyable) generates spy classes from protocols automatically. Useful when the number of protocols grows.

Source: [Michal Cichon - DI Patterns in Swift (Nov 2025)](https://michalcichon.github.io/software-development/2025/11/25/dependency-injection-patterns-in-swift.html); Greene & Katz Ch. 6.

---

## 5. Characterization Tests for Existing Code

Before refactoring any existing code, lock in its current behavior:

1. Pick the function you need to change.
2. Add a `log()` that captures the actual output.
3. Run. Observe what the code *actually does* (not what you think it does).
4. Now you have a baseline. Any refactoring that changes the log output is a regression.

Example — characterizing `previewScrub` before refactoring:

```swift
func previewScrub(_ globalIndex: Int) {
    log("previewScrub(\(globalIndex)) — before: \(allChunks.map { $0.status })")
    // ... existing logic ...
    log("previewScrub(\(globalIndex)) — after: \(allChunks.map { $0.status })")
}
```

Run the app, scrub around, capture the log output. Now you know exactly what `previewScrub` does for various inputs. Refactor safely. Remove traces when done.

For conventional test infrastructure (optional, secondary):
```swift
@Test("previewScrub marks chunks up to index as listened")
func previewScrubBehavior() {
    let store = ChunkStore()
    store.startRecording()
    store.appendChunk()
    store.appendChunk()
    // Simulate upload
    // store.previewScrub(0)
    // #expect(store.allChunks[0].status == .listened)
}
```

Source: Michael Feathers, *Working Effectively with Legacy Code*; Greene & Katz Section IV.

---

## 6. Incremental Migration Strategy

### Do not rewrite. Test at the point of change.

1. **Bug fixes first.** Add a `log()` that reproduces the bug. Fix it. Log shows correct value. Remove trace. This is the lowest-friction TDD entry point. ([SwiftLee](https://www.avanderlee.com/workflow/test-driven-development-tdd-for-bug-fixes-in-swift/))

2. **New features get TDD from scratch.** Green-field code within the existing project.

3. **Extract and test.** Pull logic out of `ContentView` into `VoicesViewModel`. The view becomes a thin rendering shell. The view model is testable via `log()` traces and optionally via Swift Testing.

4. **Sprout Method.** Write new logic in a separate, fully-tested function. Call it from legacy code with a single insertion point. Minimal change to untested code.

5. **Wrap Method.** Rename the original (e.g., `startRecording` → `_startRecordingCore`). New method with original name calls core + new tested logic.

Source: Feathers, *Working Effectively with Legacy Code*; [Understanding Legacy Code](https://understandlegacycode.com/blog/key-points-of-working-effectively-with-legacy-code/).

### Seams in Swift

| Seam type | Swift equivalent | When to use |
|-----------|-----------------|-------------|
| Object seam | Protocol conformance | Primary. Extract protocol from `WSConnection`, inject mock. |
| Link seam | Module/target boundary | Test target links mock implementation. |
| Preprocessing seam | `#if DEBUG` / `#if TESTING` | Escape hatch for hard-to-inject deps. |

---

## 7. Conventional Test Infrastructure (Secondary)

XCTest and Swift Testing are available for unit/integration tests when needed. They are not the primary workflow but complement logging-based proof.

### When to use formal tests

- Pure logic functions with many edge cases (chunk index math, scrub clamping).
- Regression tests for bugs that were hard to reproduce.
- Anything that needs to run in CI without a device.

### Swift Testing basics

```swift
import Testing

@Test("Chunk store starts empty")
func emptyStore() {
    let store = ChunkStore()
    #expect(store.allChunks.isEmpty)
    #expect(store.activeIndex == nil)
}

@Test("Append chunk increases count", arguments: [1, 5, 10])
func appendChunks(count: Int) {
    let store = ChunkStore()
    store.startRecording()
    for _ in 0..<count { store.appendChunk() }
    #expect(store.allChunks.count == count)
}
```

Two macros replace 40+ `XCTAssert` functions:
- `#expect(condition)` — soft assertion, continues on failure.
- `try #require(value)` — hard assertion, stops the test. Also unwraps optionals.

### Coexistence

Both XCTest and Swift Testing work in the same target. New tests use Swift Testing. UI tests stay on XCTest (`XCUIApplication`). Don't mix assertion styles in a single test.

Sources: [Use Your Loaf - Migrating XCTest to Swift Testing](https://useyourloaf.com/blog/migrating-xctest-to-swift-testing/); WWDC24 [Meet Swift Testing](https://developer.apple.com/videos/play/wwdc2024/10179/); [Fatbobman - Mastering Swift Testing](https://fatbobman.com/en/posts/mastering-the-swift-testing-framework/).

---

## 8. Test Naming

### XCTest (legacy convention)

```
test_<what>_<conditions>_<expected>
```

Example: `test_appendChunk_duringRecording_increasesCount()`

### Swift Testing (new code)

Use `@Test("description")` with a short function name:

```swift
@Test("Appending chunk during recording increases count")
func appendDuringRecording() { }
```

Source: [Quality Coding - Unit Test Naming](https://qualitycoding.org/unit-test-naming/); [Swift with Vincent - Better Test Names](https://www.swiftwithvincent.com/blog/swift-62-lets-you-write-better-test-names).

---

## 9. Log-Based Branch Proof During Development

During development on a feature branch, temporary `log()` traces act as proof that the feature works on real hardware:

```swift
// Development — temporary trace
func startListening() {
    log("PROOF: startListening — hasListenable=\(hasListenable), isListening=\(isListening)")
    isListening = true
    // ...
}
```

```bash
# From Mac, watch the branch being tested on iPhone
tail -f ~/clawcontraw.log | grep --line-buffered 'PROOF:'
```

Before the PR is merged:
1. All `PROOF:` / `RED:` / `GREEN:` traces are removed.
2. Only permanent `log()` calls (app lifecycle, errors) remain.
3. The commit diff is clean.

This gives us the benefit of TDD's prove-then-implement discipline without coupling to a test runner that can't see real device behavior.

---

## References

### Books
- Greene & Katz, *iOS Test-Driven Development by Tutorials* (Kodeco, 2019)
- Michael Feathers, *Working Effectively with Legacy Code* (Prentice Hall, 2004)

### Apple / WWDC
- [Meet Swift Testing (WWDC24)](https://developer.apple.com/videos/play/wwdc2024/10179/)
- [Go Further with Swift Testing (WWDC24)](https://developer.apple.com/videos/play/wwdc2024/10195/)
- [What's New in Swift / Swift Testing (WWDC25)](https://developer.apple.com/videos/play/wwdc2025/245/)
- [Swift Testing Documentation](https://developer.apple.com/documentation/testing)

### @Observable and Testing (2025-2026)
- [Jacob Bartlett - Unit Test the Observation Framework](https://blog.jacobstechtavern.com/p/unit-test-the-observation-framework)
- [Fatbobman - Deep Dive Into Observation](https://fatbobman.com/en/posts/mastering-observation/)
- [Jared Sinclair - We Need to Talk About Observation (Sept 2025)](https://jaredsinclair.com/2025/09/10/observation.html)
- [Jesse Squires - @Observable Is Not a Drop-In](https://www.jessesquires.com/blog/2024/09/09/swift-observable-macro/)
- [Use Your Loaf - Swift Observations AsyncSequence](https://useyourloaf.com/blog/swift-observations-asyncsequence-for-state-changes/)
- [Swift Forums - @MainActor @Observable test performance](https://forums.swift.org/t/improving-swift-testing-performance-for-mainactor-observable-view-models/84733)
- [Swift Forums - Enforce @Observable through a protocol](https://forums.swift.org/t/enforce-observable-through-a-protocol/72984)

### Migration and DI
- [Michal Cichon - DI Patterns in Swift (Nov 2025)](https://michalcichon.github.io/software-development/2025/11/25/dependency-injection-patterns-in-swift.html)
- [SwiftLee - TDD for Bug Fixes](https://www.avanderlee.com/workflow/test-driven-development-tdd-for-bug-fixes-in-swift/)
- [Understanding Legacy Code - Key Points](https://understandlegacycode.com/blog/key-points-of-working-effectively-with-legacy-code/)
- [Migrating XCTest to Swift Testing (Use Your Loaf)](https://useyourloaf.com/blog/migrating-xctest-to-swift-testing/)

### Libraries
- [swift-spyable](https://github.com/Matejkob/swift-spyable) — Macro-generated spies
- [swift-concurrency-extras](https://github.com/pointfreeco/swift-concurrency-extras) — Deterministic async testing
- [ObservationTestUtils](https://github.com/jacobsapps/ObservationTestUtils) — Helpers for testing @Observable

---

*PDF source: "iOS Test-Driven Development by Tutorials" (Greene & Katz) extracted via `pdftotext`. Sections III-IV of the book are early-access stubs — legacy code guidance supplements with Feathers' techniques. Web sources fetched April 2026.*

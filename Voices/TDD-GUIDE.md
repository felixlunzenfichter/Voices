# TDD Guide for Voices

Practical test-driven development adapted to this repo's logging-first infrastructure, `@Observable` architecture, and branch-level proof workflow.

---

## 1. The Voices TDD Loop

Primary loop uses the WebSocket log server as the proof system. Conventional test infrastructure is secondary.

### Step 1 — Error log with trace

Add a `log()` or `logError()` that exposes the behavior gap. Run on device, watch `~/clawcontraw.log`.

```swift
func startRecording() {
    logError("TRACE: startRecording — chunk count = \(store.allChunks.count), expected >0")
    store.startRecording()
}
```

```bash
tail -f ~/clawcontraw.log | grep --line-buffered '"device":"Felix'"'"'s iPhone"'
```

The log shows the wrong value or an error. That's your failing test.

### Step 2 — Success log with trace

Write the minimum code to fix it. Run again. The log now shows the correct state.

```swift
func appendChunk() -> UUID {
    // ... implementation ...
    log("TRACE: appendChunk — total chunks now \(allChunks.count)")
    return id
}
```

### Step 3 — Cleanup: remove temporary traces for a clean PR

Delete all `TRACE:` logs. The final diff contains only the feature code and any permanent `log()`/`logError()` calls that belong in production.

```
1. logError("TRACE: ...")  → observe failure on device
2. log("TRACE: ...")       → observe success on device
3. delete TRACE logs       → clean commit
```

---

## 2. Rules (from *iOS TDD by Tutorials*, adapted)

| Rule | Application |
|------|-------------|
| Prove the gap before coding | `logError()` the expected state before implementing |
| Bare minimum to pass | Smallest change that makes the log correct |
| All previous proofs hold | Re-run after each change, watch full log output |
| Compilation errors count as failures | A type error is already a failing test |
| Clean up both sides | Production code *and* temporary traces |

Source: Greene & Katz, Chapters 1-2.

---

## 3. Observable Architecture: Dumb Views, Smart View Models

`ChunkStore` is already `@MainActor @Observable` — good. `ContentView` still holds behavior (timer management, listening toggle, scrub coordination) that belongs in a view model.

### Target

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

### @Observable vs Combine/ObservableObject

Plain `var` properties are automatically tracked. No `@Published`, no sink chains, no `AnyCancellable`. Synchronous mutations are directly testable — mutate, then assert.

**Gotchas:**
- `@Observable` is a macro on a class, not a protocol. Can't be enforced through protocols — observation silently fails if missing. ([Swift Forums](https://forums.swift.org/t/enforce-observable-through-a-protocol/72984))
- `withObservationTracking` is one-shot. For continuous observation outside SwiftUI, use Swift 6.2's `Observations` AsyncSequence. ([Use Your Loaf](https://useyourloaf.com/blog/swift-observations-asyncsequence-for-state-changes/))
- Always pair with `@MainActor` on UI-driving view models. Off-main mutations crash at runtime without compiler warnings. ([Fatbobman](https://fatbobman.com/en/posts/mastering-observation/))
- `@State` with `@Observable` calls the initializer every view rebuild. SwiftUI preserves the original instance but intermediate ones can leak. ([Jesse Squires](https://www.jessesquires.com/blog/2024/09/09/swift-observable-macro/))

### Dumb view pattern

Data in, callbacks out. No `@State` for business logic, no `Task` creation. `ChunkStrip`, `MessageList`, `RecordButton`, `ListenButton` already follow this pattern.

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

### Testing @Observable view models (optional, secondary)

Synchronous state tests need no observation tracking:
```swift
@Test func toggleRecordingStartsRecording() {
    let vm = VoicesViewModel(store: ChunkStore())
    vm.toggleRecording()
    #expect(vm.isRecording == true)
}
```

`@MainActor` view models force serial test execution in Swift Testing — no in-process parallelization. Acceptable for this codebase. ([Swift Forums](https://forums.swift.org/t/improving-swift-testing-performance-for-mainactor-observable-view-models/84733))

---

## 4. Dependency Injection

Inject *dependencies* behind protocols via `init`. The view model itself stays concrete (sidesteps the `@Observable`-can't-be-enforced-through-protocols problem).

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

For macro-generated mocks, [@Spyable](https://github.com/Matejkob/swift-spyable) generates spy classes from protocols automatically.

Source: [Michal Cichon - DI Patterns in Swift (Nov 2025)](https://michalcichon.github.io/software-development/2025/11/25/dependency-injection-patterns-in-swift.html); Greene & Katz Ch. 6.

---

## 5. Characterization Tests for Existing Code

Before refactoring, lock in current behavior:

1. Add `log()` calls that capture actual output of the function you'll change.
2. Run. Observe what the code *actually does*.
3. That log output is your baseline — any refactoring that changes it is a regression.
4. Remove traces when done.

```swift
func previewScrub(_ globalIndex: Int) {
    log("TRACE: previewScrub(\(globalIndex)) before: \(allChunks.map { $0.status })")
    // ... existing logic ...
    log("TRACE: previewScrub(\(globalIndex)) after: \(allChunks.map { $0.status })")
}
```

Source: Feathers, *Working Effectively with Legacy Code*; Greene & Katz Section IV.

---

## 6. Incremental Migration

Do not rewrite. Add tests only where you're already making changes.

1. **Bug fixes** — add a `logError()` trace that reproduces the bug, fix it, log shows correct value, remove trace. Lowest friction entry. ([SwiftLee](https://www.avanderlee.com/workflow/test-driven-development-tdd-for-bug-fixes-in-swift/))
2. **New features** — TDD from scratch.
3. **Extract and test** — pull logic out of `ContentView` into a view model. Testable via traces and optionally Swift Testing.
4. **Sprout Method** — new tested function, called from legacy code at a single insertion point.
5. **Wrap Method** — rename original (`startRecording` → `_startRecordingCore`), new method calls core + new logic.

Source: Feathers, *Working Effectively with Legacy Code*.

### Seams in Swift

| Seam type | Swift equivalent | Use case |
|-----------|-----------------|----------|
| Object seam | Protocol conformance | Primary. Extract protocol from `WSConnection`, inject mock. |
| Link seam | Module/target boundary | Test target links mock implementation. |
| Preprocessing seam | `#if DEBUG` / `#if TESTING` | Escape hatch for hard-to-inject deps. |

---

## 7. Conventional Test Infrastructure (Secondary)

Use when logging-based proof isn't enough: pure logic with many edge cases, CI without a device, hard-to-reproduce regressions.

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

`#expect(condition)` — continues on failure. `try #require(value)` — stops the test, also unwraps optionals. Both XCTest and Swift Testing coexist in one target.

Sources: [Use Your Loaf](https://useyourloaf.com/blog/migrating-xctest-to-swift-testing/); WWDC24 [Meet Swift Testing](https://developer.apple.com/videos/play/wwdc2024/10179/).

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

## 9. Branch Proof Workflow

During development, filter traces by device to isolate one branch's logs:

```bash
tail -f ~/clawcontraw.log | grep --line-buffered 'TRACE:'
```

Before merging: delete all `TRACE:` logs. Only permanent `log()`/`logError()` calls remain. The commit diff is clean.

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

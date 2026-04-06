# Lodi, *Test-Driven Development in Swift* (Apress, 2021)

Summary adapted to Voices' log-driven TDD infrastructure. Each chapter's key insight is translated to our system: logs as proof, `@Observable` architecture, protocol-backed DI, device-first workflow.

---

## Part I: Foundations (Ch 1-5)

### Ch 1 — Why TDD

Core loop: **Red, Green, Refactor**. Write a failing proof first, make it pass with minimum code, clean up.

**Our translation:** `logError("TRACE: ...")` = red. Fix code until `log("TRACE: ...")` shows correct state = green. Delete TRACE logs = refactor/cleanup. Same loop, logs instead of XCTAssertEqual.

### Ch 2 — XCTest Mechanics

Key patterns: `XCTUnwrap` (fail instead of crash on nil), `XCTestExpectation` (async), Arrange-Act-Assert structure.

**Our translation:** Arrange-Act-Assert maps directly to selfTest():
```swift
// Arrange — set up state
toggleRecording()
try? await Task.sleep(for: .seconds(5))

// Act — do the thing
toggleRecording()  // stop

// Assert — log the proof
if store.allChunks.count > 0 {
    log("TEST PASS: recording produced \(store.allChunks.count) chunks")
} else {
    logError("TEST FAIL: recording produced 0 chunks")
}
```

Avoid force-unwrapping in tests. A crash kills all subsequent log output. Use `guard let` + `logError` instead.

### Ch 3 — Getting Started with TDD

**Test List**: Before coding, write the list of behaviors to prove. Work through them one at a time. This is the Partition Problem and Solve Sequentially technique.

```
// Test list for "listen after scrub"
// 1. scrub to chunk 10 moves activeIndex
// 2. chunks 0-10 stay .listened, 11+ become .uploaded
// 3. pressing listen after scrub replays from 11
// 4. replay doesn't re-replay chunks 0-10
// 5. all chunks listened after replay
```

**Fake It Till You Make It**: Hardcode the return value to make the test pass, then generalize. In our system: make the log line appear with the right value, even if the implementation is incomplete. Then iterate.

**Wishful Coding**: Write the call site first (the test / the log assertion), even if the function doesn't exist yet. Let the compiler error guide implementation.

**Compiler as test**: A type error is a failing test. When you change a protocol or struct, the compiler tells you everywhere that needs updating — same feedback loop as a failing log.

### Ch 4 — TDD in the Real World

**Use the strictest assertion possible.** `XCTAssertEqual(count, 3)` tells you the actual value on failure. `XCTAssertTrue(count == 3)` just says "false". In our logs:

```swift
// Bad — tells you nothing on failure
if chunks > 0 { log("TEST PASS") } else { logError("TEST FAIL") }

// Good — shows actual value
logError("TEST FAIL: expected >0 chunks, got \(chunks)")
```

**Don't let tests crash.** Lodi introduces a safe Collection subscript that returns nil instead of crashing on out-of-range indices. Critical for us: if selfTest() crashes mid-run, every subsequent TEST PASS/FAIL line is lost.

```swift
extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
```

Use `guard let chunk = allChunks[safe: 10]` instead of `allChunks[10]` in test assertions.

**Test Naming Convention** (Roy Osherove): `[UnitOfWork]_[Scenario]_[ExpectedBehavior]`. In our logs, this becomes the TEST label:
```swift
log("TEST PASS: scrubTo10 — activeIndex moved to 10")
//            ^unit        ^expected behavior
```

**Pure Functions are easiest to test.** No state, no side effects — input in, output out, assert. Push as much logic as possible into pure functions, keep the impure shell thin. Our `ChunkStore` computed properties (`hasListenable`, `allHeard`, `allChunks`) are effectively pure — test them directly.

### Ch 5 — Fixture Extensions

When a type's init signature changes, every test that creates it breaks. Fixture extensions centralize construction with sensible defaults:

```swift
extension ChunkEntry {
    static func fixture(
        id: UUID = UUID(),
        status: ChunkStatus = .uploaded
    ) -> ChunkEntry {
        ChunkEntry(id: id, status: status)
    }
}

extension Recording {
    static func fixture(
        id: UUID = UUID(),
        createdAt: Date = .now,
        chunks: [ChunkEntry] = [.fixture()]
    ) -> Recording {
        Recording(id: id, createdAt: createdAt, chunks: chunks)
    }
}
```

**Rule of three**: If you call an init in two tests, define a fixture before the third. Fixtures are composable — `Recording.fixture()` uses `ChunkEntry.fixture()` as its default.

**Why this matters for us:** As `ChunkEntry` grows (audio data, duration, metadata), only the fixture needs updating. Every selfTest assertion and future Swift Testing test stays untouched.

---

## Part II: Testing SwiftUI (Ch 6-7)

### Ch 6 — Humble View, Smart ViewModel

SwiftUI views can't be unit tested directly. The solution: make the view *humble* (layout only) and move all logic into a testable ViewModel.

**We already do this.** Our architecture: dumb `ContentView` reads `VoicesViewModel`, which owns `ChunkStore`. The view calls `toggleRecording()`, the ViewModel handles state. Test the ViewModel, trust SwiftUI to render.

Lodi uses nested ViewModels (`MenuRow.ViewModel`). We use a flat structure (`VoicesViewModel` + `ChunkStore`). Same principle: views ask ViewModels what to show, never compute it themselves.

### Ch 7 — Testing Dynamic Views (Dependency Inversion Principle)

When a ViewModel depends on an async data source, define a protocol and inject it. This lets you:
1. Test the ViewModel with a stub (instant, deterministic)
2. Build the real implementation later
3. Swap implementations without changing the ViewModel

**Our equivalent:** `ChunkStore` injects `ListenedDatabase` via protocol. `InMemoryListenedDatabase` in production (and tests). When we add persistent storage, we swap the implementation — ChunkStore doesn't change.

**Key insight**: The Dependency Inversion Principle is not about testing — it's about building one layer at a time. Test the ViewModel with a stub while the real networking isn't built yet. We do this naturally: `WSConnection` is a real WebSocket client, but if we needed to test log delivery, we'd inject a protocol.

---

## Part III: Test Doubles (Ch 8, 10, 12, 15)

Four types. Each serves a different purpose:

| Double | Controls | Purpose | Voices example |
|--------|----------|---------|----------------|
| **Stub** | Indirect *input* | Return a predetermined value to the SUT | A `ListenedDatabase` that always returns `true` for `allHeard` |
| **Spy** | Indirect *output* | Record what the SUT did for later assertion | A log spy that captures all `log()` calls for assertion |
| **Fake** | *State* | Simpler in-memory version of a stateful dependency | `InMemoryListenedDatabase` (we already have this) |
| **Dummy** | *Nothing* | Satisfies a required parameter that doesn't affect the test | An empty `ListenedDatabase` passed when testing recording (listening not under test) |

**When to use which:**
- Testing what the ViewModel *does* given an input? **Stub** the dependency.
- Testing that the ViewModel *called* a dependency correctly? **Spy** on it.
- Dependency is stateful (UserDefaults, database, disk)? **Fake** it in-memory.
- Dependency is required by init but irrelevant to this test? **Dummy** it.

**In our log-driven system**, the device log itself is a spy — every `log()` and `logError()` call is captured in `~/clawcontraw.log`. We assert by grepping the log output. The whole system is one big Spy Test Double.

---

## Part IV: Real-World Patterns (Ch 9, 11, 13-14)

### Ch 9 — Testing JSON/Decoding

Only test decoding when there's custom logic (nested objects, computed properties, enum mapping). If `Decodable` auto-synthesis handles it, a test is redundant — Swift does the work.

**For us:** If we add a server API, test the decoding only if the JSON shape differs from our model shape.

### Ch 11 — Dependency Injection with @EnvironmentObject

Shared state (like an order controller) should be injected, not accessed as a singleton. Singletons couple tests — one test's mutation affects the next.

**Our equivalent:** We inject `ListenedDatabase` via init, keeping `ChunkStore` testable in isolation. Each test (or selfTest run) gets a fresh `InMemoryListenedDatabase`.

### Ch 13 — Conditional View Presentation

Extract conditional logic (show alert? which message?) into the ViewModel. Test the logic, wire the view to consume it.

**Our equivalent:** Button color (blue vs purple) is computed from `store.hasListenable && !store.allHeard`. The ViewModel exposes the data, the view just reads it. We prove the logic via log assertions in selfTest.

### Ch 14 — Fixing Bugs with TDD

> "A bug is just a test that hasn't been written yet."

**Bug-fix workflow:**
1. Write a `logError("TEST FAIL: ...")` that reproduces the bug on device.
2. See it fail in the logs.
3. Fix the code.
4. See the log switch to `log("TEST PASS: ...")`.
5. Delete the TRACE, commit the fix.

For changing existing behavior: update the expected value in the log assertion *first*, see it fail, then change the implementation to match.

### Ch 15 — Fakes and Dummies

**Fake**: Replace a slow/stateful dependency with a fast in-memory equivalent. Our `InMemoryListenedDatabase` is textbook — it stores heard IDs in a `Set<UUID>` instead of hitting disk/database.

**Dummy**: Fill a required parameter with a do-nothing implementation when the behavior under test doesn't use it. Example: when testing recording logic, pass a dummy `ListenedDatabase` that does nothing — recording doesn't touch it.

---

## Part V: Process & Mindset (Ch 16, Appendix A)

### Ch 16 — Conclusion

- TDD nudges good design. If a test is hard to write, the code is hard to use.
- Small steps compound. Each passing test is a known-good state you can return to.
- "Speed of iteration will trump quality of iteration" (Daniel Ek). TDD enables fast iteration with confidence.

### Appendix A — Where to Go from Here

- **CI**: Run tests on every push. For us: a GitHub Action that builds the project (compilation = test).
- **Snapshot Testing**: Point-Free's library captures UI as images. Low priority for us — our UI is bar strips, not complex layouts.
- **Modularization**: Split app into modules to speed up builds and enable parallel testing. Relevant when the codebase grows beyond the current ~5 files.

---

## Key Takeaways for Voices

1. **Our log system IS Lodi's test suite.** `logError("TEST FAIL: ...")` = `XCTAssertEqual` failure. `log("TEST PASS: ...")` = assertion passed. The device log is a Spy that records everything.

2. **Arrange-Act-Assert in every selfTest block.** Set up state, perform action, log the proof. Keep the three phases visually distinct.

3. **Write a Test List before coding.** Enumerate behaviors as comments before implementing. Work through them sequentially. This prevents scope creep — the list IS the spec.

4. **Don't let tests crash.** Use safe subscripts and guard-let in test assertions. A crash at line 50 loses proof from lines 51-200.

5. **Fixture extensions for model types.** As `ChunkEntry`/`Recording` grow, centralize construction. Update one fixture, all tests stay green.

6. **Four Test Doubles, one question each.** Stub = what input? Spy = what output? Fake = what state? Dummy = not relevant. We already use Fakes (`InMemoryListenedDatabase`). Name them correctly.

7. **Bug = missing test.** Reproduce via `logError`, fix, flip to `log`, delete trace, commit.

8. **Pure functions first.** `hasListenable`, `allHeard`, `allChunks` are pure computed properties — easiest to test. Push logic toward pure functions, keep the impure shell (Tasks, async, UI) as thin as possible.

---

## Reference

Gio Lodi, *Test-Driven Development in Swift: Compile Better Code with XCTest and TDD* (Apress, 2021). ISBN 978-1-4842-7002-8.

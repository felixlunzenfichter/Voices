# Version 1 Specification

## Voices v1 - Talk to Felix

Voice messaging app where everyone talks directly to Felix.

1. Apple Sign-In
2. Recording list shown as bars only — no visible transcript text
4. Bars indicate recording state, including whether something has been uploaded or listened to
5. Invisible inertial scrubber over the control area — swipe left/right between Play and Record to navigate chunks with native iOS momentum scrolling; no visible scrubber UI, just haptic ticks and the chunk number between the buttons
6. Play button (bottom left)
7. Record button (bottom right)

## Release path

### Shipped

| PR | What |
|----|------|
| #1 | Play/record buttons, project setup, notification sound |
| #2 | WebSocket logging to Claw Control log server |
| #12 | TDD workflow guide |
| #13 | Remove empty Xcode test stubs |
| #15 | Extract VoicesViewModel with mutual-exclusion guard |
| #18 | TDD infrastructure: test target, unit tests, demo chunk UI |
| #19 | Mocked listening with sequential playback progress |
| #20 | Resume playback, listen guards, hasUnplayedChunks |
| #22 | Database seam, PlaybackPosition model, test rewrite |
| #24 | Service-owned tasks: PlaybackService and RecordingService |
| #25 | Chunk-level listened state, cursor/listened separation, white playback cursor |
| #26 | Remove test double duplication, parameterize services, @MainActor Database, baseline fix |
| #28 | Remove Silent services, require explicit deps, add fixture helpers |
| #30 | Invisible inertial seek with SwiftUI scrubber |
| #31 | Cursor haptics, honest cursor semantics, end-of-playback fixes |

### Next PRs

1. **Multi-user conversation model** — Replace single-user recording list with a two-participant conversation. Each message belongs to a sender. Listened state is ownership-aware: a chunk is marked listened only for the participant who did not author it and only when actually played back by that participant; hearing your own message does not mark it listened for you. During playback, my cursor is white and the other participant's cursor is black.
3. **Real database/server** — Replace InMemoryDatabase with persistent storage and server sync. Recordings survive app restarts. Listened state syncs across devices.
4. **Real audio services** — Replace DemoRecordingService/DemoPlaybackService with actual microphone capture, audio encoding, and AVAudioPlayer playback. Chunk intervals driven by real audio segmentation.
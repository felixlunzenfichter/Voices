# Version 1 Specification

## Voices v1 — Talk to Felix

Voice messaging app for a small family-and-friends circle. v0.9 (TestFlight) is hub-and-spoke: everyone talks to Felix. v1.0 generalises to N-to-N: anyone can talk to anyone, including group conversations.

1. Apple Sign-In
2. Recording list shown as bars only — no visible transcript text
3. Bars indicate recording state, including whether something has been uploaded or listened to
4. Invisible inertial scrubber over the control area — swipe left/right between Play and Record to navigate chunks with native iOS momentum scrolling; no visible scrubber UI, just haptic ticks and the chunk number between the buttons
5. Play button (bottom left)
6. Record button (bottom right)

## Locked data model (v1.0)

Two flat top-level Firestore collections. Same shape supports two-person and group conversations.

### `conversations`

```
{
  id: String,
  members: [uid],          // identity of the conversation
  title?: String,          // optional, mostly for groups
  createdAt: Timestamp,
  lastActivityAt: Timestamp
}
```

Member list IS the conversation identity. Membership is immutable for two-person conversations; for groups it can change but every change requires fan-out (see below).

### `recordings`

```
{
  id: String,
  conversationID: String,  // pointer to parent conversation
  author: uid,
  members: [uid],          // DENORMALIZED from conversations.members
  chunks: [Int],
  listened: [Int],         // chunk indices marked listened
  createdAt: Timestamp
}
```

The `members` array is the one piece of denormalization in the model. Firestore has no joins, so without it you couldn't ask "all recordings I'm allowed to see" in a single query. The duplicate is the price of the single-listener model.

**Maintenance cost of the denormalization:**
- Two-person conversations: membership never changes → duplicate is effectively immutable, zero ongoing cost.
- Groups: any member add/remove must batch-update `members` on every existing recording in that conversation. Bounded fan-out, scales with recording count in that one conversation.

## Subscription model (two listeners, identical for every user)

Every user — Felix or otherwise — runs exactly two real-time listeners. Same code path everywhere, no Felix special case.

```
Listener 1 — conversation list:
  conversations
    .where("members", arrayContains: me)
    .orderBy("lastActivityAt", desc)

Listener 2 — recordings (across all my conversations):
  recordings
    .where("members", arrayContains: me)
    .orderBy("createdAt", desc)
    .limit(WINDOW)
```

**Why this works:**
- One stream gives a user every recording they're allowed to see, in any conversation, in chronological order. Client-side groups by `conversationID` to render per-conversation views.
- Firestore's snapshot listener doubles as the offline cache. Whatever you subscribe to is available offline automatically. No separate sync mechanism, no APNs for state.
- Cross-conversation activity is signalled by Listener 1 — `lastActivityAt` bumps on every new recording, the row reorders, the UI updates even while the user is inside a different conversation.

## Ordering

| View | Ordering key |
|------|--------------|
| Conversation list (Listener 1) | `lastActivityAt` desc |
| Recordings timeline (within a conversation) | `createdAt` asc — stable, marking listened does NOT reorder |
| Conversation row's "last activity" | `lastActivityAt` (bumped by writes to recordings; client-side `max(createdAt)` as fallback) |

Listen events are not first-class timeline events in v1. They surface as the unlistened-count dropping in the conversation row; the row does not reorder when someone listens.

## Pagination and windowing

Firestore listeners scale comfortably to thousands of docs; they get expensive in the tens of thousands. The realistic ceiling for Voices is ~10 recordings/day × 365 × 10 years ≈ 36k — three orders of magnitude below "Firebase struggles." Even so, Listener 2 ships with `.limit(WINDOW)` from day one.

- **Initial WINDOW:** 200 most recent recordings across all conversations.
- **Older on demand:** `getDocuments()` pages of 100 when the user scrolls back; drop from memory when scrolled away. Firestore's local cache keeps recently-seen docs available offline.
- **Listener 1** stays unwindowed — conversation count is small (tens at most).

## Security rules (privacy-compatible, matches the queries exactly)

```
match /conversations/{cid} {
  allow read:   if request.auth.uid in resource.data.members;
  allow create: if request.auth.uid in request.resource.data.members;
  allow update: if request.auth.uid in resource.data.members;
}

match /recordings/{rid} {
  allow read:   if request.auth.uid in resource.data.members;
  allow create: if request.auth.uid == request.resource.data.author
             && request.auth.uid in request.resource.data.members;
  allow update: if request.auth.uid in resource.data.members;
}
```

Server-side enforcement mirrors what each client query already expresses. A non-member's query is rejected at the rules layer — they physically cannot subscribe to a conversation they're not in.

## Migration from v0.9 (asymmetric) to v1.0 (N-to-N)

v0.9 ships with a flat `recordings` collection scoped per-user (Felix subscribes to all; others use `author == me OR recipient == me`). v1.0 generalises this without throwing it away.

One-time migration script:

1. **Backfill `members`** on every existing recording: `members = [author, recipient]` (sorted).
2. **Create one `conversations` document per distinct pair** found in recordings. `members = [uid1, uid2]` (sorted). `createdAt = min(recording.createdAt)`. `lastActivityAt = max(recording.createdAt)`.
3. **Backfill `conversationID`** on every recording by pair lookup.
4. **Switch writes** to the new shape (set `members` and `conversationID` on every new recording).
5. **Switch listeners** to the two-listener model.
6. **Drop `recipient`** field from recordings.

Single deploy. No downtime. Existing data preserved.

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
| #44 | Firebase Firestore backend for Voices |

### Remaining PRs to v0.9 (TestFlight)

1. **Real audio recording** — `RealRecordingService` capturing chunked AAC from `AVAudioEngine`.
2. **Firebase Storage upload** — each chunk uploaded; storage path on the Firestore chunk entry.
3. **Real audio playback** — `RealPlaybackService` downloads chunks in order, plays gap-free.
4. **Conversation-list view (Felix)** — grouped client-side by other party from today's flat shape.
5. **Multi-party routing** — `recipient` field + scoped subscriptions for non-Felix users (`author == me OR recipient == me`).
6. **Apple Sign-In + Firebase Auth** — replace hardcoded harness UUIDs with real `auth.uid`.
7. **Security rules (v0.9 shape)** — read iff `auth.uid in [author, recipient]`.
8. **Production Firebase project + TestFlight** — single bundled ship PR.

### v1.0 — N-to-N generalisation

After v0.9 ships and is stable in TestFlight:

9. **Conversations collection + `members` denormalization** — introduce `conversations` docs; backfill `members` and `conversationID` on recordings.
10. **Two-listener subscription model** — replace v0.9's per-user scoped query with the symmetric `members arrayContains me` listeners for both collections.
11. **Group conversation creation flow** — UI for starting a new conversation with any subset of users.
12. **Security rules (v1.0 shape)** — switch to the `members`-based rules above.
13. **Drop `recipient`** — remove the v0.9 field once nothing reads it.

## Highest-risk unknown

Gap-free playback after the AAC chunk round-trip. AAC encoders prefix encoded chunks with implicit priming samples; concatenating ~0.5–1s chunks downloaded from Storage may produce audible clicks. The encoder choice has to be made during the "Real audio recording" PR because it constrains everything downstream. Mitigations exist (server-side re-encode, switch to Opus in CAF, accept slight gaps) but the trade-off is unproven in this codebase.

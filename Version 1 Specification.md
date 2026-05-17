# Version 1 Specification

## Voices v1 — Talk to Felix

Voice messaging app for a small family-and-friends circle. The data model is locked from v0.9 onward: the same Firestore shape supports the v0.9 TestFlight (everyone has a conversation with Felix) and the v1.0 release (anyone talks to anyone, including groups). v1.0 is UI-only on top of v0.9 — no schema changes, no data migration.

1. Apple Sign-In
2. Recording list shown as bars only — no visible transcript text
3. Bars indicate recording state, including whether something has been uploaded or listened to
4. Invisible inertial scrubber over the control area — swipe left/right between Play and Record to navigate chunks with native iOS momentum scrolling; no visible scrubber UI, just haptic ticks and the chunk number between the buttons
5. Play button (bottom left)
6. Record button (bottom right)

## Locked data model (v0.9 and v1.0)

Two flat top-level Firestore collections. The same shape supports two-person conversations and groups — a two-person conversation is just `members.count == 2`.

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

Member list IS the conversation identity. For two-person conversations membership is immutable; for groups (v1.0 UI) it can change with bounded fan-out.

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

The `members` array is the one piece of denormalization. Firestore has no joins, so without it you couldn't ask "all recordings I'm allowed to see" in a single query. The duplicate is the price of the single-listener model.

**Maintenance cost of the denormalization:**
- Two-person conversations: membership never changes → duplicate is effectively immutable, zero ongoing cost.
- Groups (v1.0): any member add/remove must batch-update `members` on every existing recording in that conversation. Bounded fan-out, scales with recording count in that one conversation.

### No `recipient` field

The "who is this for" is always derivable as `members \ {author}`. For two-person conversations that's exactly the other party; for groups it's everyone else. A separate `recipient` field would duplicate `members` and force an asymmetric Felix-versus-everyone query — both unnecessary.

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

In v0.9 every non-Felix user has exactly one conversation, so their UX is a single thread. Felix is in every conversation, so his Listener 1 surfaces a list. Same query, different rendering.

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

## Writing recordings (find-or-create conversation)

The one extra cost of locking the v1.0 model from day one is that every "send a message to X" must first ensure a conversation document exists for that pair. Algorithm:

```
1. Compute sorted pair key from [author, otherParticipant].
2. conversationDoc = conversations.where("members", "==", sortedPair).limit(1)
3. If empty: create conversations doc with members=sortedPair, createdAt=now.
4. Write recording with conversationID set + members array set.
5. Bump conversations.lastActivityAt = serverTimestamp().
```

Three writes on first-ever contact (lookup, conversation create, recording create). Two writes per subsequent recording (recording + `lastActivityAt` bump). Negligible cost; the lookup result can be cached client-side per pair for the session.

## Security rules

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

Server-side enforcement mirrors what each client query already expresses. A non-member's query is rejected at the rules layer — they physically cannot subscribe to a conversation they're not in. These rules are the same in v0.9 and v1.0.

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
4. **Conversations collection + two-listener subscription model** — introduce the locked v1.0 data shape (conversations doc, denormalized `members` on recordings, find-or-create on send, two listeners per user). Replaces today's flat single-collection shape with the final one.
5. **Conversation-list view (Felix)** — renders Listener 1's results as grouped rows; for non-Felix users the same listener resolves to one row, opening directly into the thread.
6. **Apple Sign-In + Firebase Auth** — replace harness UUIDs with real `auth.uid`.
7. **Security rules** — the locked `members`-based rules above.
8. **Production Firebase project + TestFlight** — single bundled ship PR.

### v1.0 — UI only

v1.0 ships group conversations without changing the database. The model already supports them; v0.9 just had no UI to create one.

9. **New-conversation flow** — UI for starting a conversation with one or more other users; creates a `conversations` document with the chosen `members` array.
10. **Group-aware rendering** — conversation row shows multi-author labels; in-thread chunks identify their author; per-member unread (if needed) computed client-side from `listened`.
11. **Membership changes** — UI for adding/removing members from an existing group, with the bounded `members`-fan-out write to recordings in that conversation.

No schema migration, no security rule change, no listener change between v0.9 and v1.0.

## Highest-risk unknown

Gap-free playback after the AAC chunk round-trip. AAC encoders prefix encoded chunks with implicit priming samples; concatenating ~0.5–1s chunks downloaded from Storage may produce audible clicks. The encoder choice has to be made during the "Real audio recording" PR because it constrains everything downstream. Mitigations exist (server-side re-encode, switch to Opus in CAF, accept slight gaps) but the trade-off is unproven in this codebase.

# Version 1 Specification

## Voices v1 — Talk to Felix

Voice messaging app for a small family-and-friends circle. Every conversation is between exactly two people.

**Release split:**
- **v0.9 (TestFlight)** — hub-and-spoke. Every conversation includes Felix. Mama and Marina each have one conversation: with Felix.
- **v1.0 (App Store)** — any pair. Mama can start a conversation with Marina without Felix in it.

The data model is the same in both versions. The only difference is the new-conversation UI: v0.9 fixes Felix as one participant, v1.0 lets the user pick any other user. No data migration between versions.

1. Apple Sign-In
2. Recording list shown as bars only — no visible transcript text
3. Bars indicate recording state, including whether something has been uploaded or listened to
4. Invisible inertial scrubber over the control area — swipe left/right between Play and Record to navigate chunks with native iOS momentum scrolling; no visible scrubber UI, just haptic ticks and the chunk number between the buttons
5. Play button (bottom left)
6. Record button (bottom right)

## Data model

Two flat top-level Firestore collections.

### `conversations`

```
{
  id: String,
  members: [uid],          // exactly two; identity of the conversation
  createdAt: Timestamp,
  lastActivityAt: Timestamp
}
```

Member list IS the conversation identity. Membership is immutable.

### `recordings`

```
{
  id: String,
  conversationID: String,  // pointer to parent conversation
  author: uid,
  members: [uid],          // DENORMALIZED from conversations.members
  pendingChunks:  [Int],   // bytes on producer's device, not yet on Mac
  uploadedChunks: [Int],   // Mac has the bytes; anyone can GET
  listened: [Int],         // chunk indices marked listened
  createdAt: Timestamp
}
```

The `members` array is the one piece of denormalization. Firestore has no joins, so without it you couldn't ask "all recordings I'm allowed to see" in a single query. The duplicate is the price of the single-listener model.

Because membership is immutable in v1, the duplicate is effectively immutable too — zero ongoing maintenance cost.

The `pendingChunks` / `uploadedChunks` split keeps recordings tiny in Firestore (no bytes, only integers) and lets every client observe each chunk's sync state through the same listener. Per-chunk UI states fall out as set membership: `pending && !uploaded` = recorded here, not yet uploaded; `uploaded && local file present` = synced; `uploaded && local file absent` = uploaded, not yet downloaded.

### No `recipient` field

The "who is this for" is always derivable as `members \ {author}` — exactly the other participant. A separate `recipient` field would duplicate `members` and force an asymmetric Felix-versus-everyone query — both unnecessary.

## Chunk byte storage (hybrid: Firestore + Mac blob server)

Firestore holds **metadata only**. Raw audio bytes live on a tiny Mac-hosted HTTP service. Three endpoints, filesystem-backed, no DB:

```
PUT    /blobs/<rid>/<idx>     body = raw PCM bytes
GET    /blobs/<rid>/<idx>     → bytes (200) / 404
DELETE /blobs                 wipe (tests only)
```

**Why not Firebase Storage:** the Storage SDK's dynamic-framework wrapper has a per-app emulator-config restriction that breaks the writer/reader test pair, and the test infra/rules/emulator setup costs more than a 50-line Node service.

**Why not inline base64 in Firestore:** chunks of ~32 KB raw PCM ≈ 43 KB base64. ~22 chunks per recording fits in Firestore's 1 MB per-doc cap, then writes start rejecting silently. Proven dead-end.

**Per-device local cache.** Bytes are written to `Library/Caches/voices-firebase-cache/<namespace>/<rid>/<idx>.pcm` on the device (stable across launches; OS-purge-eligible under disk pressure). Same-device reads never round-trip; only the first reader on each remote device fetches from the Mac.

### Sync handshake

`appendChunk` writes bytes to local disk, then `arrayUnion(pendingChunks, idx)` on Firestore. Firestore's listener fires locally (`hasPendingWrites = true`) so the writer's UI sees the chunk at 80% opacity immediately. A recursive upload loop, driven from the same listener, picks up chunks where bytes are local but not yet on the Mac (i.e. `pending && !uploaded`), PUTs them, then atomically moves the index from `pendingChunks` to `uploadedChunks`. Other devices observe the move server-side; their symmetric download loop GETs newly-uploaded chunks they don't have locally.

**Offline.** Local write always succeeds. The `arrayUnion` is queued by Firestore's offline cache; the listener still fires locally so the writer's UI is correct. The upload loop's `PUT` retries on the next listener fire after reconnect. Order is preserved per-recording because chunk indices are appended in chunk order at the source.

### Audio format

PCM, not AAC. 48 kHz mono float32, non-interleaved — the canonical wire format.

| Setting | Value |
|---|---|
| Sample rate | 48 000 Hz |
| Channels | 1 (mono) |
| Sample size | 4 B (float32) |
| Bitrate | ~192 KB/s (≈ 1.54 Mbit/s) |
| Tap buffer size | 8 192 frames (~170 ms) |
| Chunk size | ~32 KB |
| Chunk rate | ~5.9 chunks/s |

AAC was tried and dropped: each independently encoded AAC chunk carries ~44 ms of encoder priming silence, producing audible clicks at chunk boundaries. PCM has no priming, no inter-frame state, and concatenates bit-exact. Later we can revisit Opus if the ~10× bitrate vs AAC becomes a problem; AAC-per-chunk is structurally wrong for streaming.

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
- One stream gives a user every recording they're allowed to see, in any conversation, in chronological order. Client-side grouping by `conversationID` renders per-conversation views.
- Firestore's snapshot listener doubles as the offline cache. Whatever you subscribe to is available offline automatically. No separate sync mechanism, no APNs for state.
- Cross-conversation activity is signalled by Listener 1 — `lastActivityAt` bumps on every new recording, the row reorders, the UI updates even while the user is inside a different conversation.

Felix is in every conversation, so his Listener 1 surfaces a list. Other users are typically in one conversation (with Felix), so their Listener 1 resolves to a single row — the UI opens directly into that thread. Same query, different rendering.

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

Every "send a message to X" must first ensure a conversation document exists for that pair. Algorithm:

```
1. Compute sorted pair key from [author, otherParticipant].
2. conversationDoc = conversations.where("members", "==", sortedPair).limit(1)
3. If empty: create conversations doc with members=sortedPair, createdAt=now.
4. Write recording with conversationID set + members array set.
5. Bump conversations.lastActivityAt = serverTimestamp().
```

Three writes on first-ever contact (lookup, conversation create, recording create). Two writes per subsequent recording (recording + `lastActivityAt` bump). The lookup result is cached client-side per pair for the session.

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

Server-side enforcement mirrors what each client query already expresses. A non-member's query is rejected at the rules layer — they physically cannot subscribe to a conversation they're not in.

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
| #48 | Real PCM recording + playback, hybrid Firestore/Mac-blob backend, read-through chunk cache (in review) |

### Remaining PRs to v0.9 (TestFlight)

1. **Conversations collection + two-listener subscription model** — introduce the locked data shape (conversations doc, denormalized `members` on recordings, find-or-create on send, two listeners per user). Replaces today's flat single-collection shape with the final one.
2. **Conversation-list view** — renders Listener 1's results; for v0.9 users with one conversation the list collapses to a single row and the UI opens directly into the thread.
3. **Apple Sign-In + Firebase Auth** — replace harness UUIDs with real `auth.uid`.
4. **Security rules** — the locked `members`-based rules above.
5. **Hub-and-spoke UI constraint** — new-conversation flow fixes Felix as one of the two participants. Felix's app can pick any other user; non-Felix users have no new-conversation entry point (their one conversation already exists).
6. **Mac blob server → hosted server** — the in-development backend currently runs as a Node service on Felix's Mac (reached via Tailscale). For TestFlight it has to move to a real server (Fly.io / Render / a small VPS). Same three-route API, same client code; only the base URL changes.
7. **Production Firebase project + TestFlight** — single bundled ship PR.

### Remaining PRs to v1.0 (App Store)

Same data model, same listeners, same security rules. The only change is lifting the v0.9 UI constraint.

10. **Open new-conversation flow** — non-Felix users gain a new-conversation entry point; participant picker offers any other user, not just Felix. Existing `find-or-create` write path is unchanged.
11. **App Store submission** — review-ready build, screenshots, privacy disclosures.

## Highest-risk unknown

Moving the Mac-hosted blob server to a real hosted server. Today the bytes live on Felix's Mac reached over Tailscale, which works for development and is what PR #48 ships against. Putting the same Node service behind a public address adds: a deployment target (Fly.io / Render / VPS), TLS termination, persistent disk (or migrating bytes to S3-class object storage), auth tied to Apple Sign-In, and rate/size limits. None of these are technically hard individually; the unknown is whether we land them as a small focused PR or end up rewriting the data path for an object-storage SDK along the way.

Previously the high-risk item was gap-free playback after the AAC chunk round-trip. That risk is **closed**: we ship raw PCM, which has no encoder priming and concatenates bit-exact. Storage size is higher (~192 KB/s vs ~8 KB/s for AAC) but irrelevant at v0.9 scale; Opus is the long-term lever if/when bandwidth matters.

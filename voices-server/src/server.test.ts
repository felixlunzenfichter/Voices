import { test } from "node:test";
import assert from "node:assert/strict";
import { startServer, applyMutation } from "./server.ts";
import { MemoryStorage, FileStorage } from "./storage.ts";
import type { State } from "./types.ts";
import { promises as fs } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

async function getJSON(url: string): Promise<unknown> {
  const res = await fetch(url);
  return await res.json();
}

async function postJSON(url: string, body: unknown): Promise<Response> {
  return fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

test("Server: addRecording then GET /state shows it", async () => {
  const storage = new MemoryStorage();
  const handle = await startServer({ port: 0, storage });
  try {
    const base = `http://127.0.0.1:${handle.port}`;
    const initial = (await getJSON(`${base}/state`)) as State;
    assert.deepStrictEqual(initial.recordings, []);

    const rec = {
      id: "11111111-1111-1111-1111-111111111111",
      author: "22222222-2222-2222-2222-222222222222",
      audioChunks: [],
    };
    const res = await postJSON(`${base}/mutation`, { type: "addRecording", recording: rec });
    assert.strictEqual(res.status, 204);

    const after = (await getJSON(`${base}/state`)) as State;
    assert.strictEqual(after.recordings.length, 1);
    assert.strictEqual(after.recordings[0]!.id, rec.id);
  } finally {
    await handle.close();
  }
});

test("Server: state survives server restart via FileStorage", async () => {
  const dir = await fs.mkdtemp(join(tmpdir(), "voices-server-restart-"));
  const path = join(dir, "state.json");
  const storage1 = new FileStorage(path);
  const handle1 = await startServer({ port: 0, storage: storage1 });
  try {
    const base = `http://127.0.0.1:${handle1.port}`;
    await postJSON(`${base}/mutation`, {
      type: "addRecording",
      recording: { id: "aaaa-bb", author: "cccc-dd", audioChunks: [] },
    });
  } finally {
    await handle1.close();
  }

  // Fresh server, fresh in-memory state, same file. The persisted
  // mutation must come back.
  const storage2 = new FileStorage(path);
  const handle2 = await startServer({ port: 0, storage: storage2 });
  try {
    const base = `http://127.0.0.1:${handle2.port}`;
    const after = (await getJSON(`${base}/state`)) as State;
    assert.strictEqual(after.recordings.length, 1);
    assert.strictEqual(after.recordings[0]!.id, "aaaa-bb");
  } finally {
    await handle2.close();
  }
});

test("applyMutation: markListened with viewer == author is a no-op (own-message rule)", () => {
  const me = "11111111-1111-1111-1111-111111111111";
  const initial: State = {
    recordings: [{ id: "rec-1", author: me, audioChunks: [{ index: 0, listened: false }] }],
  };
  const after = applyMutation(initial, { type: "markListened", recordingID: "rec-1", chunkIndex: 0, by: me });
  assert.strictEqual(after.recordings[0]!.audioChunks[0]!.listened, false);
});

test("applyMutation: markListened with viewer != author marks the chunk", () => {
  const me = "11111111-1111-1111-1111-111111111111";
  const other = "22222222-2222-2222-2222-222222222222";
  const initial: State = {
    recordings: [{ id: "rec-1", author: me, audioChunks: [{ index: 0, listened: false }] }],
  };
  const after = applyMutation(initial, { type: "markListened", recordingID: "rec-1", chunkIndex: 0, by: other });
  assert.strictEqual(after.recordings[0]!.audioChunks[0]!.listened, true);
});

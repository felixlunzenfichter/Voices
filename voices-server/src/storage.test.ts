import { test } from "node:test";
import assert from "node:assert/strict";
import { promises as fs } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { FileStorage } from "./storage.ts";
import type { State } from "./types.ts";

async function tempPath(): Promise<string> {
  const dir = await fs.mkdtemp(join(tmpdir(), "voices-server-test-"));
  return join(dir, "state.json");
}

test("FileStorage round-trips a state with one recording", async () => {
  const path = await tempPath();
  const writer = new FileStorage(path);
  const state: State = {
    recordings: [
      {
        id: "11111111-1111-1111-1111-111111111111",
        author: "22222222-2222-2222-2222-222222222222",
        audioChunks: [
          { index: 0, listened: false },
          { index: 1, listened: true },
        ],
      },
    ],
  };
  await writer.save(state);

  const reader = new FileStorage(path);
  const loaded = await reader.load();
  assert.deepStrictEqual(loaded, state);
});

test("FileStorage returns empty state when the file does not exist", async () => {
  const path = await tempPath();
  const storage = new FileStorage(path);
  const loaded = await storage.load();
  assert.deepStrictEqual(loaded, { recordings: [] });
});

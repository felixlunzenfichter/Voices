// Mac-hosted shared-state server. HTTP, JSON, no framework — just
// Node's stdlib `http` plus the Storage seam.
//
//   GET  /state      → 200 { recordings: Recording[] }
//   POST /mutation   → 204; body is one of types.Mutation
//
// Persistence: FileStorage(~/voices-server/state.json) by default.
// Override path via VOICES_STATE_PATH; override port via VOICES_PORT.

import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { homedir } from "node:os";
import { join } from "node:path";
import { FileStorage, type Storage } from "./storage.ts";
import type { Mutation, State } from "./types.ts";

const DEFAULT_PORT = 9995;
const DEFAULT_STATE_PATH = join(homedir(), "voices-server", "state.json");

export interface ServerHandle {
  port: number;
  close: () => Promise<void>;
}

export async function startServer(opts: {
  port?: number;
  storage: Storage;
}): Promise<ServerHandle> {
  let state: State = await opts.storage.load();

  const httpServer = createServer(async (req, res) => {
    try {
      await route(req, res);
    } catch (err) {
      console.error("[error]", err);
      respond(res, 500, { error: String(err) });
    }
  });

  async function route(req: IncomingMessage, res: ServerResponse): Promise<void> {
    if (req.method === "GET" && req.url === "/state") {
      const peer = req.socket.remoteAddress ?? "?";
      console.log(`[GET /state] from ${peer} recordings=${state.recordings.length}`);
      respond(res, 200, state);
      return;
    }
    if (req.method === "POST" && req.url === "/mutation") {
      const body = await readBody(req);
      const mutation = JSON.parse(body) as Mutation;
      state = applyMutation(state, mutation);
      await opts.storage.save(state);
      console.log(`[mutation] ${describe(mutation)}`);
      res.writeHead(204);
      res.end();
      return;
    }
    respond(res, 404, { error: "not found" });
  }

  return new Promise((resolve) => {
    httpServer.listen(opts.port ?? DEFAULT_PORT, "0.0.0.0", () => {
      const addr = httpServer.address();
      const port = typeof addr === "object" && addr ? addr.port : (opts.port ?? DEFAULT_PORT);
      console.log(`voices-server listening on http://0.0.0.0:${port}`);
      resolve({
        port,
        close: () => new Promise<void>((r) => httpServer.close(() => r())),
      });
    });
  });
}

export function applyMutation(state: State, m: Mutation): State {
  const recordings = state.recordings.slice();
  switch (m.type) {
    case "addRecording":
      recordings.push({
        id: m.recording.id,
        author: m.recording.author,
        audioChunks: (m.recording.audioChunks ?? []).map((c) => ({ ...c })),
      });
      break;
    case "appendChunk": {
      const idx = recordings.findIndex((r) => r.id === m.recordingID);
      if (idx >= 0) {
        recordings[idx] = {
          ...recordings[idx]!,
          audioChunks: [...recordings[idx]!.audioChunks, { index: m.chunk.index, listened: !!m.chunk.listened }],
        };
      }
      break;
    }
    case "removeRecording":
      return { recordings: recordings.filter((r) => r.id !== m.recordingID) };
    case "markListened": {
      const idx = recordings.findIndex((r) => r.id === m.recordingID);
      if (idx < 0) break;
      const rec = recordings[idx]!;
      // Author-aware rule: viewer == author → no-op. Mirrors
      // InMemoryDatabase.markListened(...:by:) on the iOS side.
      if (m.by !== undefined && m.by === rec.author) break;
      const chunks = rec.audioChunks.slice();
      const c = chunks[m.chunkIndex];
      if (!c) break;
      chunks[m.chunkIndex] = { ...c, listened: true };
      recordings[idx] = { ...rec, audioChunks: chunks };
      break;
    }
  }
  return { recordings };
}

function describe(m: Mutation): string {
  const short = (s: string | undefined) => (s ?? "").slice(0, 8);
  switch (m.type) {
    case "addRecording": return `addRecording rec=${short(m.recording.id)} author=${short(m.recording.author)}`;
    case "appendChunk": return `appendChunk rec=${short(m.recordingID)} index=${m.chunk.index}`;
    case "removeRecording": return `removeRecording rec=${short(m.recordingID)}`;
    case "markListened": return `markListened rec=${short(m.recordingID)} index=${m.chunkIndex} by=${short(m.by)}`;
  }
}

function readBody(req: IncomingMessage): Promise<string> {
  return new Promise((resolve, reject) => {
    let body = "";
    req.setEncoding("utf8");
    req.on("data", (c) => (body += c));
    req.on("end", () => resolve(body));
    req.on("error", reject);
  });
}

function respond(res: ServerResponse, status: number, body: unknown): void {
  res.writeHead(status, { "Content-Type": "application/json" });
  res.end(JSON.stringify(body));
}

// Entry point when run directly via tsx.
const isMain = import.meta.url === `file://${process.argv[1]}`;
if (isMain) {
  const port = process.env.VOICES_PORT ? Number(process.env.VOICES_PORT) : DEFAULT_PORT;
  const path = process.env.VOICES_STATE_PATH ?? DEFAULT_STATE_PATH;
  const storage = new FileStorage(path);
  await startServer({ port, storage });
  console.log(`  state file: ${path}`);
}

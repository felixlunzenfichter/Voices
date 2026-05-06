// Storage seam. The server's route handlers depend only on this
// interface, never on a concrete implementation. Today: FileStorage
// (flat JSON file). Tomorrow: PostgresStorage that implements the
// same shape — no route changes required.

import { promises as fs } from "node:fs";
import { dirname } from "node:path";
import type { State } from "./types.js";

export interface Storage {
  load(): Promise<State>;
  save(state: State): Promise<void>;
}

const EMPTY: State = { recordings: [] };

/** Single-file JSON persistence. Atomic write via temp + rename. */
export class FileStorage implements Storage {
  constructor(private readonly path: string) {}

  async load(): Promise<State> {
    try {
      const raw = await fs.readFile(this.path, "utf8");
      const parsed = JSON.parse(raw) as State;
      if (!parsed || !Array.isArray(parsed.recordings)) return { ...EMPTY };
      return parsed;
    } catch (err: unknown) {
      // Missing file is the clean-start case.
      if (isErrnoCode(err, "ENOENT")) return { ...EMPTY };
      throw err;
    }
  }

  async save(state: State): Promise<void> {
    await fs.mkdir(dirname(this.path), { recursive: true });
    const tmp = `${this.path}.tmp`;
    await fs.writeFile(tmp, JSON.stringify(state, null, 2), "utf8");
    await fs.rename(tmp, this.path);
  }
}

/** In-process test double. Used by server.test.ts. */
export class MemoryStorage implements Storage {
  constructor(private state: State = { ...EMPTY }) {}
  async load(): Promise<State> { return structuredClone(this.state); }
  async save(state: State): Promise<void> { this.state = structuredClone(state); }
}

function isErrnoCode(err: unknown, code: string): boolean {
  return typeof err === "object" && err !== null && "code" in err && (err as { code: unknown }).code === code;
}

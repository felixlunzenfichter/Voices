import express, { Request, Response } from "express";
import fs from "node:fs/promises";
import { createReadStream } from "node:fs";
import path from "node:path";

// Audio blobs live on disk under <repo>/mac-server/blobs/<rid>/<idx>.pcm.
// Firestore holds metadata; this server is bytes only — no DB.
const BLOBS_DIR = path.resolve(process.cwd(), "blobs");
await fs.mkdir(BLOBS_DIR, { recursive: true });

const app = express();
app.use(express.raw({ type: "application/octet-stream", limit: "50mb" }));

const blobPath = (rid: string, idx: string) =>
    path.join(BLOBS_DIR, rid, `${idx}.pcm`);

app.put("/blobs/:rid/:idx", async (req: Request, res: Response) => {
    const { rid, idx } = req.params;
    if (!/^[0-9a-fA-F-]+$/.test(rid) || !/^\d+$/.test(idx)) {
        return res.status(400).end();
    }
    const p = blobPath(rid, idx);
    await fs.mkdir(path.dirname(p), { recursive: true });
    await fs.writeFile(p, req.body as Buffer);
    res.status(200).end();
});

app.get("/blobs/:rid/:idx", async (req: Request, res: Response) => {
    const { rid, idx } = req.params;
    const p = blobPath(rid, idx);
    try {
        await fs.access(p);
    } catch {
        return res.status(404).end();
    }
    res.setHeader("Content-Type", "application/octet-stream");
    createReadStream(p).pipe(res);
});

app.delete("/blobs", async (_req: Request, res: Response) => {
    await fs.rm(BLOBS_DIR, { recursive: true, force: true });
    await fs.mkdir(BLOBS_DIR, { recursive: true });
    res.status(204).end();
});

const PORT = 7654;
app.listen(PORT, "0.0.0.0", () => {
    console.log(`voices-mac-server listening on 0.0.0.0:${PORT}`);
    console.log(`blobs dir: ${BLOBS_DIR}`);
});

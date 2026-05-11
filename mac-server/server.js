// Mac-hosted event/revision cloud for Voices. Plain Node http, no
// framework, no dependencies. The history is the truth; the counter
// is the index into it; the recordings projection is convenience.
//
// State held in memory (durable storage is a later commit):
//   revision    : strictly monotonic, no gaps; 0 = before any write
//   recordings  : projection — fold(empty, history[1..revision])
//   history     : append-only [(revision, event)]
//   subscribers : open SSE connections with their last-shipped `since`
//
// Endpoints:
//   GET  /state             → 200 { revision, recordings }
//                             cold-start snapshot for fresh clients
//   POST /events            → body { baseRevision, event }
//                             200 { revision }                                    if baseRevision == revision
//                             409 { revision, events: [...] since baseRevision }  if baseRevision <  revision
//                             400                                                  on malformed body
//   GET  /events?since=N    → text/event-stream
//                             on connect: replay every (r, e) with r > N
//                             after: one frame per accepted POST /events
//   POST /reset             → 200, clears everything to revision=0, recordings=[],
//                             history=[]. Test helper; harmless in production
//                             until we restrict it.

import http from 'node:http';
import { URL } from 'node:url';

const PORT = 9995;

let revision = 0;
let recordings = [];
let history = [];
const subscribers = [];

function apply(event) {
    switch (event.type) {
        case 'recordingAdded': {
            const r = event.recording;
            if (!recordings.find(x => x.id === r.id)) {
                recordings.push({
                    id: r.id,
                    author: r.author,
                    audioChunks: (r.audioChunks ?? []).map(c => ({ ...c })),
                });
            }
            return;
        }
        case 'chunkAppended': {
            const rec = recordings.find(x => x.id === event.recordingID);
            if (rec && !rec.audioChunks.find(c => c.index === event.chunk.index)) {
                rec.audioChunks.push({ ...event.chunk });
            }
            return;
        }
        case 'chunkListened': {
            const rec = recordings.find(x => x.id === event.recordingID);
            if (!rec || rec.author === event.by) return;
            const ch = rec.audioChunks.find(c => c.index === event.chunkIndex);
            if (ch) ch.listened = true;
            return;
        }
    }
}

function broadcastFrame(rev, event) {
    const frame = `data: ${JSON.stringify({ revision: rev, event })}\n\n`;
    for (const s of subscribers) {
        if (s.since < rev) {
            s.res.write(frame);
            s.since = rev;
        }
    }
}

function readBody(req) {
    return new Promise((resolve, reject) => {
        let buf = '';
        req.on('data', chunk => buf += chunk);
        req.on('end', () => resolve(buf));
        req.on('error', reject);
    });
}

const server = http.createServer(async (req, res) => {
    const u = new URL(req.url, `http://${req.headers.host}`);

    if (req.method === 'GET' && u.pathname === '/state') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ revision, recordings }));
        return;
    }

    if (req.method === 'POST' && u.pathname === '/events') {
        const body = await readBody(req);
        let parsed;
        try { parsed = JSON.parse(body); }
        catch { res.writeHead(400); res.end(); return; }
        const { baseRevision, event } = parsed;
        if (typeof baseRevision !== 'number' || !event) {
            res.writeHead(400); res.end(); return;
        }
        if (baseRevision < revision) {
            const missed = history.filter(h => h.revision > baseRevision);
            res.writeHead(409, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ revision, events: missed }));
            return;
        }
        if (baseRevision > revision) {
            res.writeHead(400); res.end(); return;
        }
        revision += 1;
        apply(event);
        history.push({ revision, event });
        broadcastFrame(revision, event);
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ revision }));
        return;
    }

    if (req.method === 'GET' && u.pathname === '/events') {
        const since = parseInt(u.searchParams.get('since') ?? '0', 10);
        res.writeHead(200, {
            'Content-Type': 'text/event-stream',
            'Cache-Control': 'no-cache',
            'Connection': 'keep-alive',
        });
        // Replay missed events first.
        let lastShipped = since;
        for (const h of history) {
            if (h.revision > since) {
                res.write(`data: ${JSON.stringify(h)}\n\n`);
                lastShipped = h.revision;
            }
        }
        const sub = { res, since: lastShipped };
        subscribers.push(sub);
        req.on('close', () => {
            const i = subscribers.indexOf(sub);
            if (i >= 0) subscribers.splice(i, 1);
        });
        return;
    }

    if (req.method === 'POST' && u.pathname === '/reset') {
        revision = 0;
        recordings = [];
        history = [];
        // Close all subscriber connections so they re-subscribe with since=0.
        for (const s of subscribers.splice(0)) {
            try { s.res.end(); } catch {}
        }
        res.writeHead(200);
        res.end();
        return;
    }

    res.writeHead(404);
    res.end();
});

server.listen(PORT, () => {
    console.log(`voices-server listening on :${PORT}`);
});

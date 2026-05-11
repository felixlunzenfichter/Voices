// Mac-hosted shared-state server for the Voices iOS tests (and
// eventually the running app). Plain Node http, no framework, no
// dependencies. In-memory snapshot only — persistence is a later
// commit.
//
//   GET  /state   →  200, body = { revision, recordings }
//   POST /state   →  200, body = { revision }, side effect:
//                    revision++ then recordings = JSON-decoded body;
//                    SSE broadcast to every /events subscriber.
//   GET  /events  →  200, text/event-stream. On connect: one frame
//                    with the current { revision, recordings }. Then
//                    one frame per subsequent POST /state.
//
// `revision` is the cloud's monotonically increasing cursor.

import http from 'node:http';

const PORT = 9995;
let revision = 0;
let recordings = [];
const subscribers = [];

function broadcastState() {
    const payload = `data: ${JSON.stringify({ revision, recordings })}\n\n`;
    for (const s of subscribers) {
        s.write(payload);
    }
}

const server = http.createServer((req, res) => {
    if (req.method === 'GET' && req.url === '/state') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ revision, recordings }));
        return;
    }
    if (req.method === 'POST' && req.url === '/state') {
        let body = '';
        req.on('data', chunk => body += chunk);
        req.on('end', () => {
            try {
                const parsed = JSON.parse(body);
                revision += 1;
                recordings = parsed;
                broadcastState();
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ revision }));
            } catch {
                res.writeHead(400);
                res.end();
            }
        });
        return;
    }
    if (req.method === 'GET' && req.url === '/events') {
        res.writeHead(200, {
            'Content-Type': 'text/event-stream',
            'Cache-Control': 'no-cache',
            'Connection': 'keep-alive',
        });
        res.write(`data: ${JSON.stringify({ revision, recordings })}\n\n`);
        subscribers.push(res);
        req.on('close', () => {
            const i = subscribers.indexOf(res);
            if (i >= 0) subscribers.splice(i, 1);
        });
        return;
    }
    res.writeHead(404);
    res.end();
});

server.listen(PORT, () => {
    console.log(`mac-server listening on :${PORT}`);
});

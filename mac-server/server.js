// Mac-hosted shared-state server for the Voices iOS tests (and
// eventually the running app). Plain Node http, no framework, no
// dependencies. In-memory snapshot only — persistence is a later
// commit.
//
//   GET  /state  →  200, body = { revision, recordings }
//   POST /state  →  200, body = { revision }, side effect:
//                   revision++ then recordings = JSON-decoded body
//
// `revision` is the cloud's monotonically increasing cursor — it
// counts the number of successfully accepted writes since process
// start. Clients carry it as `baseRevision` on the next POST (later
// step), and consume it via the SSE event stream (later step). For
// now it is published on GET/POST but no client validates it.

import http from 'node:http';

const PORT = 9995;
let revision = 0;
let recordings = [];

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
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ revision }));
            } catch {
                res.writeHead(400);
                res.end();
            }
        });
        return;
    }
    res.writeHead(404);
    res.end();
});

server.listen(PORT, () => {
    console.log(`mac-server listening on :${PORT}`);
});

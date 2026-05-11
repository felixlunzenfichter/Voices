// Mac-hosted shared-state server for the Voices iOS test 1 (and
// eventually the running app). Plain Node http, no framework, no
// dependencies. In-memory snapshot only — persistence is a later
// commit.
//
//   GET  /state  →  200, body = JSON [Recording]
//   POST /state  →  200, side effect: stored = JSON-decoded body
//
// Wire shape matches Voices/Voices/Infra/HTTPCloud.swift on the iOS
// side: raw [Recording] array, not wrapped.

import http from 'node:http';

const PORT = 9995;
let recordings = [];

const server = http.createServer((req, res) => {
    if (req.method === 'GET' && req.url === '/state') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(recordings));
        return;
    }
    if (req.method === 'POST' && req.url === '/state') {
        let body = '';
        req.on('data', chunk => body += chunk);
        req.on('end', () => {
            try {
                recordings = JSON.parse(body);
                res.writeHead(200);
                res.end();
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

// server-fixed.js
const http = require('http');
const { hashAsync } = require('./slow-hash');
const { startLoopMonitor } = require('./loop-monitor');

const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('OK\n');
    return;
  }

  if (req.url === '/hash') {
    // Same hash, same settings — but crypto.pbkdf2 (no "Sync") runs on libuv's background thread pool. The main thread is free the moment this line returns.
    hashAsync('hunter2', (err, hash) => {
      if (err) {
        console.error('hash failed:', err.message);
        res.writeHead(500, { 'Content-Type': 'text/plain' });
        res.end('hash failed\n');
        return;
      }
      res.writeHead(200, { 'Content-Type': 'text/plain' });
      res.end(`hashed: ${hash.slice(0, 16)}...\n`);
    });
    return;
  }

  res.writeHead(404, { 'Content-Type': 'text/plain' });
  res.end('not found\n');
});

server.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    console.error('port 3000 is already in use: stop the old server (Ctrl+C in its terminal) and try again');
  } else {
    console.error('server error:', err.message);
  }
  process.exit(1);
});

server.listen(3000, () => {
  console.log('FIXED (non-blocking) server on http://localhost:3000');
  startLoopMonitor();
});

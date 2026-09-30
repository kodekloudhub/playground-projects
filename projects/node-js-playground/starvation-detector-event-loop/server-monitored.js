// server-monitored.js
const http = require('http');
const { hashSync } = require('./slow-hash');
const { startLoopMonitor } = require('./loop-monitor');

const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('OK\n');
    return;
  }

  if (req.url === '/hash') {
    const hash = hashSync('hunter2'); // still blocking — we're only adding eyes, not fixing yet
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end(`hashed: ${hash.slice(0, 16)}...\n`);
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
  console.log('MONITORED (still blocking) server on http://localhost:3000');
  startLoopMonitor();
});

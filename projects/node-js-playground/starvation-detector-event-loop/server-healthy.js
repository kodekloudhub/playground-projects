// server-healthy.js
const http = require('http');

const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('OK\n');
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

server.listen(3000, () => console.log('healthy server on http://localhost:3000'));

// upgrade-detect.js
const http = require('http');

const server = http.createServer((req, res) => {
  res.writeHead(200);
  res.end('normal request, nothing to upgrade here');
});

// Node fires this event ONLY when it sees Upgrade: websocket headers — normal page requests never reach this function at all.
server.on('upgrade', (req, socket, head) => {
  console.log('--- upgrade request detected ---');
  console.log('headers:', req.headers);
  // We're not replying yet — just proving we can see the request.
});

server.listen(3000, () => console.log('listening on http://localhost:3000'));

// handshake.js
const http = require('http');
const crypto = require('crypto');

// This exact string is part of the official WebSocket rules — every WebSocket server in the world uses this same fixed string. It's not secret; it's just a fixed constant defined by the spec.
const MAGIC_STRING = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

// Glue the magic string onto the browser's key, scramble the result with SHA-1 (a one-way scrambling algorithm), then encode it as base64 text so it's safe to put in a header.
function computeAcceptValue(clientKey) {
  return crypto.createHash('sha1').update(clientKey + MAGIC_STRING).digest('base64');
}

const server = http.createServer((req, res) => {
  res.writeHead(200);
  res.end('normal request, nothing to upgrade here');
});

server.on('upgrade', (req, socket, head) => {
  const clientKey = req.headers['sec-websocket-key'];
  const acceptValue = computeAcceptValue(clientKey);

  // "101 Switching Protocols" is the official way to say: "Okay, I understood you — from now on, treat this connection as a WebSocket, not a normal web request."
  socket.write(
    'HTTP/1.1 101 Switching Protocols\r\n' +
    'Upgrade: websocket\r\n' +
    'Connection: Upgrade\r\n' +
    `Sec-WebSocket-Accept: ${acceptValue}\r\n\r\n`
  );

  console.log('handshake complete — connection is now a WebSocket');
});

server.listen(3000, () => console.log('listening on http://localhost:3000'));

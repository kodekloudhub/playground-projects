// chat-server.js
const http = require('http');
const crypto = require('crypto');

const MAGIC_STRING = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';
function computeAcceptValue(key) {
  return crypto.createHash('sha1').update(key + MAGIC_STRING).digest('base64');
}

function encodeTextFrame(text) {
  const textBytes = Buffer.from(text, 'utf8');
  return Buffer.concat([Buffer.from([0x81, textBytes.length]), textBytes]);
}

function unmask(payload, maskKey) {
  const result = Buffer.alloc(payload.length);
  for (let i = 0; i < payload.length; i++) {
    result[i] = payload[i] ^ maskKey[i % 4];
  }
  return result;
}

// Every currently connected chat client lives in here.
const clients = new Set();

const server = http.createServer((req, res) => {
  res.writeHead(200);
  res.end('this server only speaks WebSocket — connect with new WebSocket(...)');
});

server.on('upgrade', (req, socket) => {
  const acceptValue = computeAcceptValue(req.headers['sec-websocket-key']);
  socket.write(
    'HTTP/1.1 101 Switching Protocols\r\n' +
    'Upgrade: websocket\r\nConnection: Upgrade\r\n' +
    `Sec-WebSocket-Accept: ${acceptValue}\r\n\r\n`
  );

  clients.add(socket);
  console.log(`client connected — ${clients.size} total`);

  let pending = Buffer.alloc(0);

  socket.on('data', (chunk) => {
    pending = Buffer.concat([pending, chunk]);

    while (pending.length >= 2) {
      const opcode = pending[0] & 0b00001111;
      const lengthField = pending[1] & 0b01111111;
      if (lengthField > 125) {
        // This simplified server only handles short messages (see the
        // Task 4 bonus for how real WebSocket servers handle longer
        // ones). Log why, then drop this frame so `pending` doesn't
        // get stuck holding data we can't parse.
        console.error('message too long for this simplified server, dropping it');
        pending = Buffer.alloc(0);
        break;
      }

      const payloadStart = 6; // 2 header bytes + 4-byte mask key
      const frameLength = payloadStart + lengthField;
      if (pending.length < frameLength) break;

      const maskKey = pending.slice(2, 6);
      const scrambledPayload = pending.slice(6, frameLength);
      const text = unmask(scrambledPayload, maskKey).toString('utf8');

      if (opcode === 0x8) { // close
        socket.write(Buffer.from([0x88, 0x00]));
        socket.end();
      } else if (opcode === 0x9) { // ping
        socket.write(Buffer.from([0x8A, 0x00]));
      } else if (opcode === 0x1) { // text
        console.log('broadcasting:', text);
        for (const client of clients) {
          client.write(encodeTextFrame(text));
        }
      }

      pending = pending.slice(frameLength);
    }
  });

  socket.on('close', () => {
    clients.delete(socket);
    console.log(`client disconnected — ${clients.size} remaining`);
  });
});

server.listen(3000, () => console.log('chat server on ws://localhost:3000'));

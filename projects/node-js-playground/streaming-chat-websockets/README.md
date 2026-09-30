# Streaming Chat Over WebSockets (No Framework)

**Level:** beginner  ·  **Playground:** Node JS Playground

▶ **[Launch the playground](https://kodekloud.com/playgrounds/playground-nodejs)** — open it, then copy the files below.

A [`commands.sh`](./commands.sh) with the runnable steps is included.

![](https://t37266828.p.clickup-attachments.com/t37266828/b5d09481-9754-45a4-a4af-467abf8130b7/Marketing%20Youtube%20Labs%20Team%20-%20Architecture%20Diagram%20Maker%20\(2\).png)

```markdown
---
# ─── Metadata (read by the playground for listing & filtering) ───
id: streaming-chat-websockets
title: "Streaming Chat Over WebSockets (No Framework)"
playground: Node.js
playground_link: https://kodekloud.com/playgrounds/playground-nodejs
difficulty: beginner
estimated_minutes: 80
tags:
  - nodejs
  - javascript
  - websockets
  - networking
  - http
  - binary
skills:
  - http upgrade
  - websocket handshake
  - binary framing
  - frame buffering
  - broadcasting
prerequisites:
  - Basic JavaScript syntax (functions, variables)
  - No prior networking or WebSocket experience required
---

# Streaming Chat Over WebSockets (No Framework)

## Scenario
Your team wants a chat feature, but before adding a ready-made WebSocket library, your lead wants everyone to actually understand what a WebSocket connection *is*. So you're going to build the simplest possible version yourself — no libraries — starting from a completely normal Node.js HTTP server, the same kind that could serve a webpage, and upgrading it into a WebSocket server by hand.

## What you'll build
A chat server that starts life as a completely ordinary Node `http` server, detects when a browser wants to upgrade to a WebSocket, performs the handshake by hand, reads and writes binary frames byte-by-byte, and broadcasts messages to every connected client.

## Learning objectives
By the end you will be able to:
- Explain what an "upgrade request" is, and how Node's `http` module lets you detect one.
- Compute a valid WebSocket handshake response by hand.
- Read a binary frame's header, including messages long enough to need extended length bytes.
- Explain why you can't assume one `data` event equals one full message, and handle that safely.
- Build outgoing frames correctly (and know why server frames are never masked).
- Recognize different message types (text, close, ping) and keep track of multiple connected clients to broadcast a message to all of them.

## Prerequisites
- Playground: **Node.js** (open it before starting)
- Node.js available in the sandbox (`node -v` to confirm)

## How to test your server in this playground

This playground's own code editor already uses port 8080 internally — that's why every task in this project uses **port 3000** instead, and why you can't just visit `http://localhost:3000` directly: your browser and the server are on different machines, so the playground needs to forward the port for you.

Every time a task asks you to check something in the browser, follow these steps:

1. Run your server file: `node <file>.js`
2. In the editor, find the **View Port** option (usually a small port/globe icon near the top-right of the editor, or under a **Ports** tab)
3. Enter **3000** as the port number, then click **Open Port**
4. A **new browser tab** opens at a forwarded URL — this tab is your actual server, live
5. Open DevTools (F12) **on that new tab** (not on the editor tab) to run any browser console code the task asks for

**One important detail:** the forwarded URL won't be `localhost` — it'll be some long generated address. Whenever a task says to run `new WebSocket('ws://localhost:3000')`, use this instead, typed into that forwarded tab's console:
```javascript
new WebSocket(window.location.origin.replace(/^http/, 'ws'))
```

This automatically builds the correct address no matter what the forwarded URL looks like — it just takes the current tab's own address and swaps `http`/`https` for `ws`/`wss`.

## Steps

### Task 1 — Start with a plain, ordinary HTTP server

**What's happening here:** Before any WebSocket logic exists, let's confirm we have a plain, ordinary web server — the same kind you'd use for any website — using Node's built-in `http` module. Nothing WebSocket-related yet.

Create a file `http-server.js` and add the following:

```javascript
// http-server.js
const http = require('http');

// This is a completely normal web server — it could serve any website.
const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/plain' });
  res.end('just a normal web page, nothing WebSocket about this yet');
});

server.listen(3000, () => console.log('listening on http://localhost:3000'));
```

Run it:

```bash
node http-server.js
```

Then open **View Port**, enter `3000`, click **Open Port** — the new tab that opens shows the plain text response (see "How to test your server in this playground" above if you haven't set this up yet).

**What you should see:** A totally ordinary web page. This confirms the starting point: everything we build next is layered on top of this same kind of server, not something separate from it.

### Task 2 — Detect when a browser wants to upgrade the connection

**What's happening here:** A browser opening `new WebSocket(...)` sends a normal HTTP request, just with two extra headers: `Upgrade: websocket` and `Connection: Upgrade`. Node's `http` server watches for these and fires a separate `'upgrade'` event instead of treating it as a normal page request — handing you the raw connection to take over.

Create a file `upgrade-detect.js`: and add the following:

```javascript
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
```

Run it:

```bash
node upgrade-detect.js
```

Then open **View Port**, enter `3000`, click **Open Port**. In the new forwarded tab, open DevTools (F12) and run:

```javascript
new WebSocket(window.location.origin.replace(/^http/, 'ws'));
```

**What you should see:** Your terminal prints "upgrade request detected" along with a headers object that includes something like `'sec-websocket-key': '...'` and `'upgrade': 'websocket'`. Notice you didn't have to parse any raw text yourself — Node already turned the headers into a normal JavaScript object for you.

### Task 3 — Do the handshake by hand

**What's happening here:** The browser included a random made-up key in its request (`sec-websocket-key`) as part of the handshake — a short "are we speaking the same language?" exchange that happens once, at the start. To prove your server understands WebSockets, you combine that key with one fixed rule from the spec and send back the result — just some string-joining and a hash.

Create a file `handshake.js` and add the following:

```javascript
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
```

Run it:

```bash
node handshake.js
```

Open **View Port**, enter `3000`, click **Open Port**. In the forwarded tab's DevTools console, connect the same way as Task 2, then check DevTools' Network tab — the connection should now show status `101`.

**What you should see:** The moment your server sends that `101` reply, the browser considers the WebSocket officially "open." From here on, neither side sends normal HTTP on this connection — everything is small binary messages, which is what the next tasks are about.

### Task 4 — Read a frame's header

**What's happening here:** Every message starts with header bytes describing its length, before the actual text. If your friend typed "hey" then, two seconds later, "how are you", your computer doesn't see two separate messages — it just sees `heyhowareyou`, run together. That's what the length number is for: the sender says "the next message is 3 characters," sends `hey`, and your computer knows exactly where to stop.

A quick word on the numbers you'll see: a **Buffer** is a list of numbers 0–255, read like an array (`buffer[0]`, `buffer[1]`, ...). `0x81` and `0b10000000` are just numbers written in hex and binary — binary is 8 digits because that's exactly one byte, making it easy to check one bit at a time.

Create a file `frame-parser.js` and add the following:

```javascript
// frame-parser.js
function readFrameHeader(buffer) {
  const firstByte = buffer[0];
  const secondByte = buffer[1];

  // Leftmost bit: is this the whole message, or is more coming?
  const isFinalPiece = (firstByte & 0b10000000) !== 0;

  // Last 4 bits: what type of message is this (text, ping, close, etc.)?
  const messageType = firstByte & 0b00001111;

  // Leftmost bit of the second byte: did the sender scramble this?
  const isScrambled = (secondByte & 0b10000000) !== 0;

  // Last 7 bits: the length of the message, in bytes.
  const messageLength = secondByte & 0b01111111;

  return { isFinalPiece, messageType, isScrambled, messageLength };
}

// Example message: FIN=1, text, masked, length=5
const example = Buffer.from([0x81, 0x85, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
console.log(readFrameHeader(example));
```

Run it:

```bash
node frame-parser.js
```

**What you should see:** `messageLength: 5`, read directly from the second byte, along with `isFinalPiece: true`, `messageType: 1`, and `isScrambled: true`.

> 🎯 **Bonus (optional):** the code above assumes messages are 125 bytes or shorter. Real WebSocket messages can be longer — the length byte then reads `126` or `127` instead, meaning "the real length is actually stored in the next 2 or 8 bytes." Try extending `readFrameHeader` to handle that case if you want to go further, but it's not required to continue.

### Task 5 — Don't assume one delivery is one full message

**What's happening here:** TCP doesn't care about your message boundaries — it might deliver a big message across several small chunks, or bundle two small messages into one. Don't try to read anything until you're sure the whole "letter" has arrived: keep a growing pile of bytes in a tray, and each time a new piece shows up, check "do I have the full thing yet?" If not, keep waiting. If yes, read it all at once and clear the tray.

Create a file `frame-buffer.js` and add the following:

```javascript
// frame-buffer.js

// This pile of bytes grows every time more data arrives.
let pending = Buffer.alloc(0);

function handleIncomingData(chunk, onCompleteFrame) {
  // Glue the new chunk onto whatever we were already holding.
  pending = Buffer.concat([pending, chunk]);

  // Keep trying to pull frames out for as long as we have enough bytes.
  while (pending.length >= 2) {
    const lengthField = pending[1] & 0b01111111;
    const payloadStart = 6; // 2 header bytes + 4-byte mask key
    const frameLength = payloadStart + lengthField;

    // Not enough bytes yet for a full frame — stop and wait for more data.
    if (pending.length < frameLength) break;

    const completeFrame = pending.slice(0, frameLength);
    onCompleteFrame(completeFrame);

    // Keep whatever bytes are left over for the next chunk.
    pending = pending.slice(frameLength);
  }
}

// Demo: feed data in awkward little pieces, and still get one clean frame out.
function logCompleteFrame(frame) {
  console.log('got a complete frame, length:', frame.length);
}

const wholeFrame = Buffer.from([0x81, 0x85, 0, 0, 0, 0, 72, 101, 108, 108, 111]);
handleIncomingData(wholeFrame.slice(0, 4), logCompleteFrame);  // first few bytes only
handleIncomingData(wholeFrame.slice(4, 8), logCompleteFrame);  // a few more
handleIncomingData(wholeFrame.slice(8), logCompleteFrame);     // the rest
```

Run it:

```bash
node frame-buffer.js
```

**What you should see:** Even though the frame was fed in 3 separate, awkward little pieces, "got a complete frame" only prints once — after the third piece arrives, when there's finally enough data for one whole frame.

### Task 6 — Build outgoing frames (simpler than reading them)

**What's happening here:** Sending a message back uses the same frame format from Task 4, but easier — the server is never required to scramble ("mask") outgoing messages, only the browser has to do that. So building a reply is just: attach the length, then the plain text, no unscrambling needed.

`Buffer.from(text, 'utf8')` takes a plain string and converts each character into its byte number, using the standard UTF-8 rule (`h` is always `104`, `e` is always `101`, and so on). Once it's bytes, it's just numbers like any other data — that's why `Buffer.concat([header, textBytes])` can glue your 2 header bytes directly onto the front of it, no special handling needed. This is the same conversion running in reverse from Task 7's `.toString('utf8')`, which turns bytes back into text — UTF-8 is just the shared rule both directions use.

Create a file `encode-frame.js` and add the following:

```javascript
// encode-frame.js

// Builds a single, unmasked text frame ready to send to a browser.
function encodeTextFrame(text) {
  const textBytes = Buffer.from(text, 'utf8');

  // 0x81 = FIN bit on + opcode 1 (text). No mask bit, since server frames are never masked.
  const header = Buffer.from([0x81, textBytes.length]);

  return Buffer.concat([header, textBytes]);
}

const frame = encodeTextFrame('hello from the server');
console.log(frame);
```

Run it:

```bash
node encode-frame.js
```

**What you should see:** Something like `<Buffer 81 15 68 65 6c 6c 6f 20 66 72 6f 6d 20 74 68 65 20 73 65 72 76 65 72>` — this is Node printing the raw bytes in hex, not text, because a Buffer is just numbers; it has no idea some of them spell out a message. The first 2 numbers are the header (`81` = FIN+text opcode, `15` = 21 in hex, matching the message's length), followed by the actual text bytes — `68` is `h`, `65` is `e`, and so on. This is exactly what gets written to the socket when your server replies to a chat message.

### Task 7 — Wire it all together into a real chat room

**What's happening here:** Time to combine every previous task into one working server: perform the handshake, read incoming frames safely (using the buffering approach from Task 5), and — new in this task — keep a `Set` of every connected client so a message from one person gets broadcast to everyone else.

A quick note on the numbers you'll see checked in this code: the first byte's last 4 bits tell you the message _type_ (called the opcode) — `0x1` means a normal text message, `0x8` means the browser is saying goodbye (close), `0x9` means a "still there?" check (ping). Different types need different handling, which is exactly what the `if`/`else if` chain below does. This server also only handles short messages (125 bytes or fewer, same as Task 4) — if you send a longer message, it logs an error and drops it instead of getting stuck.

Create a file `chat-server.js` and add the following:

```javascript
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
```

**Testing this — quick flow:**

1. **Terminal:** `node chat-server.js` → leave it running
2. Open **View Port**, enter `3000`, click **Open Port** — this opens **Tab 1** at the forwarded URL. Open DevTools there and run:

```javascript
const ws = new WebSocket(window.location.origin.replace(/^http/, 'ws'));
ws.onmessage = (e) => console.log('received:', e.data);
ws.onopen = () => ws.send('hi from tab 1');
```

1. Open **View Port** again, enter `3000`, click **Open Port** once more — this opens a **second, separate tab (Tab 2)** at the same forwarded URL. Open DevTools there and run:

```javascript
const ws2 = new WebSocket(window.location.origin.replace(/^http/, 'ws'));
ws2.onmessage = (e) => console.log('received:', e.data);
ws2.onopen = () => ws2.send('hi from tab 2');
```

1. **Check:** terminal logs `client connected` twice and `broadcasting: ...` for each message.
2. **Confirm broadcast:** in Tab 1, run `ws.send('test')` → it should appear in **both** tabs' consoles.
3. **Confirm the long-message error handling:** in Tab 1, send a message over 125 characters:

```javascript
ws.send('This is a really long chat message that just keeps going and going, way past what this simple beginner server was built to handle, because it is definitely longer than one hundred and twenty five characters in total.');
```

Check your **terminal** — instead of broadcasting it, you should see:

```cpp
message too long for this simplified server, dropping it
```

Notice nothing shows up in either tab's `onmessage` — the message is silently dropped, and only your terminal (the developer side) knows why.
7\. **Confirm disconnect:** close Tab 2 → terminal logs `client disconnected`.

**What you should see:** A message sent from one tab shows up in the `onmessage` log of every other connected tab, including its own — this is a real, working, multi-client chat room, built entirely without a WebSocket library.

## Validation
Run through each check and confirm the actual behavior, not just that the script ran without errors:

- [ ] Task 1: opening port `3000` via View Port shows the plain text response in the new tab.
- [ ] Task 2: opening a WebSocket from the browser console causes your server to log the `'upgrade'` event and print real request headers.
- [ ] Task 3: the browser's DevTools Network tab shows your connection as status `101`.
- [ ] Task 4: `frame-parser.js` correctly reports `messageLength: 5`, `isFinalPiece: true`, `messageType: 1`, and `isScrambled: true` for the example message.
- [ ] Task 5: `frame-buffer.js` logs "got a complete frame" exactly once, even though the data arrived in 3 separate pieces.
- [ ] Task 6: `encode-frame.js` prints a Buffer whose second number matches the length of your text.
- [ ] Task 7: a message sent from one browser tab appears in every other connected tab's console.
- [ ] Task 7 (bonus): sending a message over 125 characters logs "message too long for this simplified server, dropping it" in the terminal instead of broadcasting.

## References & further learning
*   MDN: Writing WebSocket servers: [https://developer.mozilla.org/en-US/docs/Web/API/WebSockets\_API/Writing\_WebSocket\_servers](https://developer.mozilla.org/en-US/docs/Web/API/WebSockets_API/Writing_WebSocket_servers)
*   MDN: WebSocket API (the browser side): [https://developer.mozilla.org/en-US/docs/Web/API/WebSocket](https://developer.mozilla.org/en-US/docs/Web/API/WebSocket)
*   Node.js docs: `http` module, `'upgrade'` event: [https://nodejs.org/api/http.html#event-upgrade](https://nodejs.org/api/http.html#event-upgrade)
*   Node.js docs: `crypto` module: [https://nodejs.org/api/crypto.html](https://nodejs.org/api/crypto.html)
*   Node.js docs: `Buffer`: [https://nodejs.org/api/buffer.html](https://nodejs.org/api/buffer.html)

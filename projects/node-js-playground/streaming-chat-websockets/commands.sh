#!/usr/bin/env bash
set -euo pipefail

This automatically builds the correct address no matter what the forwarded URL looks like — it just takes the current tab's own address and swaps `http`/`https` for `ws`/`wss`.

## Steps

### Task 1 — Start with a plain, ordinary HTTP server

**What's happening here:** Before any WebSocket logic exists, let's confirm we have a plain, ordinary web server — the same kind you'd use for any website — using Node's built-in `http` module. Nothing WebSocket-related yet.

Create a file `http-server.js` and add the following:

Run it:

Then open **View Port**, enter `3000`, click **Open Port** — the new tab that opens shows the plain text response (see "How to test your server in this playground" above if you haven't set this up yet).

**What you should see:** A totally ordinary web page. This confirms the starting point: everything we build next is layered on top of this same kind of server, not something separate from it.

### Task 2 — Detect when a browser wants to upgrade the connection

**What's happening here:** A browser opening `new WebSocket(...)` sends a normal HTTP request, just with two extra headers: `Upgrade: websocket` and `Connection: Upgrade`. Node's `http` server watches for these and fires a separate `'upgrade'` event instead of treating it as a normal page request — handing you the raw connection to take over.

Create a file `upgrade-detect.js`: and add the following:

Run it:

Then open **View Port**, enter `3000`, click **Open Port**. In the new forwarded tab, open DevTools (F12) and run:

**What you should see:** Your terminal prints "upgrade request detected" along with a headers object that includes something like `'sec-websocket-key': '...'` and `'upgrade': 'websocket'`. Notice you didn't have to parse any raw text yourself — Node already turned the headers into a normal JavaScript object for you.

### Task 3 — Do the handshake by hand

**What's happening here:** The browser included a random made-up key in its request (`sec-websocket-key`) as part of the handshake — a short "are we speaking the same language?" exchange that happens once, at the start. To prove your server understands WebSockets, you combine that key with one fixed rule from the spec and send back the result — just some string-joining and a hash.

Create a file `handshake.js` and add the following:

Run it:

Open **View Port**, enter `3000`, click **Open Port**. In the forwarded tab's DevTools console, connect the same way as Task 2, then check DevTools' Network tab — the connection should now show status `101`.

**What you should see:** The moment your server sends that `101` reply, the browser considers the WebSocket officially "open." From here on, neither side sends normal HTTP on this connection — everything is small binary messages, which is what the next tasks are about.

### Task 4 — Read a frame's header

**What's happening here:** Every message starts with header bytes describing its length, before the actual text. If your friend typed "hey" then, two seconds later, "how are you", your computer doesn't see two separate messages — it just sees `heyhowareyou`, run together. That's what the length number is for: the sender says "the next message is 3 characters," sends `hey`, and your computer knows exactly where to stop.

A quick word on the numbers you'll see: a **Buffer** is a list of numbers 0–255, read like an array (`buffer[0]`, `buffer[1]`, ...). `0x81` and `0b10000000` are just numbers written in hex and binary — binary is 8 digits because that's exactly one byte, making it easy to check one bit at a time.

Create a file `frame-parser.js` and add the following:

Run it:

**What you should see:** `messageLength: 5`, read directly from the second byte, along with `isFinalPiece: true`, `messageType: 1`, and `isScrambled: true`.

> 🎯 **Bonus (optional):** the code above assumes messages are 125 bytes or shorter. Real WebSocket messages can be longer — the length byte then reads `126` or `127` instead, meaning "the real length is actually stored in the next 2 or 8 bytes." Try extending `readFrameHeader` to handle that case if you want to go further, but it's not required to continue.

### Task 5 — Don't assume one delivery is one full message

**What's happening here:** TCP doesn't care about your message boundaries — it might deliver a big message across several small chunks, or bundle two small messages into one. Don't try to read anything until you're sure the whole "letter" has arrived: keep a growing pile of bytes in a tray, and each time a new piece shows up, check "do I have the full thing yet?" If not, keep waiting. If yes, read it all at once and clear the tray.

Create a file `frame-buffer.js` and add the following:

Run it:

**What you should see:** Even though the frame was fed in 3 separate, awkward little pieces, "got a complete frame" only prints once — after the third piece arrives, when there's finally enough data for one whole frame.

### Task 6 — Build outgoing frames (simpler than reading them)

**What's happening here:** Sending a message back uses the same frame format from Task 4, but easier — the server is never required to scramble ("mask") outgoing messages, only the browser has to do that. So building a reply is just: attach the length, then the plain text, no unscrambling needed.

`Buffer.from(text, 'utf8')` takes a plain string and converts each character into its byte number, using the standard UTF-8 rule (`h` is always `104`, `e` is always `101`, and so on). Once it's bytes, it's just numbers like any other data — that's why `Buffer.concat([header, textBytes])` can glue your 2 header bytes directly onto the front of it, no special handling needed. This is the same conversion running in reverse from Task 7's `.toString('utf8')`, which turns bytes back into text — UTF-8 is just the shared rule both directions use.

Create a file `encode-frame.js` and add the following:

Run it:

**What you should see:** Something like `<Buffer 81 15 68 65 6c 6c 6f 20 66 72 6f 6d 20 74 68 65 20 73 65 72 76 65 72>` — this is Node printing the raw bytes in hex, not text, because a Buffer is just numbers; it has no idea some of them spell out a message. The first 2 numbers are the header (`81` = FIN+text opcode, `15` = 21 in hex, matching the message's length), followed by the actual text bytes — `68` is `h`, `65` is `e`, and so on. This is exactly what gets written to the socket when your server replies to a chat message.

### Task 7 — Wire it all together into a real chat room

**What's happening here:** Time to combine every previous task into one working server: perform the handshake, read incoming frames safely (using the buffering approach from Task 5), and — new in this task — keep a `Set` of every connected client so a message from one person gets broadcast to everyone else.

A quick note on the numbers you'll see checked in this code: the first byte's last 4 bits tell you the message _type_ (called the opcode) — `0x1` means a normal text message, `0x8` means the browser is saying goodbye (close), `0x9` means a "still there?" check (ping). Different types need different handling, which is exactly what the `if`/`else if` chain below does. This server also only handles short messages (125 bytes or fewer, same as Task 4) — if you send a longer message, it logs an error and drops it instead of getting stuck.

Create a file `chat-server.js` and add the following:

**Testing this — quick flow:**

1. **Terminal:** `node chat-server.js` → leave it running
2. Open **View Port**, enter `3000`, click **Open Port** — this opens **Tab 1** at the forwarded URL. Open DevTools there and run:

1. Open **View Port** again, enter `3000`, click **Open Port** once more — this opens a **second, separate tab (Tab 2)** at the same forwarded URL. Open DevTools there and run:

1. **Check:** terminal logs `client connected` twice and `broadcasting: ...` for each message.
2. **Confirm broadcast:** in Tab 1, run `ws.send('test')` → it should appear in **both** tabs' consoles.
3. **Confirm the long-message error handling:** in Tab 1, send a message over 125 characters:

Check your **terminal** — instead of broadcasting it, you should see:

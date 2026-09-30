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

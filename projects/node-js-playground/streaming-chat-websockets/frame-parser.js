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

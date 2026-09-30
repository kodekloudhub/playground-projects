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

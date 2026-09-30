// bmp-utils.js
// Minimal uncompressed 24-bit BMP reader/writer + nearest-neighbor resize. BMP is deliberately simple (no compression) so we can read and write real image files without needing a JPEG/PNG decoder.

function createBMP(width, height, pixelFn) {
  const rowSize = Math.floor((24 * width + 31) / 32) * 4; // rows padded to 4 bytes
  const pixelArraySize = rowSize * height;
  const fileSize = 54 + pixelArraySize;

  const buf = Buffer.alloc(fileSize);
  buf.write('BM', 0);
  buf.writeUInt32LE(fileSize, 2);
  buf.writeUInt32LE(54, 10); // pixel data offset
  buf.writeUInt32LE(40, 14); // DIB header size
  buf.writeInt32LE(width, 18);
  buf.writeInt32LE(height, 22); // positive = bottom-up
  buf.writeUInt16LE(1, 26); // planes
  buf.writeUInt16LE(24, 28); // bits per pixel
  buf.writeUInt32LE(0, 30); // no compression
  buf.writeUInt32LE(pixelArraySize, 34);

  for (let y = 0; y < height; y++) {
    const fileRow = height - 1 - y; // bottom-up storage
    const rowStart = 54 + fileRow * rowSize;
    for (let x = 0; x < width; x++) {
      const [r, g, b] = pixelFn(x, y);
      const off = rowStart + x * 3;
      buf[off] = b; buf[off + 1] = g; buf[off + 2] = r; // BGR order
    }
  }
  return buf;
}

function readBMP(buf) {
  const width = buf.readInt32LE(18);
  const height = buf.readInt32LE(22);
  const rowSize = Math.floor((24 * width + 31) / 32) * 4;
  function getPixel(x, y) {
    const fileRow = height - 1 - y;
    const off = 54 + fileRow * rowSize + x * 3;
    return [buf[off + 2], buf[off + 1], buf[off]]; // back to RGB
  }
  return { width, height, getPixel };
}

function resizeBMP(inputBuf, targetWidth, targetHeight) {
  const src = readBMP(inputBuf);
  return createBMP(targetWidth, targetHeight, (x, y) => {
    const srcX = Math.floor((x / targetWidth) * src.width);
    const srcY = Math.floor((y / targetHeight) * src.height);
    return src.getPixel(srcX, srcY);
  });
}

module.exports = { createBMP, readBMP, resizeBMP };

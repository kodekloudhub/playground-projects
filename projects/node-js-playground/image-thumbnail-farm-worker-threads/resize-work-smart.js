// resize-work-smart.js
const fs = require('fs');
const { resizeBMP } = require('./bmp-utils');

let sharp = null;
try {
  sharp = require('sharp');
} catch {
  // not installed -- pure-JS fallback below
}

async function resizeImageFileSmart(inputPath, outputPath, targetWidth, targetHeight) {
  if (sharp) {
    await sharp(inputPath).resize(targetWidth, targetHeight).toFile(outputPath);
    return { engine: 'sharp' };
  }
  const inputBuf = fs.readFileSync(inputPath);
  const outputBuf = resizeBMP(inputBuf, targetWidth, targetHeight);
  fs.writeFileSync(outputPath, outputBuf);
  return { engine: 'pure-js' };
}

module.exports = { resizeImageFileSmart };

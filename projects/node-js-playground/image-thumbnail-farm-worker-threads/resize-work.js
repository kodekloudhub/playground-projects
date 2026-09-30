// resize-work.js
const fs = require('fs');
const { resizeBMP } = require('./bmp-utils');

function resizeImageFile(inputPath, outputPath, targetWidth, targetHeight) {
  const inputBuf = fs.readFileSync(inputPath);
  const outputBuf = resizeBMP(inputBuf, targetWidth, targetHeight);
  fs.writeFileSync(outputPath, outputBuf);
  return { inputBytes: inputBuf.length, outputBytes: outputBuf.length };
}

module.exports = { resizeImageFile };

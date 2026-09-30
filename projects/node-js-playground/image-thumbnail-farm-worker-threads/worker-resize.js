// worker-resize.js
const { parentPort } = require('worker_threads');
const { resizeImageFile } = require('./resize-work');

parentPort.on('message', ({ inputPath, outputPath, targetWidth, targetHeight }) => {
  const result = resizeImageFile(inputPath, outputPath, targetWidth, targetHeight);
  parentPort.postMessage({ done: true, outputPath, ...result });
});

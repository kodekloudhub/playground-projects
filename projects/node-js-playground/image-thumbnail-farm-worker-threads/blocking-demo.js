// blocking-demo.js
const { resizeImageFile } = require('./resize-work');

setInterval(() => console.log('tick'), 200);

setTimeout(() => {
  console.log('--- resizing a REAL image on the MAIN thread ---');
  const start = Date.now();
  const result = resizeImageFile('samples/photo0.bmp', 'thumbs/photo0-blocking.bmp', 200, 150);
  console.log(`--- done in ${Date.now() - start}ms (${result.inputBytes} -> ${result.outputBytes} bytes) ---`);
}, 1000);

// nonblocking-demo.js
const { Worker } = require('worker_threads');

setInterval(() => console.log('tick'), 200);

setTimeout(() => {
  console.log('--- resizing the SAME real image, but in a worker ---');
  const start = Date.now();
  const worker = new Worker('./worker-resize.js');

  worker.postMessage({
    inputPath: 'samples/photo0.bmp',
    outputPath: 'thumbs/photo0-nonblocking.bmp',
    targetWidth: 200, targetHeight: 150,
  });

  worker.on('message', (msg) => {
    console.log(`--- done in ${Date.now() - start}ms -> wrote ${msg.outputPath} ---`);
    worker.terminate();
  });
}, 1000);

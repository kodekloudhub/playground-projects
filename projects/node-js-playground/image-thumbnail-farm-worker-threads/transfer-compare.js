// transfer-compare.js
const { Worker } = require('worker_threads');
const fs = require('fs');

const realImageBytes = fs.readFileSync('samples/photo0.bmp'); // a real multi-MB file

function timeCopy() {
  return new Promise((resolve) => {
    const worker = new Worker('./echo-worker.js');
    const start = Date.now();
    worker.postMessage({ data: realImageBytes }); // plain Buffer -> Node copies it all
    worker.on('message', () => {
      console.log(`[copy]   took ${Date.now() - start}ms`);
      worker.terminate();
      resolve();
    });
  });
}

function timeShared() {
  return new Promise((resolve) => {
    const worker = new Worker('./echo-worker.js');
    const start = Date.now();
    const sab = new SharedArrayBuffer(realImageBytes.length);
    new Uint8Array(sab).set(realImageBytes); // one-time copy INTO shared memory
    worker.postMessage({ sab });              // this line just hands over a reference
    worker.on('message', () => {
      console.log(`[shared] took ${Date.now() - start}ms`);
      worker.terminate();
      resolve();
    });
  });
}

(async () => {
  console.log(`comparing with a real ${(realImageBytes.length / 1024 / 1024).toFixed(1)}MB image file\n`);
  await timeCopy();
  await timeShared();
})();

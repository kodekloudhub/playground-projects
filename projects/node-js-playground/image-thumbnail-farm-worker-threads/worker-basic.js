// worker-basic.js
const { parentPort } = require('worker_threads');

parentPort.on('message', (msg) => {
  console.log('[worker] received:', msg);
  parentPort.postMessage(`hello back, I got: ${msg}`);
});

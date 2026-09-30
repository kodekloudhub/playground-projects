// main-basic.js
const { Worker } = require('worker_threads');

const worker = new Worker('./worker-basic.js');

worker.on('message', (msg) => {
  console.log('[main] got reply:', msg);
  worker.terminate();
});

console.log('[main] sending a message to the worker...');
worker.postMessage('ping');

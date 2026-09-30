// echo-worker.js
const { parentPort } = require('worker_threads');
parentPort.on('message', () => parentPort.postMessage('done'));

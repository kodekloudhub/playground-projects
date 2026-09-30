// observe-baseline.js
const fs = require('fs');

console.log('--- sync start ---');

setTimeout(() => console.log('fired: setTimeout'), 0);
setImmediate(() => console.log('fired: setImmediate'));
process.nextTick(() => console.log('fired: process.nextTick'));
Promise.resolve().then(() => console.log('fired: promise'));
fs.readFile('data.txt', () => console.log('fired: fs.readFile'));

console.log('--- sync end ---');

// timeout-vs-immediate.js
const fs = require('fs');

// Case 1: top-level — order is genuinely NOT guaranteed.
setTimeout(() => console.log('[top-level] setTimeout'), 0);
setImmediate(() => console.log('[top-level] setImmediate'));

// Case 2: scheduled inside a real I/O callback — setImmediate always wins.
fs.readFile('data.txt', () => {
  setTimeout(() => console.log('[inside I/O] setTimeout'), 0);
  setImmediate(() => console.log('[inside I/O] setImmediate'));
});

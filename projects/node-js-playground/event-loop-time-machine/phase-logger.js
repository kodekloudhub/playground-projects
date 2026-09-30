// phase-logger.js
const fs = require('fs');

function runAndCapture() {
  return new Promise((resolve) => {
    const fired = [];
    let remaining = 5;

    function mark(label) {
      fired.push(label);
      remaining--;
      if (remaining === 0) resolve(fired);
    }

    process.nextTick(() => mark('process.nextTick'));
    Promise.resolve().then(() => mark('promise'));
    setTimeout(() => mark('setTimeout'), 0);
    setImmediate(() => mark('setImmediate'));
    fs.readFile('data.txt', () => mark('fs.readFile'));
  });
}

module.exports = { runAndCapture };

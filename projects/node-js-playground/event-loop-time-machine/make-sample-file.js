// make-sample-file.js
const fs = require('fs');

fs.writeFileSync('data.txt', 'this file is read for real by fs.readFile, not simulated\n');
console.log('created data.txt');

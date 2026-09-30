// calibrate.js
const { performance } = require('perf_hooks');
const { hashSync, ITERATIONS } = require('./slow-hash');

hashSync('warm-up'); // the first call is a little slower; don't count it

const runs = 5;
const start = performance.now();
for (let i = 0; i < runs; i++) hashSync(`password-${i}`);
const perHash = (performance.now() - start) / runs;

console.log(`ITERATIONS = ${ITERATIONS}`);
console.log(`one hash takes ~${perHash.toFixed(0)}ms on this machine`);

if (perHash < 100) console.log('-> a bit fast: increase ITERATIONS in slow-hash.js and run again');
else if (perHash > 300) console.log('-> a bit slow: decrease ITERATIONS in slow-hash.js and run again');
else console.log('-> good: this is heavy enough to show the problem clearly');

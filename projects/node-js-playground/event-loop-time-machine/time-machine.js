// time-machine.js
const { runAndCapture } = require('./phase-logger');
const { askPrediction } = require('./predict');

const LABELS = ['process.nextTick', 'promise', 'setTimeout', 'setImmediate', 'fs.readFile'];

(async () => {
  const predicted = await askPrediction(LABELS);

  console.log('\nrunning...\n');
  const actual = await runAndCapture();

  console.log('predicted:', predicted);
  console.log('actual   :', actual);
})();

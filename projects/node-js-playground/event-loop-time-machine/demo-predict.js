// demo-predict.js
const { askPrediction } = require('./predict');

const LABELS = ['process.nextTick', 'promise', 'setTimeout', 'setImmediate', 'fs.readFile'];

askPrediction(LABELS).then((predicted) => {
  console.log('you predicted:', predicted);
});

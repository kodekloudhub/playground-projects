// demo-logger.js
const { runAndCapture } = require('./phase-logger');

runAndCapture().then((order) => {
  console.log('actual fired order:', order);
});

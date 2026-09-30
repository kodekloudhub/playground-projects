// shutdown-demo.js
const fs = require('fs');
const { ThumbnailPool } = require('./pool');

const pool = new ThumbnailPool('./worker-resize.js', 4);

const files = fs.readdirSync('samples').filter((f) => f.endsWith('.bmp'));
const jobs = files.map((f) => ({
  inputPath: `samples/${f}`,
  outputPath: `thumbs/shutdown-${f}`,
  targetWidth: 200, targetHeight: 150,
}));

jobs.forEach((j) => pool.submit(j).catch((err) => console.log('[job] rejected:', err.message)));
setTimeout(() => pool.shutdown(), 100); // shut down almost immediately, mid-flight

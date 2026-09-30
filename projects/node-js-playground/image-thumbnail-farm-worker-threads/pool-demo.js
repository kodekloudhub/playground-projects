// pool-demo.js
const fs = require('fs');
const { ThumbnailPool } = require('./pool');

const pool = new ThumbnailPool('./worker-resize.js', 4); // 4 workers on purpose

const files = fs.readdirSync('samples').filter((f) => f.endsWith('.bmp'));
const jobs = files.map((f) => ({
  inputPath: `samples/${f}`,
  outputPath: `thumbs/pool-${f}`,
  targetWidth: 200, targetHeight: 150,
}));

Promise.all(jobs.map((j) => pool.submit(j))).then(() => {
  console.log(`--- all ${jobs.length} real images resized ---`);
});

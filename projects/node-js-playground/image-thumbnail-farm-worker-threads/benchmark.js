// benchmark.js
const fs = require('fs');
const { ThumbnailPool } = require('./pool');

function makeJobs() {
  const files = fs.readdirSync('samples').filter((f) => f.endsWith('.bmp'));
  return files.map((f) => ({
    inputPath: `samples/${f}`,
    outputPath: `thumbs/bench-${f}`,
    targetWidth: 200, targetHeight: 150,
  }));
}

async function runBatch(poolSize) {
  const pool = new ThumbnailPool('./worker-resize.js', poolSize);
  const jobs = makeJobs();

  const start = Date.now();
  await Promise.all(jobs.map((j) => pool.submit(j)));
  const elapsed = Date.now() - start;

  await pool.shutdown();
  return elapsed;
}

(async () => {
  const oneWorker = await runBatch(1);
  const fourWorkers = await runBatch(4);

  console.log('\n--- Benchmark Results (8 real images) ---');
  console.log(`1 worker : ${oneWorker}ms`);
  console.log(`4 workers: ${fourWorkers}ms`);
  console.log(`Speedup  : ${(oneWorker / fourWorkers).toFixed(2)}x`);
})();

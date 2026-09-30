// loadtest.js
// Runs in its OWN process (a separate terminal), so its stopwatch keeps ticking honestly even when the server it is testing is frozen.
const http = require('http');
const { performance } = require('perf_hooks');

const PORT = 3000;
const DURATION_MS = 5000;     // how long the test runs
const HEALTH_EVERY_MS = 50;   // one /health "customer" every 50ms
const HAMMER_WORKERS = 8;     // how many clients keep hitting the slow route at once

// `node loadtest.js`               -> only /health (baseline)
// `node loadtest.js --hammer`      -> /health + hammer /hash
// `node loadtest.js --hammer /x`   -> /health + hammer the route /x
const hammerIndex = process.argv.indexOf('--hammer');
const hammerPath = hammerIndex === -1 ? null : (process.argv[hammerIndex + 1] || '/hash');

const agent = new http.Agent({ keepAlive: true, maxSockets: Infinity });

function timedGet(path) {
  return new Promise((resolve, reject) => {
    const start = performance.now();
    const req = http.get({ host: '127.0.0.1', port: PORT, path, agent }, (res) => {
      res.resume(); // we only care about timing, not the body
      res.on('end', () => {
        if (res.statusCode !== 200) return reject(new Error(`${path} answered ${res.statusCode}`));
        resolve(performance.now() - start);
      });
    });
    req.on('error', reject);
  });
}

function percentile(sortedValues, p) {
  if (sortedValues.length === 0) return 0;
  const index = Math.min(sortedValues.length - 1, Math.ceil((p / 100) * sortedValues.length) - 1);
  return sortedValues[Math.max(0, index)];
}

function fail(err) {
  if (err.code === 'ECONNREFUSED') {
    console.error(`\nNothing is listening on port ${PORT}. Start a server in your other terminal first.`);
  } else {
    console.error('\nload test failed:', err.message);
  }
  process.exit(1);
}

(async () => {
  console.log(`testing /health for ${DURATION_MS / 1000}s` +
    (hammerPath ? ` while ${HAMMER_WORKERS} clients hammer ${hammerPath}` : ' (no hammering)') + '...');

  const healthLatencies = [];
  const pendingHealth = [];
  let hammerDone = 0;
  let running = true;

  const healthTimer = setInterval(() => {
    pendingHealth.push(timedGet('/health').then((ms) => healthLatencies.push(ms)).catch(fail));
  }, HEALTH_EVERY_MS);

  const hammerLoops = [];
  if (hammerPath) {
    for (let i = 0; i < HAMMER_WORKERS; i++) {
      hammerLoops.push((async () => {
        while (running) {
          await timedGet(hammerPath).catch(fail);
          hammerDone++;
        }
      })());
    }
  }

  await new Promise((r) => setTimeout(r, DURATION_MS));
  running = false;
  clearInterval(healthTimer);
  await Promise.all([...pendingHealth, ...hammerLoops]);

  const sorted = [...healthLatencies].sort((a, b) => a - b);
  const seconds = DURATION_MS / 1000;

  console.log('\n--- /health latency ---');
  console.log(`requests : ${sorted.length}`);
  console.log(`p50      : ${percentile(sorted, 50).toFixed(1)}ms`);
  console.log(`p99      : ${percentile(sorted, 99).toFixed(1)}ms`);
  console.log(`max      : ${sorted[sorted.length - 1].toFixed(1)}ms`);
  if (hammerPath) {
    console.log(`\n--- ${hammerPath} throughput ---`);
    console.log(`completed: ${hammerDone} in ${seconds}s (~${(hammerDone / seconds).toFixed(1)} req/s)`);
  }
  agent.destroy();
})();

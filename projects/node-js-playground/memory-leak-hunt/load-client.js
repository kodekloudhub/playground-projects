// load-client.js
const http = require('http');

const [, , mode, countArg] = process.argv;
const count = parseInt(countArg, 10) || 100;
const runId = Date.now(); // guarantees "unique" ids stay unique across runs

function get(path) {
  return new Promise((resolve, reject) => {
    http.get(`http://localhost:3000${path}`, (res) => {
      let body = '';
      res.on('data', (chunk) => (body += chunk));
      res.on('end', () => resolve(JSON.parse(body)));
    }).on('error', reject);
  });
}

async function run() {
  for (let i = 0; i < count; i++) {
    if (mode === 'compute-unique') {
      await get(`/compute?id=user-${runId}-${i}`); // a brand-new key every time
    } else if (mode === 'compute-same') {
      await get('/compute?id=user-fixed'); // the exact same key every time
    } else if (mode === 'subscribe') {
      await get('/subscribe');
    } else {
      console.error('unknown mode. use: compute-unique | compute-same | subscribe');
      process.exit(1);
    }
  }
  console.log(`sent ${count} requests in mode "${mode}"`);
}

run();

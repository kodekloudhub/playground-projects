// memory-trend.js
const http = require('http');

function getStats() {
  return new Promise((resolve, reject) => {
    http.get('http://localhost:3000/stats', (res) => {
      let body = '';
      res.on('data', (chunk) => (body += chunk));
      res.on('end', () => resolve(JSON.parse(body)));
    }).on('error', reject);
  });
}

async function run() {
  console.log('sampling /stats every second — drive traffic from another terminal now');
  for (let i = 0; i < 30; i++) {
    const stats = await getStats();
    const bar = '#'.repeat(Math.round(stats.heapUsedMB));
    console.log(`t+${i}s  heapUsed=${stats.heapUsedMB}MB  cache=${stats.cacheSize}  listeners=${stats.listenerCount}  ${bar}`);
    await new Promise((resolve) => setTimeout(resolve, 1000));
  }
}

run();

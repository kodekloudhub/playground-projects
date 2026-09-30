// leaky-server.js
const http = require('http');
const v8 = require('v8');
const fs = require('fs');
const EventEmitter = require('events');

fs.mkdirSync('snapshots', { recursive: true });

// ─── Leak #1 ingredient: a cache with no eviction ───
const cache = new Map();

function expensiveCompute(id) {
  // A real, somewhat heavy payload (50KB) so growth is visible in a snapshot instead of getting lost in the noise of tiny objects.
  return { id, data: Buffer.alloc(50 * 1024, id.length % 256) };
}

// ─── Leak #2 ingredient: a long-lived emitter shared by every request ───
const sharedEmitter = new EventEmitter();

function forceGC(label) {
  if (global.gc) {
    global.gc();
  } else {
    console.warn(`[${label}] run with --expose-gc for accurate measurements (node --expose-gc leaky-server.js)`);
  }
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');

  if (url.pathname === '/compute') {
    const id = url.searchParams.get('id') || 'default';
    // THE BUG: nothing is ever deleted from `cache`, no matter how many distinct ids arrive. Every unique id becomes a permanent entry.
    if (!cache.has(id)) {
      cache.set(id, expensiveCompute(id));
    }
    const result = cache.get(id);
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ id: result.id, cacheSize: cache.size }));
    return;
  }

  if (url.pathname === '/subscribe') {
    // THE BUG: a brand-new listener is created and attached on every single request, and it is never removed — not on response finish, not ever.
    const onTick = () => {
      // pretend this request cares about future "tick" events
    };
    sharedEmitter.on('tick', onTick);
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ listenerCount: sharedEmitter.listenerCount('tick') }));
    return;
  }

  if (url.pathname === '/stats') {
    forceGC('stats');
    const mem = process.memoryUsage();
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      cacheSize: cache.size,
      listenerCount: sharedEmitter.listenerCount('tick'),
      heapUsedMB: +(mem.heapUsed / 1024 / 1024).toFixed(2),
      rssMB: +(mem.rss / 1024 / 1024).toFixed(2),
    }));
    return;
  }

  if (url.pathname === '/snapshot') {
    const name = url.searchParams.get('name') || `snap-${Date.now()}`;
    forceGC('snapshot');
    const filePath = `snapshots/${name}.heapsnapshot`;
    v8.writeHeapSnapshot(filePath);
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ wrote: filePath }));
    return;
  }

  res.writeHead(404);
  res.end('not found');
});

server.listen(3000, () => console.log(`leaky server on http://localhost:3000 (pid ${process.pid})`));

// fixed-server.js
const http = require('http');
const v8 = require('v8');
const fs = require('fs');
const EventEmitter = require('events');

fs.mkdirSync('snapshots', { recursive: true });

// ─── Fix #1: a cache with a hard size limit and simple LRU eviction ───
const MAX_CACHE_ENTRIES = 50;
const cache = new Map();

function rememberInCache(id, value) {
  if (cache.has(id)) {
    cache.delete(id); // re-insert so it counts as most-recently-used
  } else if (cache.size >= MAX_CACHE_ENTRIES) {
    const oldestKey = cache.keys().next().value; // Map keeps insertion order
    cache.delete(oldestKey);
  }
  cache.set(id, value);
}

function expensiveCompute(id) {
  return { id, data: Buffer.alloc(50 * 1024, id.length % 256) };
}

// ─── Fix #2: remove each request's listener once that request is done ───
const sharedEmitter = new EventEmitter();

function forceGC(label) {
  if (global.gc) {
    global.gc();
  } else {
    console.warn(`[${label}] run with --expose-gc for accurate measurements`);
  }
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');

  if (url.pathname === '/compute') {
    const id = url.searchParams.get('id') || 'default';
    if (!cache.has(id)) {
      rememberInCache(id, expensiveCompute(id));
    } else {
      rememberInCache(id, cache.get(id)); // refresh recency, no growth
    }
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ id, cacheSize: cache.size }));
    return;
  }

  if (url.pathname === '/subscribe') {
    const onTick = () => {
      // pretend this request cares about future "tick" events
    };
    sharedEmitter.on('tick', onTick);

    // THE FIX: the moment this response is done, this request no longer needs to hear about future ticks — so stop listening.
    res.on('finish', () => {
      sharedEmitter.off('tick', onTick);
    });

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

server.listen(3000, () => console.log(`fixed server on http://localhost:3000 (pid ${process.pid})`));

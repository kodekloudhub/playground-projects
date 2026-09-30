# Memory Leak Hunt

**Level:** intermediate  ·  **Playground:** Node JS Playground

▶ **[Launch the playground](https://kodekloud.com/playgrounds/playground-nodejs)** — open it, then copy the files below.

A [`commands.sh`](./commands.sh) with the runnable steps is included.

![](https://t37266828.p.clickup-attachments.com/t37266828/b029fef9-204c-4b07-b645-62ad29615f73/Marketing%20Youtube%20Labs%20Team%20-%20Architecture%20Diagram%20Maker%20\(3\).png)
# Memory Leak Hunt (Heap Snapshots & GC)

```markdown
---
# ─── Metadata (read by the playground for listing & filtering) ───
id: memory-leak-hunt
title: "Memory Leak Hunt"
playground: Node.js
playground_link: https://kodekloud.com/playgrounds/playground-nodejs
difficulty: intermediate
estimated_minutes: 100
tags:
  - nodejs
  - javascript
  - memory
  - v8
  - heap
  - garbage-collection
  - debugging
skills:
  - heap snapshots
  - --inspect / DevTools memory profiling
  - forcing garbage collection
  - retainer paths
  - unbounded cache leaks
  - stray event listener leaks
  - bounded (LRU) caching
prerequisites:
  - Basic JavaScript syntax (functions, closures, Map)
  - Comfortable with Node's `http` module and `EventEmitter`
  - No prior V8 internals or heap-profiling experience required
---

# Memory Leak Hunt (Heap Snapshots & GC)

## Scenario
A service your team owns has been quietly restarting in production every couple of days — no crash logs, no errors, just `Out of memory` in the process manager. Nobody touched the code recently. Your lead's theory: something in the server is holding onto objects it doesn't need anymore. Your job is to find it — not by staring at the code and guessing, but by actually taking heap snapshots, diffing them, and following the evidence to the exact lines responsible. The server you're handed has **two separate, independent leaks** hiding in it, and a corrected version exists — you'll only look at it after you've found both yourself.

## What you'll build
You'll start with a small HTTP server that looks completely reasonable — it caches expensive results and lets requests subscribe to a shared event — but leaks memory in two unrelated ways: an unbounded cache and a stray event listener. You'll prove each leak exists with real numbers from `process.memoryUsage()`, then move to the real diagnostic tool of the trade: V8 heap snapshots, taken before and after controlled traffic, diffed to find exactly what's growing and why. You'll do this first from files (`v8.writeHeapSnapshot`) and then live, through `--inspect` and Chrome DevTools' Memory panel. Finally, you'll reveal the fixed version of the server, apply the same tests to it, and confirm — with numbers, not vibes — that both leaks are gone.

## Learning objectives
By the end you will be able to:
- Explain what a memory leak actually means in a garbage-collected language: not a broken cleanup process, but something still being reachable that shouldn't be.
- Force a garbage collection cycle on demand and explain why that matters before taking a measurement.
- Diagnose an unbounded-cache leak using repeatable, quantifiable memory measurements.
- Diagnose a stray-event-listener leak, including recognizing Node's own `MaxListenersExceededWarning`.
- Take a V8 heap snapshot (both to a file and live via DevTools) and force GC immediately beforehand.
- Diff two heap snapshots and read a **retainer path** to identify exactly what's holding a leaking object alive.
- Fix both leak patterns (bounded/evicting cache, listener cleanup) and prove the fix with the same methodology used to find the bug.

## Prerequisites
- Playground: **Node.js** (open it before starting)
- Node.js available in the sandbox (`node -v` to confirm)

## How you'll interact with this server in this playground
This project is an API, not a web page, so instead of opening a browser tab you'll drive it with small scripts and `curl` from the terminal — every task tells you exactly what to run. One thing that *does* need the browser: Task 4, where you attach Chrome DevTools to the running process for live memory profiling. For that task only, you'll need **View Port** to forward the inspector's port (`9229`) the same way earlier playgrounds forwarded `3000` — full steps are in that task.

Every measurement task also needs one extra flag when you start the server: `--expose-gc`. Without it, `global.gc()` doesn't exist, and you can't force a collection before measuring — so every run instruction in this lab starts the server as:
```bash
node --expose-gc leaky-server.js
```

## Steps

### Task 0 — Build the server (with both bugs already inside it)
_Mechanism: none yet — this just gives every later task a real, running target._

**What's happening here:** Below is a small HTTP server with four endpoints: `/compute` (caches an "expensive" result per id), `/subscribe` (attaches something to a shared, long-lived emitter), `/stats` (reports live memory and internal counts, forcing a GC first), and `/snapshot` (dumps a heap snapshot file, also forcing GC first). Two of these endpoints are quietly buggy — you'll spend the next few tasks proving exactly how and why, not just taking it on faith.

Create a file `leaky-server.js` and add the following:

```javascript
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
```

Create a file `load-client.js` — a small helper every later task uses to send real, repeatable traffic:

```javascript
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
```

**How to read the command you'll type:** every time you call this script, it looks like `node load-client.js <mode> <count>` — two extra words after the filename:
*   `<mode>` — which endpoint to hit, repeatedly: `compute-unique`, `compute-same`, or `subscribe`.
*   `<count>` — how many times to hit it, e.g. `300`.

So `node load-client.js subscribe 300` means: call `/subscribe` 300 times in a row. `node load-client.js compute-unique 500` means: call `/compute` 500 times, each with a brand-new id. Node hands these two words to the script as text (via `process.argv`), and `parseInt(countArg, 10)` converts `"300"` into the actual number `300` so the loop can count with it. Typing a mode this script doesn't recognize (a typo, say) is the only thing that errors — a real mode followed by a number is exactly how this script is meant to be run, every time.

**Terminal 1** — start the server and leave it running here for the rest of this task (and Tasks 1–3):

```bash
node --expose-gc leaky-server.js
```

**Terminal 2** — open a second terminal (keep Terminal 1 open and running) and check it's alive:

```bash
curl http://localhost:3000/stats
```

**Why** Starting with `--expose-gc` is what makes `global.gc()` inside `forceGC()` actually work instead of silently warning — every later measurement in this lab depends on that flag being present from the start. The `curl` confirms the server is alive and gives you the honest starting point — a small `heapUsedMB`, `cacheSize: 0`, `listenerCount: 0` — before anything has had a chance to leak. From here on, **Terminal 1 is always "run the server"** and **Terminal 2 is always "run commands against it"** — every later task follows this same two-terminal split.

**What you should see:** A JSON object with small numbers across the board. This is your true baseline — every later task compares back to something close to this.

**Note on** **`load-client.js`****:** you're not running it yet — it just sits there for now. It only makes sense once a server is already listening for it to hit, so Task 1 is where you'll actually invoke it for the first time.

### Task 1 — Prove leak #1: the unbounded cache

**What's happening here:** `/compute` caches by id so identical requests don't redo work — a completely reasonable instinct. The question is what happens to memory when the _same_ id keeps coming back versus when a _stream of new_ ids keeps coming in. We'll test both, using `/stats` (which forces a GC before reporting) so there's no ambiguity about whether growth is real or just the collector being slow.

**Terminal 1** should still be running `leaky-server.js` from Task 0 — leave it as is. **Terminal 2** — run this sequence, checking `/stats` between each step:

```bash
curl http://localhost:3000/stats
node load-client.js compute-same 300
curl http://localhost:3000/stats
node load-client.js compute-unique 300
curl http://localhost:3000/stats
node load-client.js compute-unique 300
curl http://localhost:3000/stats
```

**Why** Two `compute-unique` batches back to back, both followed by a _forced-GC_ `/stats` call, is the whole proof: if the first batch's memory came back down on its own, the second batch's growth would start from the same low baseline. Instead you'll see the increase carry over and compound — proof that GC had every chance to reclaim this memory and genuinely could not, because something is still holding onto it.

**What you should see:** After `compute-same`, `cacheSize` barely moves (it was already cached after the very first hit) and `heapUsedMB` stays essentially flat — repeating identical work is memory-neutral. After each `compute-unique` batch, `cacheSize` jumps by exactly 300 and `heapUsedMB` climbs by roughly 300 × 50KB ≈ 15MB, **even though** **`/stats`** **just forced a garbage collection immediately before reporting**. That last detail is what makes this a leak rather than normal, temporary memory use.

### Task 2 — Prove leak #2: the stray event listener

**What's happening here:** `/subscribe` attaches a listener to `sharedEmitter` on every request. Node's `EventEmitter` has a built-in safety net for exactly this situation: once a single event name passes 10 listeners, it prints a warning to the console on its own, without you writing any detection code at all.

**Terminal 1** — stop the server and restart it fresh, so listener counts start at zero:

```bash
# Ctrl+C to stop, then:
node --expose-gc leaky-server.js
```

**Terminal 2** — run:

```bash
node load-client.js subscribe 20
curl http://localhost:3000/stats
node load-client.js subscribe 500
curl http://localhost:3000/stats
```

**Why** Restarting first matters here specifically because `sharedEmitter` is created once at module load — without a fresh process, leftover listeners from an earlier task would make this count meaningless. Watch **Terminal 1** (the server's own output), not just the `curl` replies in Terminal 2 — that's where the warning prints.

**What you should see:** Partway through the first `load-client.js subscribe 20` run, the server's terminal prints something like `MaxListenersExceededWarning: Possible EventEmitter memory leak detected. 11 tick listeners added...` — Node telling you, unprompted, that something looks wrong. `/stats` afterward shows `listenerCount: 20`, and after the batch of 500 it shows `listenerCount: 520` — a number that only ever goes up, no matter how long you wait or how many times `/stats` forces a GC.

### Task 3 — Take heap snapshots and isolate each leak

**What's happening here:** A single heap snapshot is a full map of every live object and what's referencing it. On its own it's just a big pile of data — the real technique is taking **two** snapshots around a controlled bit of traffic and diffing them. To make the diff mean something, you isolate one variable at a time: first prove "neutral" traffic really is neutral, then test each leak separately against that same baseline method.

**Terminal 1** — restart the server fresh (`Ctrl+C`, then `node --expose-gc leaky-server.js`). **Terminal 2** — run this exact sequence, checking each `curl` reply for the snapshot's filename:

```bash
curl "http://localhost:3000/snapshot?name=baseline"
node load-client.js compute-same 300
curl "http://localhost:3000/snapshot?name=after-neutral"
```

**Why** `compute-same` repeats one identical key, so this diff should show **almost nothing new** — it's your control group, proving your methodology (forced GC, then snapshot) doesn't produce false alarms on its own.

**Terminal 1** — restart the server again (fresh state). **Terminal 2** — isolate leak #1:

```bash
curl "http://localhost:3000/snapshot?name=cache-before"
node load-client.js compute-unique 300
curl "http://localhost:3000/snapshot?name=cache-after"
```

**Terminal 1** — restart once more. **Terminal 2** — isolate leak #2:

```bash
curl "http://localhost:3000/snapshot?name=listeners-before"
node load-client.js subscribe 300
curl "http://localhost:3000/snapshot?name=listeners-after"
```

**Why restart between each pair** Each pair needs to start from a clean, empty cache and zero listeners — otherwise leftover growth from an earlier test would contaminate the diff you're about to read, and you wouldn't know which bug produced which growth.

**What you should see:** Five `.heapsnapshot` files sitting in `./snapshots/`. You won't read them yet — that's the next task — but confirm with `ls -lh snapshots/` that `cache-after` is noticeably larger on disk than `cache-before`, and that `after-neutral` is close in size to `baseline`.

### Task 4 — Diff the snapshots in Chrome DevTools and read the retainer path

**What's happening here:** You already have two "photos" of memory from Task 3 — one before some traffic, one after. This task is just: open both photos side by side in a tool that highlights what's different between them, then click on the biggest difference to see _why_ it's still there. Nothing new is being run or tested here — you're purely looking at data you already collected.

**Step 1 — get the snapshot files onto your own computer.**
The files exist inside the lab container, but your Chrome browser is running on your own machine, so it can't see the container's disk at all. In the file explorer on the left of your editor, find the `snapshots/` folder, right-click each of the five `.heapsnapshot` files one at a time, and choose **Download**. This just copies each file onto your own computer (usually into your Downloads folder) — nothing more.

**Step 2 — open DevTools' Memory tab.**
Open any Chrome window, press **F12**, and click the **Memory** tab along the top. You do _not_ need `chrome://inspect` or any forwarded port for this — you're only about to open local files, not connect to anything remote.

**Step 3 — load the two files you want to compare.**
Click **Load** (the upload-arrow icon near the top-left of the Memory panel) and pick `cache-before.heapsnapshot`. Click **Load** again and pick `cache-after.heapsnapshot`. Both now appear as two separate rows in the **Heap snapshots** list on the left — but neither is open yet, they're just listed.

**Step 4 — open one of them.**
Click directly on the name `cache-after...` in that left-hand list. The main panel switches from the "Select profiling type" screen to a table of object types and sizes — that means the snapshot is now open.

**Step 5 — switch to Comparison view.**
Near the top of that table, there's a dropdown currently set to **"Summary."** Change it to **"Comparison."** A second dropdown appears next to it — set that one to `cache-before`. The table now shows, for every object type, how many new instances appeared and how many bytes they added, between the two snapshots.

**Step 6 — sort so the biggest change is on top.**
Click the **`Alloc. size`** column header once or twice until the largest number is at the top (this table starts alphabetical by name, not by size, so it looks unremarkable until you sort it). Once sorted, you'll see a small group of rows that all grew by roughly the same amount — around `300`, matching your `compute-unique 300` traffic. On a real run, the ones you're looking for are:
*   **`{id, data}`** — this is literally the shape of the object your code creates: `{ id, data: Buffer.alloc(...) }`. DevTools names object types with no class after their shape, which is why it shows up this way instead of a named class.
*   **`Buffer`** / **`ArrayBuffer`** / **`system / JSArrayBufferData`** — these are the actual 50KB payloads living inside each `data` field; you'll usually see several related rows here rather than one, since a `Buffer` is really a thin wrapper around a raw `ArrayBuffer`.

**Step 7 — read the retainer path.**
Click the small `▶` arrow next to `{id, data}` to expand it, click one instance from the list underneath, and look at the **Retainers** pane at the very bottom of the screen. It shows a short chain of "what's holding this alive," ending in something like `Map → cache → (global)`. That chain is your proof: this object only still exists because your `cache` Map hasn't let it go.

**Step 8 — repeat for the listener leak.**
Download and open `listeners-before.heapsnapshot` and `listeners-after.heapsnapshot` the same way (Steps 1–5). Sort by `Alloc. size` again, and this time look for a large positive delta in **`(closure)`** or **`system / Context`** rows instead — those are your per-request `onTick` functions. Their retainer path should run back through `sharedEmitter`'s internal listener list rather than through `cache`.

**What you should see:** For the cache pair, one or two rows near the top of the sorted table jump out with `#New` close to `300` and a multi-megabyte `Alloc. size` — and clicking into one traces straight back to `cache`. For the listener pair, the standout rows are closures/contexts instead of buffers, and their trail leads back to `sharedEmitter` instead. Two different object types, two different trails, two separately confirmed bugs — this is what "finding a leak" actually looks like in practice, not a guess based on a single big number.

**Live alternative, worth trying once:** instead of triggering a snapshot through an HTTP route, this takes one directly from inside the running process using VS Code's own debugger.

1. **Terminal 1** — start the server with the inspector on:

```bash
node --inspect --expose-gc leaky-server.js
```

2. Press `Ctrl+Shift+P`, type **"Attach to Node Process"**, and pick the `leaky-server.js` one from the list.
3. Click the **Debug Console** tab (next to Terminal) and type:

```javascript
require('v8').writeHeapSnapshot('snapshots/live-test.heapsnapshot')
```

4. It prints the file path back — a real snapshot file now sits in `snapshots/`, made the same way as Task 3's, just triggered directly instead of through `/snapshot`. Download and load it in Chrome exactly as before to look inside it.

### Task 5 — Reveal the fix and prove it with the same tests

**What's happening here:** Time to look at the corrected version. It fixes leak #1 by capping the cache at a fixed size and evicting the oldest entry once that limit is hit (a simple LRU), and fixes leak #2 by removing each request's listener the moment that request's response finishes — so nothing outlives the request that created it.

Create a file `fixed-server.js` and add the following:

```javascript
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
```

**Terminal 1** — stop `leaky-server.js` (`Ctrl+C`), then start the fixed one in its place:

```bash
node --expose-gc fixed-server.js
```

**Terminal 2** — run the exact same recipe from Task 1 and Task 2, now against the fixed server:

```bash
curl http://localhost:3000/stats
node load-client.js compute-unique 300
curl http://localhost:3000/stats
node load-client.js compute-unique 300
curl http://localhost:3000/stats
node load-client.js subscribe 300
curl http://localhost:3000/stats
```

**Why re-run the identical recipe** Using the exact same test as Tasks 1 and 2, unchanged, is what makes this a legitimate before/after comparison — any difference in outcome can only be explained by the code, not by a different or easier test.

**What you should see:** After both `compute-unique` batches (600 requests total, all unique ids), `cacheSize` never exceeds `50` — it grows to the cap and then holds there. `heapUsedMB` grows only up to a point and then **plateaus** instead of climbing forever. After the `subscribe` batch of 300, `listenerCount` sits at `0` (or a very small transient number) instead of `300` — because each listener was removed the instant its own request finished.

### Bonus Task — Watch the trend live, leaky vs fixed

**What's happening here:** Numbers at two points in time are convincing; watching the trend unfold in real time is more convincing still. This script polls `/stats` once a second and prints a simple text bar for `heapUsedMB`, so you can literally watch one server's memory climb and the other plateau.

Create a file `memory-trend.js` and add the following:

```javascript
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
```

**Terminal 1** — run the **leaky** server first:

```bash
node --expose-gc leaky-server.js
```

**Terminal 2** — start the trend logger in the background, then drive traffic in the same terminal:

```bash
node memory-trend.js &
node load-client.js compute-unique 800
```

Then go back to **Terminal 1**, stop it, restart with `node --expose-gc fixed-server.js`, and in **Terminal 2** repeat the exact same two commands.

**Why** Driving 800 unique-id requests while sampling once a second turns a single before/after number into a full trend line you watch happen — on the leaky server the `#` bar should visibly lengthen roughly the whole time; on the fixed server it should lengthen for a while and then stop growing once the cache hits its cap.

**What you should see:** Against `leaky-server.js`, the printed bar keeps getting longer for the full 30 seconds. Against `fixed-server.js`, the bar lengthens early on and then holds steady in length for the remaining samples — the plateau you predicted from the code, now visible line by line.

## Validation
Run through each check and confirm the actual behavior, not just that the script ran without errors:

- [ ] Task 0: `curl /stats` on a fresh server returns small, near-zero numbers.
- [ ] Task 1: `compute-same` leaves `heapUsedMB` essentially flat; two `compute-unique` batches each add ~15MB that never comes back down, even right after a forced GC.
- [ ] Task 2: the server's terminal prints `MaxListenersExceededWarning`; `listenerCount` only ever increases, never resets.
- [ ] Task 3: five `.heapsnapshot` files exist in `snapshots/`, with `cache-after` visibly larger than `cache-before`.
- [ ] Task 4: DevTools' Comparison view identifies growth traced to the `cache` `Map` in one pair, and to `sharedEmitter`'s closures in the other.
- [ ] Task 5: against `fixed-server.js`, `cacheSize` never exceeds 50 and `listenerCount` returns to (near) 0 after `subscribe` traffic finishes.
- [ ] Bonus: the live trend bar visibly keeps growing against `leaky-server.js` and visibly plateaus against `fixed-server.js`.

## References & further learning
*   Node.js docs: `v8.writeHeapSnapshot()`: [https://nodejs.org/api/v8.html#v8writeheapsnapshotfilename-options](https://nodejs.org/api/v8.html#v8writeheapsnapshotfilename-options)
*   Node.js docs: `--inspect` and the Inspector: [https://nodejs.org/api/cli.html#--inspecthostport](https://nodejs.org/api/cli.html#--inspecthostport)
*   Node.js docs: `EventEmitter` and `setMaxListeners`: [https://nodejs.org/api/events.html#emittersetmaxlistenersn](https://nodejs.org/api/events.html#emittersetmaxlistenersn)
*   Node.js docs: `process.memoryUsage()`: [https://nodejs.org/api/process.html#processmemoryusage](https://nodejs.org/api/process.html#processmemoryusage)
*   Chrome DevTools: Fix memory problems (heap snapshots & comparison view): [https://developer.chrome.com/docs/devtools/memory-problems/](https://developer.chrome.com/docs/devtools/memory-problems/)

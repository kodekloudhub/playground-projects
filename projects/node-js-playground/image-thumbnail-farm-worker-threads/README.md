# Image Thumbnail Farm (worker_threads Pool)

**Level:** intermediate  ·  **Playground:** Node JS Playground

▶ **[Launch the playground](https://kodekloud.com/playgrounds/playground-nodejs)** — open it, then copy the files below.

A [`commands.sh`](./commands.sh) with the runnable steps is included.

![](https://t37266828.p.clickup-attachments.com/t37266828/7bd74174-40c9-446a-a65f-9f894b1ff9d1/Marketing%20Youtube%20Labs%20Team%20-%20Architecture%20Diagram%20Maker%20\(1\).png)
# Image Thumbnail Farm

```markdown
---
# ─── Metadata (read by the playground for listing & filtering) ───
id: image-thumbnail-farm-worker-threads
title: "Image Thumbnail Farm (worker_threads Pool)"
playground: Node.js
playground_link: https://kodekloud.com/playgrounds/playground-nodejs
difficulty: intermediate
estimated_minutes: 100
tags:
  - nodejs
  - javascript
  - worker_threads
  - concurrency
  - performance
  - binary
  - images
skills:
  - worker_threads
  - thread pools
  - task queues
  - idle-worker tracking
  - structured clone vs SharedArrayBuffer
  - graceful shutdown
  - benchmarking
prerequisites:
  - Basic JavaScript syntax (functions, variables, classes)
  - Comfortable with Node.js `require`, callbacks, and Buffers
  - No prior worker_threads or multithreading experience required
---

# Image Thumbnail Farm (worker_threads Pool)

## Scenario
Your app lets users upload photos, and you need to generate thumbnails. The obvious way — resize the image right there in your request handler — works fine in testing. Then a real user uploads a big photo, and suddenly *every other user's request freezes* for a few seconds. Your lead wants you to understand exactly why that happens, and build the fix yourself — no libraries at first — starting from a plain resize function that blocks everything, and turning it into a proper `worker_threads` pool with a task queue, idle-worker tracking, fast shared-memory transfer, and a clean shutdown path.

## What you'll build
Starting from a resize function that freezes everything while it runs, you'll turn it into a `worker_threads` pool: a fixed team of worker threads, a task queue that holds jobs until a worker is free, idle-worker tracking that hands off jobs automatically, a `SharedArrayBuffer` for fast image transfer, and a graceful shutdown path — proven at every step with real image files, real timings, and real console output, not just theory. You'll finish by benchmarking 1 worker against N workers, and by swapping in the real-world `sharp` library for real JPEG support.

## Learning objectives
By the end you will be able to:
- Explain why CPU-bound work (unlike I/O) blocks Node's single main thread, and prove it live.
- Spawn a `worker_threads` Worker and pass messages back and forth.
- Build a worker **pool**: a fixed set of reusable workers instead of one-per-job.
- Implement a **task queue** and **idle-worker tracking** so jobs are handed to free workers automatically.
- Explain the difference between the default **structured clone** (copy) and a **`SharedArrayBuffer`** (zero-copy, shared memory), and measure the difference on a real file.
- Shut a pool down **gracefully** — finish in-flight work, then terminate cleanly.
- Build a benchmark harness and prove parallel speedup with real numbers.
- Understand why a native library like `sharp` behaves differently inside a worker pool than hand-written JS.

## Prerequisites
- Playground: **Node.js** (open it before starting)
- Node.js available in the sandbox (`node -v` to confirm — Node 12+ has `worker_threads` built in, no install needed for the core lab)

## Why most tasks create two files
`worker_threads` runs a worker as a **separate file** on its own thread — you can't just call a function on another thread, you point `new Worker(...)` at a file path, and Node loads and runs that file independently. So from Task 2 onward, each task naturally splits into two files: one file is the **worker** (the code that actually runs on the separate thread, reacting to messages), and the other is the **controller** (the code that runs on the main thread, spawning the worker, sending it jobs, and reading its replies). They're two separate files because they're two separate threads — not an arbitrary way to split the code.

## Steps

### Task 0 — Generate real sample images
*Mechanism: none yet — this just gives every later task real data to work with.*

**What's happening here:** Every task after this one needs real image files to resize. Rather than downloading photos from the internet (the sandbox can't do that), we generate them ourselves — real, valid, uncompressed BMP files with a visible gradient pattern, so file sizes and pixel data are real, not fake. **Run this task first — every later task assumes these files already exist.
**Why:** BMP specifically: it stores pixels uncompressed, so a pure-JS reader/writer is short and simple — no JPEG/PNG decoder needed to get this lab running.

Create a file `bmp-utils.js` and add the following:
```javascript
// bmp-utils.js
// Minimal uncompressed 24-bit BMP reader/writer + nearest-neighbor resize. BMP is deliberately simple (no compression) so we can read and write real image files without needing a JPEG/PNG decoder.

function createBMP(width, height, pixelFn) {
  const rowSize = Math.floor((24 * width + 31) / 32) * 4; // rows padded to 4 bytes
  const pixelArraySize = rowSize * height;
  const fileSize = 54 + pixelArraySize;

  const buf = Buffer.alloc(fileSize);
  buf.write('BM', 0);
  buf.writeUInt32LE(fileSize, 2);
  buf.writeUInt32LE(54, 10); // pixel data offset
  buf.writeUInt32LE(40, 14); // DIB header size
  buf.writeInt32LE(width, 18);
  buf.writeInt32LE(height, 22); // positive = bottom-up
  buf.writeUInt16LE(1, 26); // planes
  buf.writeUInt16LE(24, 28); // bits per pixel
  buf.writeUInt32LE(0, 30); // no compression
  buf.writeUInt32LE(pixelArraySize, 34);

  for (let y = 0; y < height; y++) {
    const fileRow = height - 1 - y; // bottom-up storage
    const rowStart = 54 + fileRow * rowSize;
    for (let x = 0; x < width; x++) {
      const [r, g, b] = pixelFn(x, y);
      const off = rowStart + x * 3;
      buf[off] = b; buf[off + 1] = g; buf[off + 2] = r; // BGR order
    }
  }
  return buf;
}

function readBMP(buf) {
  const width = buf.readInt32LE(18);
  const height = buf.readInt32LE(22);
  const rowSize = Math.floor((24 * width + 31) / 32) * 4;
  function getPixel(x, y) {
    const fileRow = height - 1 - y;
    const off = 54 + fileRow * rowSize + x * 3;
    return [buf[off + 2], buf[off + 1], buf[off]]; // back to RGB
  }
  return { width, height, getPixel };
}

function resizeBMP(inputBuf, targetWidth, targetHeight) {
  const src = readBMP(inputBuf);
  return createBMP(targetWidth, targetHeight, (x, y) => {
    const srcX = Math.floor((x / targetWidth) * src.width);
    const srcY = Math.floor((y / targetHeight) * src.height);
    return src.getPixel(srcX, srcY);
  });
}

module.exports = { createBMP, readBMP, resizeBMP };
```

Create a file `create-sample-images.js` and add the following:

```javascript
// create-sample-images.js
const { createBMP } = require('./bmp-utils');
const fs = require('fs');

fs.mkdirSync('samples', { recursive: true });
fs.mkdirSync('thumbs', { recursive: true });

const COUNT = 8;
for (let i = 0; i < COUNT; i++) {
  const seed = i * 37;
  const img = createBMP(1600, 1200, (x, y) => [
    (x + seed) % 256,
    (y + seed) % 256,
    (x + y + seed) % 256,
  ]);
  fs.writeFileSync(`samples/photo${i}.bmp`, img);
}
console.log(`created ${COUNT} real sample images in ./samples/`);
```

Run it:

```bash
node create-sample-images.js
ls -lh samples/
```

**Why** `node create-sample-images.js` actually executes the script — creating the file doesn't run it, Node only runs code when you explicitly tell it to. `ls -lh samples/` then lists what's in that folder — this is how you confirm real files exist before trusting any later task.

**What you should see:** 8 real `.bmp` files listed, each a few megabytes. These are valid, openable image files with real pixel data — everything from here on works on these actual files.

### Task 1 — Prove the problem: CPU-bound work blocks the main thread
_Mechanism: why CPU-bound work blocks Node's single thread_

**What's happening here:** Resizing an image is pure computation — read pixel numbers, do math, write new pixel numbers — with no natural pause where Node could do anything else. To prove that, we start a heartbeat that logs `tick` every 200ms (standing in for "the server doing other work"), then resize a real sample image synchronously, right on the main thread, and watch what happens to the heartbeat.
Why this matters: until you've seen the freeze happen, "CPU-bound work blocks Node" is just a sentence — this task turns it into something you watched happen on your own screen, which is the whole justification for every task after this one.

Create a file `resize-work.js` and add the following:

```javascript
// resize-work.js
const fs = require('fs');
const { resizeBMP } = require('./bmp-utils');

function resizeImageFile(inputPath, outputPath, targetWidth, targetHeight) {
  const inputBuf = fs.readFileSync(inputPath);
  const outputBuf = resizeBMP(inputBuf, targetWidth, targetHeight);
  fs.writeFileSync(outputPath, outputBuf);
  return { inputBytes: inputBuf.length, outputBytes: outputBuf.length };
}

module.exports = { resizeImageFile };
```

Create a file `blocking-demo.js` and add the following:

```javascript
// blocking-demo.js
const { resizeImageFile } = require('./resize-work');

setInterval(() => console.log('tick'), 200);

setTimeout(() => {
  console.log('--- resizing a REAL image on the MAIN thread ---');
  const start = Date.now();
  const result = resizeImageFile('samples/photo0.bmp', 'thumbs/photo0-blocking.bmp', 200, 150);
  console.log(`--- done in ${Date.now() - start}ms (${result.inputBytes} -> ${result.outputBytes} bytes) ---`);
}, 1000);
```

Run it:

```bash
node blocking-demo.js
```

**Why** `node blocking-demo.js` runs the whole file as one live process — the heartbeat and the resize both happen inside that single run. There's no other way to actually watch the freeze happen; reading the code can't show you _when_ the ticks stop, only running it can.

**What you should see:** `tick` printed every 200ms — until the resize starts. Then **the ticks completely stop** for the duration of the resize, resuming only once the "done" line prints. Check `thumbs/photo0-blocking.bmp` afterward with `ls -lh` — a real, much smaller file exists, but producing it froze everything else the whole time.

### Task 2 — Talk to a single worker
_Mechanism:_ _`worker_threads`_ _basics_

**What's happening here:** Before building a pool, prove the basic wiring works: spawn one worker (a separate thread running its own file), send it a message, and get a reply back.
**Why:** start this small: every later task — the pool, the queue, the shutdown logic — is built entirely out of this one send/receive pattern repeated many times, so it's worth confirming it works on its own first.

Create a file `worker-basic.js` and add the following:

```javascript
// worker-basic.js
const { parentPort } = require('worker_threads');

parentPort.on('message', (msg) => {
  console.log('[worker] received:', msg);
  parentPort.postMessage(`hello back, I got: ${msg}`);
});
```

Create a file `main-basic.js` and add the following:

```javascript
// main-basic.js
const { Worker } = require('worker_threads');

const worker = new Worker('./worker-basic.js');

worker.on('message', (msg) => {
  console.log('[main] got reply:', msg);
  worker.terminate();
});

console.log('[main] sending a message to the worker...');
worker.postMessage('ping');
```

Run it:

```bash
node main-basic.js
```

\*\*Why \*\* You only ever run `main-basic.js` directly — it's the controller, and it spawns `worker-basic.js` itself via `new Worker(...)`. You never type `node worker-basic.js`; that file only makes sense running _inside_ a thread the controller creates.

**What you should see:** Three lines in order: `[main] sending...`, `[worker] received: ping`, `[main] got reply: hello back, I got: ping`. Two separate threads really did talk to each other.

### Task 3 — Move the real resize into a worker
_Mechanism:_ _`worker_threads`_ _fixes the blocking problem_

**What's happening here:** Same heartbeat test as Task 1, same real image, same resize work — but this time it runs _inside_ the worker from Task 2's pattern instead of on the main thread.
**Why:** repeat the exact same test: reusing Task 1's setup, unchanged, is what makes this a real before/after comparison — any difference in the outcome can only be explained by where the work ran, not by anything else changing.

Create a file `worker-resize.js` and add the following:

```javascript
// worker-resize.js
const { parentPort } = require('worker_threads');
const { resizeImageFile } = require('./resize-work');

parentPort.on('message', ({ inputPath, outputPath, targetWidth, targetHeight }) => {
  const result = resizeImageFile(inputPath, outputPath, targetWidth, targetHeight);
  parentPort.postMessage({ done: true, outputPath, ...result });
});
```

Create a file `nonblocking-demo.js` and add the following:

```javascript
// nonblocking-demo.js
const { Worker } = require('worker_threads');

setInterval(() => console.log('tick'), 200);

setTimeout(() => {
  console.log('--- resizing the SAME real image, but in a worker ---');
  const start = Date.now();
  const worker = new Worker('./worker-resize.js');

  worker.postMessage({
    inputPath: 'samples/photo0.bmp',
    outputPath: 'thumbs/photo0-nonblocking.bmp',
    targetWidth: 200, targetHeight: 150,
  });

  worker.on('message', (msg) => {
    console.log(`--- done in ${Date.now() - start}ms -> wrote ${msg.outputPath} ---`);
    worker.terminate();
  });
}, 1000);
```

Run it:

```bash
node nonblocking-demo.js
```

**Why** Same idea as Task 2 — you run the controller (`nonblocking-demo.js`), and it spawns `worker-resize.js` on its own. Running it is also the only way to actually watch the ticks keep going this time, which is the whole point of the comparison with Task 1.

**What you should see:** The ticks **never stop** — same real file, same resize work as Task 1, but the heartbeat keeps going right through it. `thumbs/photo0-nonblocking.bmp` is written once it's done, same result as Task 1's output, just produced without freezing anything.

### Task 4 — Build the pool: task queue + idle-worker tracking
_Mechanism: thread pools, task queues, idle-worker tracking_

**What's happening here:** Spawning a new worker per job wastes the overhead of thread creation, so instead we build a **pool**: a fixed number of workers, created once and reused across many images. Jobs that arrive while all workers are busy wait in a **queue**. The pool also tracks which workers are **idle** vs busy, so it can hand off the next queued job the moment a worker frees up.
**Why:** a queue and idle-tracking specifically: with 8 real images and only 4 workers, something has to decide who works on what and when — without this bookkeeping, jobs would either get dropped or overload a single worker instead of spreading out evenly.

Create a file `pool.js` and add the following:

```javascript
// pool.js
const { Worker } = require('worker_threads');
const os = require('os');

class ThumbnailPool {
  constructor(workerFile, poolSize = os.cpus().length) {
    this.queue = [];       // jobs waiting for a free worker
    this.idleWorkers = []; // workers currently free
    this.allWorkers = [];

    for (let i = 0; i < poolSize; i++) {
      const worker = new Worker(workerFile);
      worker.id = i;
      this.allWorkers.push(worker);
      this.idleWorkers.push(worker);
    }
    console.log(`[pool] started with ${poolSize} workers`);
  }

  submit(jobData) {
    return new Promise((resolve, reject) => {
      this.queue.push({ jobData, resolve, reject });
      this._dispatch();
    });
  }

  _dispatch() {
    while (this.queue.length > 0 && this.idleWorkers.length > 0) {
      const worker = this.idleWorkers.pop();
      const job = this.queue.shift();

      console.log(`[pool] worker ${worker.id} picked up ${job.jobData.inputPath} (${this.queue.length} still queued)`);

      const onMessage = (result) => {
        console.log(`[pool] worker ${worker.id} finished -> ${result.outputPath}`);
        worker.off('message', onMessage);
        job.resolve(result);
        this.idleWorkers.push(worker);
        this._dispatch(); // this worker is free again — check the queue
      };

      worker.on('message', onMessage);
      worker.postMessage(job.jobData);
    }
  }
}

module.exports = { ThumbnailPool };
```

Reuse `worker-resize.js` from Task 3 as the pool's worker file. Create a file `pool-demo.js` and add the following:

```javascript
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
```

Run it:

```bash
node pool-demo.js
ls -lh thumbs/
```

**Why:** `node pool-demo.js` starts the controller, which builds the pool and submits all 8 jobs. `ls -lh thumbs/` is the follow-up check — it confirms the pool actually _produced_ 8 real thumbnail files, not just printed logs claiming it did.

**What you should see:** `[pool] started with 4 workers`, then only **4 jobs picked up immediately** while the rest sit in the queue — visible via the shrinking "still queued" count. As each worker finishes, it grabs the next queued job, until all 8 real images are resized.

### Task 5 — Fast transfer: structured clone vs SharedArrayBuffer
_Mechanism: structured clone (copy) vs_ _`SharedArrayBuffer`_ _(zero-copy transfer)_

**What's happening here:** `postMessage` normally **copies** whatever you send (the "structured clone algorithm") — for a large real image buffer, that copy costs real time. A `SharedArrayBuffer` is different: it's a block of memory **both threads can access at once**, with no copy at all. Let's measure the difference using one of our real 5MB+ sample files.
**Why:** this matters for a thumbnail farm specifically: every job in this pool involves handing image bytes to a worker, so if that handoff itself is slow, it eats into the very speedup the pool is supposed to deliver.

Create a file `echo-worker.js` and add the following:

```javascript
// echo-worker.js
const { parentPort } = require('worker_threads');
parentPort.on('message', () => parentPort.postMessage('done'));
```

Create a file `transfer-compare.js` and add the following:

```javascript
// transfer-compare.js
const { Worker } = require('worker_threads');
const fs = require('fs');

const realImageBytes = fs.readFileSync('samples/photo0.bmp'); // a real multi-MB file

function timeCopy() {
  return new Promise((resolve) => {
    const worker = new Worker('./echo-worker.js');
    const start = Date.now();
    worker.postMessage({ data: realImageBytes }); // plain Buffer -> Node copies it all
    worker.on('message', () => {
      console.log(`[copy]   took ${Date.now() - start}ms`);
      worker.terminate();
      resolve();
    });
  });
}

function timeShared() {
  return new Promise((resolve) => {
    const worker = new Worker('./echo-worker.js');
    const start = Date.now();
    const sab = new SharedArrayBuffer(realImageBytes.length);
    new Uint8Array(sab).set(realImageBytes); // one-time copy INTO shared memory
    worker.postMessage({ sab });              // this line just hands over a reference
    worker.on('message', () => {
      console.log(`[shared] took ${Date.now() - start}ms`);
      worker.terminate();
      resolve();
    });
  });
}

(async () => {
  console.log(`comparing with a real ${(realImageBytes.length / 1024 / 1024).toFixed(1)}MB image file\n`);
  await timeCopy();
  await timeShared();
})();
```

Run it:

```bash
node transfer-compare.js
```

**Why** One run of this file does both timings back-to-back, in the same process, on the same real file — which is what makes the two numbers a fair, apples-to-apples comparison instead of two separate, differently-timed runs.

**What you should see:** Two real timings on the same real file — `[shared]` clearly faster than `[copy]`, since one is copying megabytes and the other isn't. (Note: because both threads can read _and write_ a `SharedArrayBuffer` at once, real production code needs `Atomics` to coordinate access safely.)

### Task 6 — Graceful shutdown
_Mechanism: graceful shutdown_

**What's happening here:** Killing worker threads mid-job would lose in-flight work. A graceful shutdown means: stop accepting new jobs, let jobs already running finish, _then_ terminate every worker cleanly.
**Why:** this can't be an afterthought: a pool that never shuts down cleanly will either lose whatever a worker was mid-way through, or leave threads running in the background after your app thinks it's stopped.

Update `pool.js` with the complete class below — it's the same constructor, `submit`, and `_dispatch` from Task 4, plus the new `shutdown` method added at the end:

```javascript
// pool.js
const { Worker } = require('worker_threads');
const os = require('os');

class ThumbnailPool {
  constructor(workerFile, poolSize = os.cpus().length) {
    this.queue = [];       // jobs waiting for a free worker
    this.idleWorkers = []; // workers currently free
    this.allWorkers = [];

    for (let i = 0; i < poolSize; i++) {
      const worker = new Worker(workerFile);
      worker.id = i;
      this.allWorkers.push(worker);
      this.idleWorkers.push(worker);
    }
    console.log(`[pool] started with ${poolSize} workers`);
  }

  submit(jobData) {
    return new Promise((resolve, reject) => {
      this.queue.push({ jobData, resolve, reject });
      this._dispatch();
    });
  }

  _dispatch() {
    while (this.queue.length > 0 && this.idleWorkers.length > 0) {
      const worker = this.idleWorkers.pop();
      const job = this.queue.shift();

      console.log(`[pool] worker ${worker.id} picked up ${job.jobData.inputPath} (${this.queue.length} still queued)`);

      const onMessage = (result) => {
        console.log(`[pool] worker ${worker.id} finished -> ${result.outputPath}`);
        worker.off('message', onMessage);
        job.resolve(result);
        this.idleWorkers.push(worker);
        this._dispatch(); // this worker is free again — check the queue
      };

      worker.on('message', onMessage);
      worker.postMessage(job.jobData);
    }
  }

  async shutdown() {
    console.log(`[pool] shutdown requested, ${this.queue.length} jobs still queued, will be rejected`);

    this.queue.forEach((job) => job.reject(new Error('pool shutting down')));
    this.queue = [];

    const busyCount = this.allWorkers.length - this.idleWorkers.length;
    console.log(`[pool] waiting for ${busyCount} in-flight job(s) to finish...`);

    await new Promise((resolve) => {
      const check = setInterval(() => {
        if (this.idleWorkers.length === this.allWorkers.length) {
          clearInterval(check);
          resolve();
        }
      }, 50);
    });

    await Promise.all(this.allWorkers.map((w) => w.terminate()));
    console.log('[pool] all workers terminated — shutdown complete');
  }
}

module.exports = { ThumbnailPool };
```

Create a file `shutdown-demo.js` and add the following:

```javascript
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
```

Run it:

```bash
node shutdown-demo.js
```

**Why** Running it is what actually triggers the race between "jobs still queued" and "shutdown requested" — the 100ms delay, the rejections, and the in-flight jobs finishing all have to happen live, inside one real run, to see the correct behavior play out in order.

**What you should see:** With 8 real jobs and only 4 workers, shutdown triggers while 4 are queued — those log `[job] rejected: pool shutting down`, while the 4 already in flight are allowed to finish (real thumbnail files appear for those) before `all workers terminated — shutdown complete` prints.

### Task 7 — Benchmark: 1 worker vs N workers
_Mechanism: benchmarking parallel speedup_

**What's happening here:** Prove the whole point with real numbers. Run the same real batch of images through a 1-worker pool and a 4-worker pool, and compare.
**Why:** a benchmark and not just a feeling: everything from Task 1 onward has been building toward one claim — spreading work across threads is faster — and a benchmark is the only way to actually confirm that claim instead of assuming it.

Create a file `benchmark.js` and add the following:

```javascript
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
```

Run it:

```bash
node benchmark.js
```

**Why** This single run does both the 1-worker batch and the 4-worker batch back-to-back, in the same process, on the same 8 images — keeping conditions identical between the two so the speedup number actually means something.

**What you should see:** Two real millisecond timings on the same real 8-image batch, followed by a speedup factor — expect somewhere close to 3–4x with 4 workers.

### Bonus Task — Swap in `sharp` for a real JPEG
_Mechanism: hand-written pure-JS engine vs a native production library_

**What's happening here:** Our pure-JS engine only understands the simple BMP format. Real apps deal with JPEG/PNG, which need real decoders — that's what the `sharp` library provides. Let's make the resize engine try `sharp` first and fall back to our pure-JS engine automatically.
**Why:** bother with a fallback at all: it mirrors how you'd actually ship this — use the fast, real library where it's available, without leaving the app broken in an environment where it isn't.

**Important caveat:** `sharp` doesn't do its pixel math in JavaScript at all — it hands the work to a native library (`libvips`), which manages its own internal thread pool, separate from `worker_threads`. That means sharp is already avoiding the main thread on its own — so a version of Task 1's "prove the freeze" test using sharp instead of our pure-JS engine likely wouldn't show a freeze at all. That's not a bug — it's a real difference: our hand-written engine teaches the mechanics of blocking and worker\_threads; sharp shows what a production library already handles internally.

Create a file `resize-work-smart.js` and add the following:

```javascript
// resize-work-smart.js
const fs = require('fs');
const { resizeBMP } = require('./bmp-utils');

let sharp = null;
try {
  sharp = require('sharp');
} catch {
  // not installed -- pure-JS fallback below
}

async function resizeImageFileSmart(inputPath, outputPath, targetWidth, targetHeight) {
  if (sharp) {
    await sharp(inputPath).resize(targetWidth, targetHeight).toFile(outputPath);
    return { engine: 'sharp' };
  }
  const inputBuf = fs.readFileSync(inputPath);
  const outputBuf = resizeBMP(inputBuf, targetWidth, targetHeight);
  fs.writeFileSync(outputPath, outputBuf);
  return { engine: 'pure-js' };
}

module.exports = { resizeImageFileSmart };
```

Install sharp (fine if it fails — the code above falls back automatically). Sharp's latest release needs Node ≥ 20.9 — if your playground runs Node 18, pin an older version instead:

```bash
npm install sharp@0.33.5
```

**Why** `sharp` is a native library (compiled code, not plain JavaScript), so it has to be installed like any npm package before `require('sharp')` can find it. If the install fails or the platform isn't supported, the try/catch in `resize-work-smart.js` falls back to the pure-JS engine instead of crashing. Pinning `@0.33.5` avoids a real issue where the newest sharp release refuses to load on Node 18.

Create a file `make-real-jpeg.js` and add the following:

```javascript
// make-real-jpeg.js
let sharp;
try {
  sharp = require('sharp');
} catch (err) {
  console.log('sharp is not available in this environment:', err.message.split('\n')[0]);
  console.log('skip this step — the rest of the lab does not need sharp.');
  process.exit(0);
}

sharp({ create: { width: 1600, height: 1200, channels: 3, background: { r: 80, g: 140, b: 200 } } })
  .jpeg()
  .toFile('samples/real-photo.jpg')
  .then(() => console.log('created a real JPEG'));
```

Run it:

```bash
node make-real-jpeg.js
node -e "require('./resize-work-smart').resizeImageFileSmart('samples/real-photo.jpg','thumbs/real-photo-thumb.jpg',200,150).then(r => console.log('resized using engine:', r.engine))"
ls -lh samples/real-photo.jpg thumbs/real-photo-thumb.jpg
```

**Why** `node make-real-jpeg.js` creates a real compressed JPEG using sharp, since our pure-JS engine can only read BMP — we need a genuine JPEG to prove the bonus task actually works on one. The `node -e "..."` line runs a short one-off script directly from the terminal (no need to save a whole extra file just to call one function) to resize that JPEG and print which engine handled it. `ls -lh` on both files then compares the real original size against the real thumbnail size, so the result is a file you can verify, not just a log message.

**Optional:** if you upload your own real photo into this playground's file browser, point `inputPath` at it instead of `samples/real-photo.jpg` — the same code will work on it.

**What you should see:** `resized using engine: sharp` (or `pure-js` if sharp couldn't install), and a real, much smaller JPEG thumbnail file.

## Validation
Run through each check and confirm the actual behavior, not just that the script ran without errors:

- [ ] Task 0: `samples/` contains 8 real `.bmp` files with real, non-zero sizes.
- [ ] Task 1: `tick` logs completely stop during the real resize and resume right after.
- [ ] Task 2: terminal shows the send → worker receive → main reply sequence, in order.
- [ ] Task 3: `tick` logs **never stop**, even during the same real resize as Task 1; `thumbs/photo0-nonblocking.bmp` exists.
- [ ] Task 4: only 4 jobs are picked up immediately (matching pool size); `thumbs/` ends up with 8 new `pool-*.bmp` files.
- [ ] Task 5: `[shared]` timing is clearly faster than `[copy]` on the real image file.
- [ ] Task 6: queued-but-not-started jobs are rejected immediately; in-flight jobs finish and produce real output files before workers terminate.
- [ ] Task 7: benchmark prints two real timings and a speedup factor greater than 1x.
- [ ] Bonus: `resize-work-smart.js` reports `sharp` (or falls back to `pure-js` cleanly) and produces a real resized JPEG.

## References & further learning
*   Node.js docs: `worker_threads`: [https://nodejs.org/api/worker\_threads.html](https://nodejs.org/api/worker_threads.html)
*   Node.js docs: `SharedArrayBuffer` & `Atomics`: [https://nodejs.org/api/worker\_threads.html#worker-threads](https://nodejs.org/api/worker_threads.html#worker-threads)
*   MDN: SharedArrayBuffer: [https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global\_Objects/SharedArrayBuffer](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/SharedArrayBuffer)
*   MDN: Atomics: [https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global\_Objects/Atomics](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Atomics)
*   BMP file format reference: [https://en.wikipedia.org/wiki/BMP\_file\_format](https://en.wikipedia.org/wiki/BMP_file_format)
*   `sharp` (real-world image library, used in the bonus task): [https://sharp.pixelplumbing.com/](https://sharp.pixelplumbing.com/)

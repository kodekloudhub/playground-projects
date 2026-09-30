#!/usr/bin/env bash
set -euo pipefail

Create a file `create-sample-images.js` and add the following:

Run it:

**Why** `node create-sample-images.js` actually executes the script — creating the file doesn't run it, Node only runs code when you explicitly tell it to. `ls -lh samples/` then lists what's in that folder — this is how you confirm real files exist before trusting any later task.

**What you should see:** 8 real `.bmp` files listed, each a few megabytes. These are valid, openable image files with real pixel data — everything from here on works on these actual files.

### Task 1 — Prove the problem: CPU-bound work blocks the main thread
_Mechanism: why CPU-bound work blocks Node's single thread_

**What's happening here:** Resizing an image is pure computation — read pixel numbers, do math, write new pixel numbers — with no natural pause where Node could do anything else. To prove that, we start a heartbeat that logs `tick` every 200ms (standing in for "the server doing other work"), then resize a real sample image synchronously, right on the main thread, and watch what happens to the heartbeat.
Why this matters: until you've seen the freeze happen, "CPU-bound work blocks Node" is just a sentence — this task turns it into something you watched happen on your own screen, which is the whole justification for every task after this one.

Create a file `resize-work.js` and add the following:

Create a file `blocking-demo.js` and add the following:

Run it:

**Why** `node blocking-demo.js` runs the whole file as one live process — the heartbeat and the resize both happen inside that single run. There's no other way to actually watch the freeze happen; reading the code can't show you _when_ the ticks stop, only running it can.

**What you should see:** `tick` printed every 200ms — until the resize starts. Then **the ticks completely stop** for the duration of the resize, resuming only once the "done" line prints. Check `thumbs/photo0-blocking.bmp` afterward with `ls -lh` — a real, much smaller file exists, but producing it froze everything else the whole time.

### Task 2 — Talk to a single worker
_Mechanism:_ _`worker_threads`_ _basics_

**What's happening here:** Before building a pool, prove the basic wiring works: spawn one worker (a separate thread running its own file), send it a message, and get a reply back.
**Why:** start this small: every later task — the pool, the queue, the shutdown logic — is built entirely out of this one send/receive pattern repeated many times, so it's worth confirming it works on its own first.

Create a file `worker-basic.js` and add the following:

Create a file `main-basic.js` and add the following:

Run it:

\*\*Why \*\* You only ever run `main-basic.js` directly — it's the controller, and it spawns `worker-basic.js` itself via `new Worker(...)`. You never type `node worker-basic.js`; that file only makes sense running _inside_ a thread the controller creates.

**What you should see:** Three lines in order: `[main] sending...`, `[worker] received: ping`, `[main] got reply: hello back, I got: ping`. Two separate threads really did talk to each other.

### Task 3 — Move the real resize into a worker
_Mechanism:_ _`worker_threads`_ _fixes the blocking problem_

**What's happening here:** Same heartbeat test as Task 1, same real image, same resize work — but this time it runs _inside_ the worker from Task 2's pattern instead of on the main thread.
**Why:** repeat the exact same test: reusing Task 1's setup, unchanged, is what makes this a real before/after comparison — any difference in the outcome can only be explained by where the work ran, not by anything else changing.

Create a file `worker-resize.js` and add the following:

Create a file `nonblocking-demo.js` and add the following:

Run it:

**Why** Same idea as Task 2 — you run the controller (`nonblocking-demo.js`), and it spawns `worker-resize.js` on its own. Running it is also the only way to actually watch the ticks keep going this time, which is the whole point of the comparison with Task 1.

**What you should see:** The ticks **never stop** — same real file, same resize work as Task 1, but the heartbeat keeps going right through it. `thumbs/photo0-nonblocking.bmp` is written once it's done, same result as Task 1's output, just produced without freezing anything.

### Task 4 — Build the pool: task queue + idle-worker tracking
_Mechanism: thread pools, task queues, idle-worker tracking_

**What's happening here:** Spawning a new worker per job wastes the overhead of thread creation, so instead we build a **pool**: a fixed number of workers, created once and reused across many images. Jobs that arrive while all workers are busy wait in a **queue**. The pool also tracks which workers are **idle** vs busy, so it can hand off the next queued job the moment a worker frees up.
**Why:** a queue and idle-tracking specifically: with 8 real images and only 4 workers, something has to decide who works on what and when — without this bookkeeping, jobs would either get dropped or overload a single worker instead of spreading out evenly.

Create a file `pool.js` and add the following:

Reuse `worker-resize.js` from Task 3 as the pool's worker file. Create a file `pool-demo.js` and add the following:

Run it:

**Why:** `node pool-demo.js` starts the controller, which builds the pool and submits all 8 jobs. `ls -lh thumbs/` is the follow-up check — it confirms the pool actually _produced_ 8 real thumbnail files, not just printed logs claiming it did.

**What you should see:** `[pool] started with 4 workers`, then only **4 jobs picked up immediately** while the rest sit in the queue — visible via the shrinking "still queued" count. As each worker finishes, it grabs the next queued job, until all 8 real images are resized.

### Task 5 — Fast transfer: structured clone vs SharedArrayBuffer
_Mechanism: structured clone (copy) vs_ _`SharedArrayBuffer`_ _(zero-copy transfer)_

**What's happening here:** `postMessage` normally **copies** whatever you send (the "structured clone algorithm") — for a large real image buffer, that copy costs real time. A `SharedArrayBuffer` is different: it's a block of memory **both threads can access at once**, with no copy at all. Let's measure the difference using one of our real 5MB+ sample files.
**Why:** this matters for a thumbnail farm specifically: every job in this pool involves handing image bytes to a worker, so if that handoff itself is slow, it eats into the very speedup the pool is supposed to deliver.

Create a file `echo-worker.js` and add the following:

Create a file `transfer-compare.js` and add the following:

Run it:

**Why** One run of this file does both timings back-to-back, in the same process, on the same real file — which is what makes the two numbers a fair, apples-to-apples comparison instead of two separate, differently-timed runs.

**What you should see:** Two real timings on the same real file — `[shared]` clearly faster than `[copy]`, since one is copying megabytes and the other isn't. (Note: because both threads can read _and write_ a `SharedArrayBuffer` at once, real production code needs `Atomics` to coordinate access safely.)

### Task 6 — Graceful shutdown
_Mechanism: graceful shutdown_

**What's happening here:** Killing worker threads mid-job would lose in-flight work. A graceful shutdown means: stop accepting new jobs, let jobs already running finish, _then_ terminate every worker cleanly.
**Why:** this can't be an afterthought: a pool that never shuts down cleanly will either lose whatever a worker was mid-way through, or leave threads running in the background after your app thinks it's stopped.

Update `pool.js` with the complete class below — it's the same constructor, `submit`, and `_dispatch` from Task 4, plus the new `shutdown` method added at the end:

Create a file `shutdown-demo.js` and add the following:

Run it:

**Why** Running it is what actually triggers the race between "jobs still queued" and "shutdown requested" — the 100ms delay, the rejections, and the in-flight jobs finishing all have to happen live, inside one real run, to see the correct behavior play out in order.

**What you should see:** With 8 real jobs and only 4 workers, shutdown triggers while 4 are queued — those log `[job] rejected: pool shutting down`, while the 4 already in flight are allowed to finish (real thumbnail files appear for those) before `all workers terminated — shutdown complete` prints.

### Task 7 — Benchmark: 1 worker vs N workers
_Mechanism: benchmarking parallel speedup_

**What's happening here:** Prove the whole point with real numbers. Run the same real batch of images through a 1-worker pool and a 4-worker pool, and compare.
**Why:** a benchmark and not just a feeling: everything from Task 1 onward has been building toward one claim — spreading work across threads is faster — and a benchmark is the only way to actually confirm that claim instead of assuming it.

Create a file `benchmark.js` and add the following:

Run it:

**Why** This single run does both the 1-worker batch and the 4-worker batch back-to-back, in the same process, on the same 8 images — keeping conditions identical between the two so the speedup number actually means something.

**What you should see:** Two real millisecond timings on the same real 8-image batch, followed by a speedup factor — expect somewhere close to 3–4x with 4 workers.

### Bonus Task — Swap in `sharp` for a real JPEG
_Mechanism: hand-written pure-JS engine vs a native production library_

**What's happening here:** Our pure-JS engine only understands the simple BMP format. Real apps deal with JPEG/PNG, which need real decoders — that's what the `sharp` library provides. Let's make the resize engine try `sharp` first and fall back to our pure-JS engine automatically.
**Why:** bother with a fallback at all: it mirrors how you'd actually ship this — use the fast, real library where it's available, without leaving the app broken in an environment where it isn't.

**Important caveat:** `sharp` doesn't do its pixel math in JavaScript at all — it hands the work to a native library (`libvips`), which manages its own internal thread pool, separate from `worker_threads`. That means sharp is already avoiding the main thread on its own — so a version of Task 1's "prove the freeze" test using sharp instead of our pure-JS engine likely wouldn't show a freeze at all. That's not a bug — it's a real difference: our hand-written engine teaches the mechanics of blocking and worker\_threads; sharp shows what a production library already handles internally.

Create a file `resize-work-smart.js` and add the following:

Install sharp (fine if it fails — the code above falls back automatically). Sharp's latest release needs Node ≥ 20.9 — if your playground runs Node 18, pin an older version instead:

**Why** `sharp` is a native library (compiled code, not plain JavaScript), so it has to be installed like any npm package before `require('sharp')` can find it. If the install fails or the platform isn't supported, the try/catch in `resize-work-smart.js` falls back to the pure-JS engine instead of crashing. Pinning `@0.33.5` avoids a real issue where the newest sharp release refuses to load on Node 18.

Create a file `make-real-jpeg.js` and add the following:

Run it:

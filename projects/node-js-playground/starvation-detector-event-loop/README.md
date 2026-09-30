# Starvation Detector

**Level:** intermediate  ·  **Playground:** Node JS Playground

▶ **[Launch the playground](https://kodekloud.com/playgrounds/playground-nodejs)** — open it, then copy the files below.

A [`commands.sh`](./commands.sh) with the runnable steps is included.

 (Measuring a Blocked Event Loop)

## Scenario
Your team's login endpoint hashes passwords before checking them. It worked fine in testing. Then a marketing email went out, hundreds of users tried to log in at once, and something strange happened: the load balancer marked the server as **dead**, because its tiny `/health` check, which does nothing but reply `OK`, suddenly took seconds to answer. Nothing was wrong with `/health` itself. Your lead wants you to reproduce the problem on purpose, **measure** exactly how bad it is with real numbers, find the cause from inside the server, fix it, and then prove the fix with the exact same measurement.

## What you'll build
A small `http` server with a fast `/health` route and a deliberately blocking `/hash` route that hashes a password with `crypto.pbkdf2Sync` (the same kind of slow, CPU-heavy work as `bcrypt`). You'll write your own load tester that hammers `/hash` while timing every `/health` request and reporting **p50 / p99 latency** and **throughput**. You'll add `perf_hooks.monitorEventLoopDelay()` so the server reports its own blocked time, then fix the route with the async `crypto.pbkdf2` and re-run the exact same test to prove the difference. You'll finish by looking at where the work went: libuv's thread pool.

## Learning objectives
By the end you will be able to:
- Explain why synchronous, CPU-heavy code blocks **every** request on a Node server, not just its own.
- Explain what **starvation** means: a fast request stuck waiting behind slow ones.
- Explain why **p99** latency reveals problems that an average hides, and compute it yourself.
- Explain why a blocked event loop puts a hard ceiling on **throughput** for the whole server.
- Use `perf_hooks.performance.now()` to time requests from the outside, and `monitorEventLoopDelay()` to measure blocking from the inside.
- Fix blocking work by moving it off the main thread with async `crypto` APIs.
- Prove a performance fix with a fair before/after measurement instead of a feeling.

## Prerequisites
- Playground: **Node.js** (open it before starting)
- Node.js available in the sandbox (`node -v` to confirm; `perf_hooks.monitorEventLoopDelay` needs Node 11.10+, and nothing in this lab needs an `npm install`)

## Why every server task needs two terminals
A server and a load tester must be **two separate processes**. If the load tester lived inside the server, it would freeze together with the server, and its stopwatch would stop ticking at exactly the moment you want it to measure. Running it in its own process means its clock keeps running honestly while the server is stuck.

So from Task 1 onward:

1. **Terminal 1** runs the server (`node server-xyz.js`) and stays open, showing the server's own logs.
2. **Terminal 2** sends requests (`curl` or `node loadtest.js`).
3. Before starting a **different** server file, stop the old one with **Ctrl+C** in Terminal 1. Every server uses port **3000** (the playground's editor already uses 8080), and only one program can hold a port at a time. If you forget, the new server prints `port 3000 is already in use` and exits.

Open a second terminal with the **+** (new terminal) button in the playground's terminal panel. If your playground only gives you one terminal, run the server in the background instead: `node server-xyz.js &`, run your tests, then stop it with `kill %1`.

## Steps

### Task 0 — Calibrate the slow work
*Mechanism: none yet — this makes sure the "slow" route is slow enough to see clearly on your machine.*

**What's happening here:** Password hashing is **deliberately** slow: it repeats a scrambling step many times so attackers can't guess millions of passwords per second. We use Node's built-in `crypto.pbkdf2Sync` for this (the same kind of work `bcrypt` does, with nothing to install). How slow one hash is depends on the CPU, so we measure it here and tune the number of repetitions (`ITERATIONS`) until one hash takes roughly 100–300ms.
**Why:** every later task compares numbers. If one hash only took 5ms, the problem would be too small to see; if it took 5 seconds, every test would crawl. Calibrating once, in one shared file, means every server in this lab does exactly the same amount of work, so every before/after comparison is fair.

Create a file `slow-hash.js` and add the following:
```javascript
// slow-hash.js
// One shared setting for "how heavy is one password hash?" Every server in this lab imports it, so the work is identical in every before/after test.
const crypto = require('crypto');

const ITERATIONS = 200000; // raise or lower this in Task 0 until one hash takes ~100-300ms
const KEY_LENGTH = 64;
const DIGEST = 'sha512';
const SALT = 'fixed-salt-for-this-lab'; // real apps use a random salt per user

function hashSync(password) {
  return crypto.pbkdf2Sync(password, SALT, ITERATIONS, KEY_LENGTH, DIGEST).toString('hex');
}

function hashAsync(password, callback) {
  crypto.pbkdf2(password, SALT, ITERATIONS, KEY_LENGTH, DIGEST, (err, key) => {
    if (err) return callback(err);
    callback(null, key.toString('hex'));
  });
}

module.exports = { hashSync, hashAsync, ITERATIONS };
```

Create a file `calibrate.js` and add the following:

```javascript
// calibrate.js
const { performance } = require('perf_hooks');
const { hashSync, ITERATIONS } = require('./slow-hash');

hashSync('warm-up'); // the first call is a little slower; don't count it

const runs = 5;
const start = performance.now();
for (let i = 0; i < runs; i++) hashSync(`password-${i}`);
const perHash = (performance.now() - start) / runs;

console.log(`ITERATIONS = ${ITERATIONS}`);
console.log(`one hash takes ~${perHash.toFixed(0)}ms on this machine`);

if (perHash < 100) console.log('-> a bit fast: increase ITERATIONS in slow-hash.js and run again');
else if (perHash > 300) console.log('-> a bit slow: decrease ITERATIONS in slow-hash.js and run again');
else console.log('-> good: this is heavy enough to show the problem clearly');
```

Run it:

```bash
node calibrate.js
```

**Why** this measures real hashing time on _this_ sandbox's real CPU, not a number from someone else's laptop. If it tells you to change `ITERATIONS`, edit `slow-hash.js` and run it again until it says `good`.

**What you should see:** something like `one hash takes ~115ms on this machine` followed by `-> good`. Write this number down; you'll use it in Task 4.

### Task 1 — Start with a healthy server
_Mechanism: a normal, non-blocking HTTP server as the baseline_

**What's happening here:** Before breaking anything, confirm what "healthy" looks like: a server with one route, `/health`, that replies `OK` immediately. Load balancers and monitoring tools call routes like this constantly to ask "are you alive?"
**Why:** you can't recognize a problem without knowing what normal looks like. This gives you the "normal" timing that every later number gets compared against.

Create a file `server-healthy.js` and add the following:

```javascript
// server-healthy.js
const http = require('http');

const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('OK\n');
    return;
  }
  res.writeHead(404, { 'Content-Type': 'text/plain' });
  res.end('not found\n');
});

server.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    console.error('port 3000 is already in use: stop the old server (Ctrl+C in its terminal) and try again');
  } else {
    console.error('server error:', err.message);
  }
  process.exit(1);
});

server.listen(3000, () => console.log('healthy server on http://localhost:3000'));
```

**Terminal 1:**

```bash
node server-healthy.js
```

**Terminal 2:**

```bash
curl -s -o /dev/null -w 'health: %{time_total}s\n' localhost:3000/health
```

**Why** `-o /dev/null` throws away the reply body and `-w '...%{time_total}...'` prints how long the whole request took, in seconds. That turns `curl` into a quick stopwatch, so you're looking at a real timing instead of just "it answered."

**What you should see:** something like `health: 0.004s`, a few milliseconds. That's what a healthy route costs. Stop the server with **Ctrl+C** before the next task.

### Task 2 — Add a deliberately blocking route
_Mechanism: synchronous CPU work blocks the single main thread_

**What's happening here:** Now we add `/hash`, which calls `pbkdf2Sync`. The word **Sync** means "do this right now, on the main thread, and don't return until it's finished." Node runs all your JavaScript on **one main thread**, so while that hash is running, Node can't even _look_ at any other request, including `/health`.
**Why:** the `/health` code doesn't change at all in this task. If `/health` gets slower, the only possible explanation is the new route next to it, which is exactly the claim this lab is testing.

Create a file `server-blocking.js` and add the following:

```javascript
// server-blocking.js
const http = require('http');
const { hashSync } = require('./slow-hash');

const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('OK\n');
    return;
  }

  if (req.url === '/hash') {
    // pbkdf2Sync runs ON the main thread. Until it returns, Node cannot accept, read, or answer ANY other request — including /health.
    const hash = hashSync('hunter2');
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end(`hashed: ${hash.slice(0, 16)}...\n`);
    return;
  }

  res.writeHead(404, { 'Content-Type': 'text/plain' });
  res.end('not found\n');
});

server.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    console.error('port 3000 is already in use: stop the old server (Ctrl+C in its terminal) and try again');
  } else {
    console.error('server error:', err.message);
  }
  process.exit(1);
});

server.listen(3000, () => console.log('BLOCKING server on http://localhost:3000'));
```

**Terminal 1:**

```bash
node server-blocking.js
```

**Terminal 2** — first time each route on its own, then fire `/hash` and, a moment later, `/health`:

```bash
curl -s -o /dev/null -w 'health alone: %{time_total}s\n' localhost:3000/health
curl -s -o /dev/null -w 'hash alone:   %{time_total}s\n' localhost:3000/hash
curl -s -o /dev/null -w 'hash: %{time_total}s\n' localhost:3000/hash & sleep 0.02; curl -s -o /dev/null -w 'health during hash: %{time_total}s\n' localhost:3000/health; wait
```

**Why** the `&` at the end of the first `curl` in the last line sends it to the background, so the `/health` request goes out 20ms later **while** the hash is still running. `wait` just waits for the background request to finish so its line prints before your prompt comes back.

**What you should see:** `health alone` takes a few milliseconds, and `hash alone` takes about your Task 0 number. But `health during hash` takes about **as long as the hash**, not a few milliseconds. `/health` did no extra work; it simply waited in line. That's **starvation** in its smallest form. Stop the server with **Ctrl+C**.

### Task 3 — Build a load tester and measure the baseline
_Mechanism: latency percentiles (p50 / p99) measured with_ _`perf_hooks.performance.now()`_

**What's happening here:** One `curl` is a single story; we need statistics. The load tester sends a `/health` request every 50ms for 5 seconds and times each one with `performance.now()`, a high-precision stopwatch. Then it sorts all the timings and reports:
*   **p50** (the median): half the requests were faster than this. This is the "typical" user.
*   **p99**: 99% of requests were faster than this. This is the **unlucky** user.
*   **max**: the single slowest request.

It can also **hammer** a route: with `--hammer`, 8 fake clients call `/hash` over and over, as fast as the server answers, like a crowd all logging in at once. It counts how many hashes finish, which is the route's **throughput** (requests per second).
**Why:** p99 and not the average: if 99 requests take 1ms and one takes 2 seconds, the average looks like a harmless ~21ms, but a real person waited 2 seconds. Percentiles show the unlucky users that averages hide, and those are exactly the users a starved server hurts.

Create a file `loadtest.js` and add the following:

```javascript
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
```

**Terminal 1:**

```bash
node server-healthy.js
```

**Terminal 2:**

```bash
node loadtest.js
```

**Why** we measure the **healthy** server first with no hammering: this is the "before anything is wrong" number. Every later result only means something next to it.

**What you should see:** about 100 requests, with `p50` around 1ms and `p99` in the low milliseconds (small spikes to ~10–20ms are normal in a shared sandbox). Stop the server with **Ctrl+C**.

### Task 4 — Hammer the blocking route and watch `/health` starve
_Mechanism: event loop starvation, and the throughput ceiling it creates_

**What's happening here:** Same load tester, same `/health` requests, but now against the blocking server while 8 clients hammer `/hash`. Each hash holds the main thread for ~100ms+, several are always waiting, and every `/health` request has to wait behind all of them.
**Why:** this is the real-world situation from the scenario (a login rush) turned into numbers you can compare with Task 3, using the exact same test.

**Terminal 1:**

```bash
node server-blocking.js
```

**Terminal 2:**

```bash
node loadtest.js --hammer
```

**Why** `--hammer` keeps `/hash` constantly busy while the tester keeps timing `/health` exactly as in Task 3. Only one thing changed between the two runs: the blocking route is under load.

**What you should see:** `/health` p50 and p99 jump from about **1ms** to **hundreds or even thousands of milliseconds**. Nothing about `/health` changed; it's starving behind the hashes.

Now look at `/hash throughput`. Compare it with your Task 0 number: `1000 ÷ (ms per hash)`. With ~115ms per hash that's about **8–9 requests per second**, and your result should be close to it. That's the **ceiling for the whole server**: one thread, one hash at a time, no matter how many CPU cores the machine has or how many clients are waiting. This is why blocking the loop kills throughput. Leave the server running for a moment and run `nproc` in Terminal 2 to see how many cores the sandbox actually has; all but one sat idle during this test. Stop the server with **Ctrl+C**.

### Task 5 — See the blocking from inside the server
_Mechanism:_ _`perf_hooks.monitorEventLoopDelay()`_

**What's happening here:** The load tester shows what **users** feel. Now we want the server to report **why**. `monitorEventLoopDelay()` works like an alarm clock that is set to ring every 10ms. If the main thread is free, it rings on time. If the main thread is stuck in a hash, the alarm can't ring until the hash finishes, so it rings late, and Node records **how late**. Every second, we print the p50, p99, and max of those delays.
**Why:** in production you usually can't run a load tester on demand, but a server can always watch itself. This is the same signal that monitoring tools use to alert on "event loop lag."

Two details before you read the numbers:
*   The histogram stores **nanoseconds** (billionths of a second), so the code divides by `1e6` to show milliseconds.
*   Because the alarm is set every **10ms**, a healthy reading is about **10ms**, not 0. Anything well above that is time the loop was blocked.

Create a file `loop-monitor.js` and add the following:

```javascript
// loop-monitor.js
const { monitorEventLoopDelay } = require('perf_hooks');

function startLoopMonitor() {
  // Node checks the loop every 10ms and records how LATE each check was.
  const histogram = monitorEventLoopDelay({ resolution: 10 });
  histogram.enable();

  const toMs = (ns) => (ns / 1e6).toFixed(1); // the histogram stores nanoseconds

  setInterval(() => {
    console.log(
      `[loop] delay p50=${toMs(histogram.percentile(50))}ms ` +
      `p99=${toMs(histogram.percentile(99))}ms ` +
      `max=${toMs(histogram.max)}ms`
    );
    histogram.reset(); // start fresh, so each line covers only the last second
  }, 1000);
}

module.exports = { startLoopMonitor };
```

Create a file `server-monitored.js` (the same blocking server, now with the monitor) and add the following:

```javascript
// server-monitored.js
const http = require('http');
const { hashSync } = require('./slow-hash');
const { startLoopMonitor } = require('./loop-monitor');

const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('OK\n');
    return;
  }

  if (req.url === '/hash') {
    const hash = hashSync('hunter2'); // still blocking — we're only adding eyes, not fixing yet
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end(`hashed: ${hash.slice(0, 16)}...\n`);
    return;
  }

  res.writeHead(404, { 'Content-Type': 'text/plain' });
  res.end('not found\n');
});

server.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    console.error('port 3000 is already in use: stop the old server (Ctrl+C in its terminal) and try again');
  } else {
    console.error('server error:', err.message);
  }
  process.exit(1);
});

server.listen(3000, () => {
  console.log('MONITORED (still blocking) server on http://localhost:3000');
  startLoopMonitor();
});
```

**Terminal 1:**

```bash
node server-monitored.js
```

Watch a few `[loop]` lines print while the server is idle.

**Terminal 2:**

```bash
node loadtest.js --hammer
```

**Why** keeping Terminal 1 visible matters here: the load tester's numbers and the server's own `[loop]` lines are two views of the same moment, one from outside and one from inside.

**What you should see:** while idle, `[loop] delay p50=10.1ms p99=10.4ms`, which is normal. During the hammer, `p99` and `max` jump to **hundreds of milliseconds**. You'll also notice **fewer** **`[loop]`** **lines than seconds** go by: the reporter's own `setInterval` is stuck in the same line as everything else. When the test ends, the numbers drop back to ~10ms. Stop the server with **Ctrl+C**.

### Task 6 — The fix: move the hash off the main thread
_Mechanism: async_ _`crypto.pbkdf2`_ _runs on libuv's thread pool_

**What's happening here:** Node has a small team of **background threads** (libuv's thread pool, 4 threads by default). Some built-in functions, including `crypto.pbkdf2` without `Sync`, send their heavy work to that team and call you back when it's done. The main thread hands the job off and is instantly free to answer `/health`. The hash itself is **identical**: same function family, same settings from `slow-hash.js`. Only _where_ it runs has changed.
**Why:** re-run the exact same test, unchanged: same load tester, same 8 clients, same hash cost. Any difference in the numbers can only come from where the work runs, which is what makes this real proof and not a guess.

Create a file `server-fixed.js` and add the following:

```javascript
// server-fixed.js
const http = require('http');
const { hashAsync } = require('./slow-hash');
const { startLoopMonitor } = require('./loop-monitor');

const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('OK\n');
    return;
  }

  if (req.url === '/hash') {
    // Same hash, same settings — but crypto.pbkdf2 (no "Sync") runs on libuv's background thread pool. The main thread is free the moment this line returns.
    hashAsync('hunter2', (err, hash) => {
      if (err) {
        console.error('hash failed:', err.message);
        res.writeHead(500, { 'Content-Type': 'text/plain' });
        res.end('hash failed\n');
        return;
      }
      res.writeHead(200, { 'Content-Type': 'text/plain' });
      res.end(`hashed: ${hash.slice(0, 16)}...\n`);
    });
    return;
  }

  res.writeHead(404, { 'Content-Type': 'text/plain' });
  res.end('not found\n');
});

server.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    console.error('port 3000 is already in use: stop the old server (Ctrl+C in its terminal) and try again');
  } else {
    console.error('server error:', err.message);
  }
  process.exit(1);
});

server.listen(3000, () => {
  console.log('FIXED (non-blocking) server on http://localhost:3000');
  startLoopMonitor();
});
```

**Terminal 1:**

```bash
node server-fixed.js
```

**Terminal 2:**

```bash
node loadtest.js --hammer
```

**Why** you're running exactly the command from Tasks 4 and 5 again, so you're comparing like with like.

**What you should see:** `/health` p50 goes back to about **1ms** and p99 to the **low tens of milliseconds** at most, even though `/hash` is being hammered just as hard. In Terminal 1, the `[loop]` lines stay near **10ms** and one prints every second. Stop the server with **Ctrl+C**.

### Task 7 — Where did the work go? The thread pool
_Mechanism: libuv thread pool size (__`UV_THREADPOOL_SIZE`__) and CPU cores_

**What's happening here:** The fix didn't make hashing free; it moved it to the 4 background threads. You can change how many threads there are with the `UV_THREADPOOL_SIZE` environment variable. We'll run the fixed server with **1** background thread and compare it with the default **4**.
**Why:** this shows the difference between the two problems. The thread pool size decides how fast `/hash` itself can go. The main thread being free decides whether `/health` suffers. Moving the work fixed the second problem; how much it improves the first depends on your CPU.

First check how many CPU cores the sandbox has:

```bash
nproc
```

**Terminal 1** — start with one background thread:

```bash
UV_THREADPOOL_SIZE=1 node server-fixed.js
```

**Terminal 2:**

```bash
node loadtest.js --hammer
```

Then stop the server (**Ctrl+C**), start it again with the default of 4 (`node server-fixed.js`), and run the same load test.
**Why** `UV_THREADPOOL_SIZE=1` in front of `node` sets that variable for this one run only, so you don't have to change any code to compare the two settings.

**What you should see:** in **both** runs, `/health` stays fast; that's the main fix, and it holds either way. The `/hash` throughput is where they differ:
*   With **several cores**, 4 threads finish noticeably more hashes per second than 1 thread (up to ~4x), which is something the blocking server could **never** do.
*   With **1 core** (`nproc` printed `1`), both runs finish about the same number of hashes: more threads can't create more CPU. That's normal, and it's a real lesson too: the fix protects the rest of the server, but it can't make a single core do more math.

Stop the server with **Ctrl+C**.

## Validation
Run through each check and confirm the actual behavior, not just that the script ran without errors:

- [ ] Task 0: `calibrate.js` reports one hash taking roughly 100–300ms and prints `good`.
- [ ] Task 1: `curl` times `/health` on the healthy server at a few milliseconds.
- [ ] Task 2: `health during hash` takes about as long as one hash, while `health alone` takes a few milliseconds.
- [ ] Task 3: the baseline load test on the healthy server shows `/health` p50 around 1ms and a low p99.
- [ ] Task 4: with `--hammer` on the blocking server, `/health` p99 jumps to hundreds or thousands of ms, and `/hash` throughput is close to `1000 ÷ (ms per hash)`.
- [ ] Task 5: `[loop]` lines read ~10ms when idle, jump to hundreds of ms during the hammer, and print less often than once per second while blocked.
- [ ] Task 6: the same `--hammer` test against `server-fixed.js` keeps `/health` p99 low and `[loop]` near 10ms; your before/after table shows the difference.
- [ ] Task 7: `/health` stays fast with both `UV_THREADPOOL_SIZE=1` and the default; you can explain why `/hash` throughput does or doesn't change based on `nproc`.

## References & further learning
*   Node.js guide: Don't Block the Event Loop (or the Worker Pool): [https://nodejs.org/en/learn/asynchronous-work/dont-block-the-event-loop](https://nodejs.org/en/learn/asynchronous-work/dont-block-the-event-loop)
*   Node.js docs: `perf_hooks.monitorEventLoopDelay()`: [https://nodejs.org/api/perf\_hooks.html#perf\_hooksmonitoreventloopdelayoptions](https://nodejs.org/api/perf_hooks.html#perf_hooksmonitoreventloopdelayoptions)
*   Node.js docs: `performance.now()`: [https://nodejs.org/api/perf\_hooks.html#performancenow](https://nodejs.org/api/perf_hooks.html#performancenow)
*   Node.js docs: `crypto.pbkdf2()` and `crypto.pbkdf2Sync()`: [https://nodejs.org/api/crypto.html#cryptopbkdf2password-salt-iterations-keylen-digest-callback](https://nodejs.org/api/crypto.html#cryptopbkdf2password-salt-iterations-keylen-digest-callback)
*   Node.js docs: `UV_THREADPOOL_SIZE`: [https://nodejs.org/api/cli.html#uv\_threadpool\_sizesize](https://nodejs.org/api/cli.html#uv_threadpool_sizesize)
*   Node.js docs: `http` module: [https://nodejs.org/api/http.html](https://nodejs.org/api/http.html)

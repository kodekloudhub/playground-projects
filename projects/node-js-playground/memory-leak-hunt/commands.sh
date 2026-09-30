#!/usr/bin/env bash
set -euo pipefail

## Steps

### Task 0 — Build the server (with both bugs already inside it)
_Mechanism: none yet — this just gives every later task a real, running target._

**What's happening here:** Below is a small HTTP server with four endpoints: `/compute` (caches an "expensive" result per id), `/subscribe` (attaches something to a shared, long-lived emitter), `/stats` (reports live memory and internal counts, forcing a GC first), and `/snapshot` (dumps a heap snapshot file, also forcing GC first). Two of these endpoints are quietly buggy — you'll spend the next few tasks proving exactly how and why, not just taking it on faith.

Create a file `leaky-server.js` and add the following:

Create a file `load-client.js` — a small helper every later task uses to send real, repeatable traffic:

**How to read the command you'll type:** every time you call this script, it looks like `node load-client.js <mode> <count>` — two extra words after the filename:
*   `<mode>` — which endpoint to hit, repeatedly: `compute-unique`, `compute-same`, or `subscribe`.
*   `<count>` — how many times to hit it, e.g. `300`.

So `node load-client.js subscribe 300` means: call `/subscribe` 300 times in a row. `node load-client.js compute-unique 500` means: call `/compute` 500 times, each with a brand-new id. Node hands these two words to the script as text (via `process.argv`), and `parseInt(countArg, 10)` converts `"300"` into the actual number `300` so the loop can count with it. Typing a mode this script doesn't recognize (a typo, say) is the only thing that errors — a real mode followed by a number is exactly how this script is meant to be run, every time.

**Terminal 1** — start the server and leave it running here for the rest of this task (and Tasks 1–3):

**Terminal 2** — open a second terminal (keep Terminal 1 open and running) and check it's alive:

**Why** Starting with `--expose-gc` is what makes `global.gc()` inside `forceGC()` actually work instead of silently warning — every later measurement in this lab depends on that flag being present from the start. The `curl` confirms the server is alive and gives you the honest starting point — a small `heapUsedMB`, `cacheSize: 0`, `listenerCount: 0` — before anything has had a chance to leak. From here on, **Terminal 1 is always "run the server"** and **Terminal 2 is always "run commands against it"** — every later task follows this same two-terminal split.

**What you should see:** A JSON object with small numbers across the board. This is your true baseline — every later task compares back to something close to this.

**Note on** **`load-client.js`****:** you're not running it yet — it just sits there for now. It only makes sense once a server is already listening for it to hit, so Task 1 is where you'll actually invoke it for the first time.

### Task 1 — Prove leak #1: the unbounded cache

**What's happening here:** `/compute` caches by id so identical requests don't redo work — a completely reasonable instinct. The question is what happens to memory when the _same_ id keeps coming back versus when a _stream of new_ ids keeps coming in. We'll test both, using `/stats` (which forces a GC before reporting) so there's no ambiguity about whether growth is real or just the collector being slow.

**Terminal 1** should still be running `leaky-server.js` from Task 0 — leave it as is. **Terminal 2** — run this sequence, checking `/stats` between each step:

**Why** Two `compute-unique` batches back to back, both followed by a _forced-GC_ `/stats` call, is the whole proof: if the first batch's memory came back down on its own, the second batch's growth would start from the same low baseline. Instead you'll see the increase carry over and compound — proof that GC had every chance to reclaim this memory and genuinely could not, because something is still holding onto it.

**What you should see:** After `compute-same`, `cacheSize` barely moves (it was already cached after the very first hit) and `heapUsedMB` stays essentially flat — repeating identical work is memory-neutral. After each `compute-unique` batch, `cacheSize` jumps by exactly 300 and `heapUsedMB` climbs by roughly 300 × 50KB ≈ 15MB, **even though** **`/stats`** **just forced a garbage collection immediately before reporting**. That last detail is what makes this a leak rather than normal, temporary memory use.

### Task 2 — Prove leak #2: the stray event listener

**What's happening here:** `/subscribe` attaches a listener to `sharedEmitter` on every request. Node's `EventEmitter` has a built-in safety net for exactly this situation: once a single event name passes 10 listeners, it prints a warning to the console on its own, without you writing any detection code at all.

**Terminal 1** — stop the server and restart it fresh, so listener counts start at zero:

**Terminal 2** — run:

**Why** Restarting first matters here specifically because `sharedEmitter` is created once at module load — without a fresh process, leftover listeners from an earlier task would make this count meaningless. Watch **Terminal 1** (the server's own output), not just the `curl` replies in Terminal 2 — that's where the warning prints.

**What you should see:** Partway through the first `load-client.js subscribe 20` run, the server's terminal prints something like `MaxListenersExceededWarning: Possible EventEmitter memory leak detected. 11 tick listeners added...` — Node telling you, unprompted, that something looks wrong. `/stats` afterward shows `listenerCount: 20`, and after the batch of 500 it shows `listenerCount: 520` — a number that only ever goes up, no matter how long you wait or how many times `/stats` forces a GC.

### Task 3 — Take heap snapshots and isolate each leak

**What's happening here:** A single heap snapshot is a full map of every live object and what's referencing it. On its own it's just a big pile of data — the real technique is taking **two** snapshots around a controlled bit of traffic and diffing them. To make the diff mean something, you isolate one variable at a time: first prove "neutral" traffic really is neutral, then test each leak separately against that same baseline method.

**Terminal 1** — restart the server fresh (`Ctrl+C`, then `node --expose-gc leaky-server.js`). **Terminal 2** — run this exact sequence, checking each `curl` reply for the snapshot's filename:

**Why** `compute-same` repeats one identical key, so this diff should show **almost nothing new** — it's your control group, proving your methodology (forced GC, then snapshot) doesn't produce false alarms on its own.

**Terminal 1** — restart the server again (fresh state). **Terminal 2** — isolate leak #1:

**Terminal 1** — restart once more. **Terminal 2** — isolate leak #2:

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

2. Press `Ctrl+Shift+P`, type **"Attach to Node Process"**, and pick the `leaky-server.js` one from the list.
3. Click the **Debug Console** tab (next to Terminal) and type:

4. It prints the file path back — a real snapshot file now sits in `snapshots/`, made the same way as Task 3's, just triggered directly instead of through `/snapshot`. Download and load it in Chrome exactly as before to look inside it.

### Task 5 — Reveal the fix and prove it with the same tests

**What's happening here:** Time to look at the corrected version. It fixes leak #1 by capping the cache at a fixed size and evicting the oldest entry once that limit is hit (a simple LRU), and fixes leak #2 by removing each request's listener the moment that request's response finishes — so nothing outlives the request that created it.

Create a file `fixed-server.js` and add the following:

**Terminal 1** — stop `leaky-server.js` (`Ctrl+C`), then start the fixed one in its place:

**Terminal 2** — run the exact same recipe from Task 1 and Task 2, now against the fixed server:

**Why re-run the identical recipe** Using the exact same test as Tasks 1 and 2, unchanged, is what makes this a legitimate before/after comparison — any difference in outcome can only be explained by the code, not by a different or easier test.

**What you should see:** After both `compute-unique` batches (600 requests total, all unique ids), `cacheSize` never exceeds `50` — it grows to the cap and then holds there. `heapUsedMB` grows only up to a point and then **plateaus** instead of climbing forever. After the `subscribe` batch of 300, `listenerCount` sits at `0` (or a very small transient number) instead of `300` — because each listener was removed the instant its own request finished.

### Bonus Task — Watch the trend live, leaky vs fixed

**What's happening here:** Numbers at two points in time are convincing; watching the trend unfold in real time is more convincing still. This script polls `/stats` once a second and prints a simple text bar for `heapUsedMB`, so you can literally watch one server's memory climb and the other plateau.

Create a file `memory-trend.js` and add the following:

**Terminal 1** — run the **leaky** server first:

**Terminal 2** — start the trend logger in the background, then drive traffic in the same terminal:

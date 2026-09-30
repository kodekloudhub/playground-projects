#!/usr/bin/env bash
set -euo pipefail

Run it:

**Why** `cat data.txt` proves the file genuinely exists on disk with real content, so every later `fs.readFile` call in this lab is reading actual bytes from actual I/O — not something that only _looks_ async.

### Task 1 — Observe the raw baseline order
_Mechanism: registering all five primitives at once, with no categorization yet_

**What's happening here:** Before learning any rules, just look at what actually happens. Register all five async primitives back-to-back and log each one as it fires, in whatever order Node decides.

Create a file `observe-baseline.js` and add the following:

Run it:

**Why** Running this — instead of just reading the code and guessing — is the entire point of the lab: your prediction and Node's real behavior are two separate things, and only an actual run tells you which one is right.

**What you should see:** `sync start` and `sync end` always print first and in that order — nothing async ever interrupts already-running synchronous code. After that, `process.nextTick` and `promise` reliably print before `setTimeout`/`setImmediate`/`fs.readFile`. The relative order of the last three can vary slightly run to run — that variability is exactly what Task 3 explains.

### Task 2 — The microtask battle: `nextTick` vs. `Promise`
_Mechanism: microtask queue priority_

**What's happening here:** Both `process.nextTick` and `Promise.then()` are "microtasks" — they run before the loop advances to any phase — but they are two _separate_ queues, and `process.nextTick`'s queue always drains completely first.

Create a file `microtask-battle.js` and add the following:

Run it:

**Why** Interleaving two `nextTick`s with two promises, instead of just one of each, proves this isn't "nextTick runs once before a promise" — it proves the **entire** **`nextTick`** **queue** empties before the **entire promise queue** even starts, regardless of registration order.

**What you should see:** `sync`, then `nextTick A`, `nextTick B` (both, in order), then `promise A`, `promise B` (both, in order), and only then `timer` — proving both microtask queues fully drain before the timers phase even begins.

### Task 3 — `setTimeout(0)` vs. `setImmediate`: the ambiguous case
_Mechanism: timers phase vs. check phase, and how poll-phase context removes the ambiguity_

**What's happening here:** At the top level of a script, Node hasn't necessarily entered the poll phase yet, so whether the timers phase or the check phase runs first genuinely depends on process startup timing — it's not random, but it's not something your code controls either. Inside a real I/O callback, though, you're _already_ past the poll phase in this loop iteration, so the check phase (immediate) is guaranteed to run before timers gets another turn.

Create a file `timeout-vs-immediate.js` and add the following:

Run it a few times in a row:

**Why** running it multiple times, not once, is what actually proves the top-level case is unreliable — a single run could get lucky and look deterministic when it isn't.

**What you should see:** the `[top-level]` pair may print in either order across runs (or consistently favor one order on your particular machine — either is normal). The `[inside I/O]` pair, however, should reliably print `setImmediate` before `setTimeout` on every single run, because it's already inside the poll phase when it schedules both.

### Task 4 — Build a reusable phase-capture module
_Mechanism: turning ad-hoc_ _`console.log`__s into a real, ordered data structure_

**What's happening here:** Every task so far just printed to the console. To build a CLI that can actually _diff_ a prediction against reality, we need the real firing order captured as an array we can compare — not just text scrolling past.

Create a file `phase-logger.js` and add the following:

Create a file `demo-logger.js` and add the following:

Run it:

**Why** `remaining` counting down to `0` before resolving is what guarantees the promise returned by `runAndCapture()` only settles once all five callbacks have genuinely fired — not after some arbitrary fixed delay that might be too short or wastefully too long.

**What you should see:** a single array of exactly 5 labels, in the real order Node fired them — this is the same information Task 1 showed you as scattered log lines, now as one structured result the rest of the CLI can actually use.

### Task 5 — Ask for a prediction first
_Mechanism:_ _`readline`_ _for interactive CLI input_

**What's happening here:** The whole exercise only works if the guess happens _before_ the run. This task builds the prompt that captures that guess as an array, in the same shape as `runAndCapture()`'s output, so the two can be compared later.

Create a file `predict.js` and add the following:

Create a file `demo-predict.js` and add the following:

Run it and try typing something invalid first, then a real guess:

**Why** validating here — not later in the diff — matters because an unvalidated guess would just silently compare as "wrong" against every position in Task 7, telling you nothing about _why_ it was wrong. Catching it at the prompt means every prediction that reaches the diff step is a genuine, complete guess, so a ❌ in Task 7 always means "you mispredicted the order," never "you mistyped a label." Closing `rl` immediately after a _valid_ answer still matters for the same reason as before — an open `readline` interface keeps the process alive waiting for more input.

**What you should see:** typing `incorrect word` gets rejected with `Not a real label: "". Valid labels are: ...` and re-prompts you; typing only 2 or 3 labels gets rejected with a count mismatch; only a complete, valid 5-label guess is accepted and echoed back as `you predicted: [...]`.

### Task 6 — Wire prediction + run together
_Mechanism: combining Tasks 4 and 5 into one flow_

**What's happening here:** This is the first point where the CLI actually feels like the "time machine" — ask for a guess, then reveal what really happened, side by side.

Create a file `time-machine.js` and add the following:

Run it and type a guess when prompted (any order of the 5 labels, comma-separated):

**Why** printing `predicted` and `actual` as two full arrays, rather than just saying right/wrong, is what Task 7's diff step needs as its raw input — you can't grade a guess you haven't recorded in a comparable shape.

**What you should see:** your typed prediction echoed back exactly as you typed it, followed by the real order from Task 4 — almost certainly different from your guess in at least one position, which is exactly the gap the next task will make visible.

### Task 7 — The diff: score the prediction
_Mechanism: position-by-position array comparison_

**What's happening here:** A simple, required diff — no fuzzy matching needed, since both arrays are always the same 5 fixed labels in some order. Walk both arrays index by index and mark each position correct or not.

Create a file `diff.js` and add the following:

Update `time-machine.js` to use it — add this to the bottom of the `async` block, after the two `console.log` lines:

Run it again with a real guess:

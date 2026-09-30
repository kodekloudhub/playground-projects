# Event Loop Time Machine (Predict → Run → Diff CLI)

**Level:** intermediate  ·  **Playground:** Node JS Playground

▶ **[Launch the playground](https://kodekloud.com/playgrounds/playground-nodejs)** — open it, then copy the files below.

A [`commands.sh`](./commands.sh) with the runnable steps is included.

# Event Loop Time Machine

```markdown
---
# ─── Metadata (read by the playground for listing & filtering) ───
id: event-loop-time-machine
title: "Event Loop Time Machine (Predict → Run → Diff CLI)"
playground: Node.js
playground_link: https://kodekloud.com/playgrounds/playground-nodejs
difficulty: intermediate
estimated_minutes: 90
tags:
  - nodejs
  - javascript
  - event-loop
  - microtasks
  - macrotasks
  - asynchronous
  - timers
  - cli
skills:
  - event loop phases
  - microtask queue vs macrotask queue
  - process.nextTick priority
  - promise microtasks
  - setTimeout vs setImmediate ordering
  - building a predict/run/diff CLI harness
prerequisites:
  - Basic JavaScript syntax (functions, callbacks)
  - Comfortable with Promises and `async`/`await`
  - No prior knowledge of event loop internals required
---

# Event Loop Time Machine (Predict → Run → Diff CLI)

## Scenario
A teammate shipped a bug last sprint caused by assuming `setTimeout(fn, 0)` always runs before a `Promise.then()`. It doesn't — and the fix took an hour because nobody on the team could actually explain, with confidence, what order Node runs things in. Your lead wants a tool that forces the real intuition to form: register a handful of async callbacks, **predict** the firing order out loud before running anything, then let the CLI **run** it for real and **diff** your guess against reality, position by position.

## What you'll build
A CLI that registers five classic async primitives — `setTimeout`, `setImmediate`, `process.nextTick`, a resolved `Promise`, and a real `fs.readFile` — prompts you to type your predicted firing order first, then runs everything for real, captures the actual order, and prints a position-by-position diff with a score.

## Learning objectives
By the end you will be able to:
- Explain the difference between the **microtask queues** (`process.nextTick`, then Promise callbacks) and the **macrotask phases** (timers, poll, check) that make up the Node event loop.
- Explain why `process.nextTick` always drains before Promise microtasks, and why both always drain before the loop moves to the next phase.
- Explain why the order between `setTimeout(fn, 0)` and `setImmediate(fn)` is *not guaranteed* at the top level, but *is guaranteed* (`setImmediate` first) inside an I/O callback.
- Build a small reusable module that captures the real firing order of several async callbacks into an array.
- Build a CLI prediction step with `readline`, and a diff step that compares predicted vs. actual order.

## Prerequisites
- Playground: **Node.js** (open it before starting)
- Node.js available in the sandbox (`node -v` to confirm — nothing here needs anything beyond core Node)

## Why every task logs the phase name, not just the callback
It's tempting to just log `'fired: setTimeout'` and move on. But the actual teaching goal is the **queue/phase each callback belongs to**, not the callback itself — `setTimeout` and `setImmediate` are both "macrotasks" but live in *different* phases (timers vs. check), while `process.nextTick` and Promises are both "microtasks" but live in *different* queues with different priority. Every task below labels callbacks with their real name so you build the mapping from API → queue, not just API → "it's async."

## Steps

### Task 0 — Generate a real file to read
*Mechanism: none yet — this just gives every later task a real file for `fs.readFile` to read.*

**What's happening here:** `fs.readFile` needs an actual file on disk to demonstrate real, non-fake I/O — not a mocked timer standing in for it. We create one real text file once, up front.

Create a file `make-sample-file.js` and add the following:
```javascript
// make-sample-file.js
const fs = require('fs');

fs.writeFileSync('data.txt', 'this file is read for real by fs.readFile, not simulated\n');
console.log('created data.txt');
```

Run it:

```bash
node make-sample-file.js
cat data.txt
```

**Why** `cat data.txt` proves the file genuinely exists on disk with real content, so every later `fs.readFile` call in this lab is reading actual bytes from actual I/O — not something that only _looks_ async.

### Task 1 — Observe the raw baseline order
_Mechanism: registering all five primitives at once, with no categorization yet_

**What's happening here:** Before learning any rules, just look at what actually happens. Register all five async primitives back-to-back and log each one as it fires, in whatever order Node decides.

Create a file `observe-baseline.js` and add the following:

```javascript
// observe-baseline.js
const fs = require('fs');

console.log('--- sync start ---');

setTimeout(() => console.log('fired: setTimeout'), 0);
setImmediate(() => console.log('fired: setImmediate'));
process.nextTick(() => console.log('fired: process.nextTick'));
Promise.resolve().then(() => console.log('fired: promise'));
fs.readFile('data.txt', () => console.log('fired: fs.readFile'));

console.log('--- sync end ---');
```

Run it:

```bash
node observe-baseline.js
```

**Why** Running this — instead of just reading the code and guessing — is the entire point of the lab: your prediction and Node's real behavior are two separate things, and only an actual run tells you which one is right.

**What you should see:** `sync start` and `sync end` always print first and in that order — nothing async ever interrupts already-running synchronous code. After that, `process.nextTick` and `promise` reliably print before `setTimeout`/`setImmediate`/`fs.readFile`. The relative order of the last three can vary slightly run to run — that variability is exactly what Task 3 explains.

### Task 2 — The microtask battle: `nextTick` vs. `Promise`
_Mechanism: microtask queue priority_

**What's happening here:** Both `process.nextTick` and `Promise.then()` are "microtasks" — they run before the loop advances to any phase — but they are two _separate_ queues, and `process.nextTick`'s queue always drains completely first.

Create a file `microtask-battle.js` and add the following:

```javascript
// microtask-battle.js
process.nextTick(() => console.log('nextTick A'));
Promise.resolve().then(() => console.log('promise A'));
process.nextTick(() => console.log('nextTick B'));
Promise.resolve().then(() => console.log('promise B'));

setTimeout(() => console.log('timer (only after ALL microtasks are drained)'), 0);

console.log('sync');
```

Run it:

```bash
node microtask-battle.js
```

**Why** Interleaving two `nextTick`s with two promises, instead of just one of each, proves this isn't "nextTick runs once before a promise" — it proves the **entire** **`nextTick`** **queue** empties before the **entire promise queue** even starts, regardless of registration order.

**What you should see:** `sync`, then `nextTick A`, `nextTick B` (both, in order), then `promise A`, `promise B` (both, in order), and only then `timer` — proving both microtask queues fully drain before the timers phase even begins.

### Task 3 — `setTimeout(0)` vs. `setImmediate`: the ambiguous case
_Mechanism: timers phase vs. check phase, and how poll-phase context removes the ambiguity_

**What's happening here:** At the top level of a script, Node hasn't necessarily entered the poll phase yet, so whether the timers phase or the check phase runs first genuinely depends on process startup timing — it's not random, but it's not something your code controls either. Inside a real I/O callback, though, you're _already_ past the poll phase in this loop iteration, so the check phase (immediate) is guaranteed to run before timers gets another turn.

Create a file `timeout-vs-immediate.js` and add the following:

```javascript
// timeout-vs-immediate.js
const fs = require('fs');

// Case 1: top-level — order is genuinely NOT guaranteed.
setTimeout(() => console.log('[top-level] setTimeout'), 0);
setImmediate(() => console.log('[top-level] setImmediate'));

// Case 2: scheduled inside a real I/O callback — setImmediate always wins.
fs.readFile('data.txt', () => {
  setTimeout(() => console.log('[inside I/O] setTimeout'), 0);
  setImmediate(() => console.log('[inside I/O] setImmediate'));
});
```

Run it a few times in a row:

```bash
node timeout-vs-immediate.js
node timeout-vs-immediate.js
node timeout-vs-immediate.js
```

**Why** running it multiple times, not once, is what actually proves the top-level case is unreliable — a single run could get lucky and look deterministic when it isn't.

**What you should see:** the `[top-level]` pair may print in either order across runs (or consistently favor one order on your particular machine — either is normal). The `[inside I/O]` pair, however, should reliably print `setImmediate` before `setTimeout` on every single run, because it's already inside the poll phase when it schedules both.

### Task 4 — Build a reusable phase-capture module
_Mechanism: turning ad-hoc_ _`console.log`__s into a real, ordered data structure_

**What's happening here:** Every task so far just printed to the console. To build a CLI that can actually _diff_ a prediction against reality, we need the real firing order captured as an array we can compare — not just text scrolling past.

Create a file `phase-logger.js` and add the following:

```javascript
// phase-logger.js
const fs = require('fs');

function runAndCapture() {
  return new Promise((resolve) => {
    const fired = [];
    let remaining = 5;

    function mark(label) {
      fired.push(label);
      remaining--;
      if (remaining === 0) resolve(fired);
    }

    process.nextTick(() => mark('process.nextTick'));
    Promise.resolve().then(() => mark('promise'));
    setTimeout(() => mark('setTimeout'), 0);
    setImmediate(() => mark('setImmediate'));
    fs.readFile('data.txt', () => mark('fs.readFile'));
  });
}

module.exports = { runAndCapture };
```

Create a file `demo-logger.js` and add the following:

```javascript
// demo-logger.js
const { runAndCapture } = require('./phase-logger');

runAndCapture().then((order) => {
  console.log('actual fired order:', order);
});
```

Run it:

```bash
node demo-logger.js
```

**Why** `remaining` counting down to `0` before resolving is what guarantees the promise returned by `runAndCapture()` only settles once all five callbacks have genuinely fired — not after some arbitrary fixed delay that might be too short or wastefully too long.

**What you should see:** a single array of exactly 5 labels, in the real order Node fired them — this is the same information Task 1 showed you as scattered log lines, now as one structured result the rest of the CLI can actually use.

### Task 5 — Ask for a prediction first
_Mechanism:_ _`readline`_ _for interactive CLI input_

**What's happening here:** The whole exercise only works if the guess happens _before_ the run. This task builds the prompt that captures that guess as an array, in the same shape as `runAndCapture()`'s output, so the two can be compared later.

Create a file `predict.js` and add the following:

```javascript
// predict.js
const readline = require('readline');

function askPrediction(labels) {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });

  return new Promise((resolve) => {
    console.log('\nThe 5 callbacks that will run:', labels.join(', '));

    function prompt() {
      rl.question('Type your predicted firing order, comma-separated: ', (answer) => {
        const predicted = answer.split(',').map((s) => s.trim());

        const unknown = predicted.filter((label) => !labels.includes(label));
        const isCompleteSet =
          predicted.length === labels.length && new Set(predicted).size === labels.length;

        if (unknown.length > 0) {
          console.log(`\nNot a real label: "${unknown.join('", "')}". Valid labels are: ${labels.join(', ')}`);
          prompt(); // ask again instead of accepting garbage
          return;
        }
        if (!isCompleteSet) {
          console.log(`\nYou need all 5 labels, each exactly once. You gave ${predicted.length}: ${predicted.join(', ')}`);
          prompt(); // ask again instead of accepting a partial/duplicated guess
          return;
        }

        rl.close();
        resolve(predicted);
      });
    }

    prompt();
  });
}

module.exports = { askPrediction };
```

Create a file `demo-predict.js` and add the following:

```javascript
// demo-predict.js
const { askPrediction } = require('./predict');

const LABELS = ['process.nextTick', 'promise', 'setTimeout', 'setImmediate', 'fs.readFile'];

askPrediction(LABELS).then((predicted) => {
  console.log('you predicted:', predicted);
});
```

Run it and try typing something invalid first, then a real guess:

```bash
node demo-predict.js
```

**Why** validating here — not later in the diff — matters because an unvalidated guess would just silently compare as "wrong" against every position in Task 7, telling you nothing about _why_ it was wrong. Catching it at the prompt means every prediction that reaches the diff step is a genuine, complete guess, so a ❌ in Task 7 always means "you mispredicted the order," never "you mistyped a label." Closing `rl` immediately after a _valid_ answer still matters for the same reason as before — an open `readline` interface keeps the process alive waiting for more input.

**What you should see:** typing `incorrect word` gets rejected with `Not a real label: "". Valid labels are: ...` and re-prompts you; typing only 2 or 3 labels gets rejected with a count mismatch; only a complete, valid 5-label guess is accepted and echoed back as `you predicted: [...]`.

### Task 6 — Wire prediction + run together
_Mechanism: combining Tasks 4 and 5 into one flow_

**What's happening here:** This is the first point where the CLI actually feels like the "time machine" — ask for a guess, then reveal what really happened, side by side.

Create a file `time-machine.js` and add the following:

```javascript
// time-machine.js
const { runAndCapture } = require('./phase-logger');
const { askPrediction } = require('./predict');

const LABELS = ['process.nextTick', 'promise', 'setTimeout', 'setImmediate', 'fs.readFile'];

(async () => {
  const predicted = await askPrediction(LABELS);

  console.log('\nrunning...\n');
  const actual = await runAndCapture();

  console.log('predicted:', predicted);
  console.log('actual   :', actual);
})();
```

Run it and type a guess when prompted (any order of the 5 labels, comma-separated):

```bash
node time-machine.js
```

**Why** printing `predicted` and `actual` as two full arrays, rather than just saying right/wrong, is what Task 7's diff step needs as its raw input — you can't grade a guess you haven't recorded in a comparable shape.

**What you should see:** your typed prediction echoed back exactly as you typed it, followed by the real order from Task 4 — almost certainly different from your guess in at least one position, which is exactly the gap the next task will make visible.

### Task 7 — The diff: score the prediction
_Mechanism: position-by-position array comparison_

**What's happening here:** A simple, required diff — no fuzzy matching needed, since both arrays are always the same 5 fixed labels in some order. Walk both arrays index by index and mark each position correct or not.

Create a file `diff.js` and add the following:

```javascript
// diff.js
function diffOrder(predicted, actual) {
  return predicted.map((label, i) => ({
    position: i + 1,
    predicted: label,
    actual: actual[i],
    correct: label === actual[i],
  }));
}

function printDiff(rows) {
  console.log('\n--- Prediction vs. Reality ---');
  for (const row of rows) {
    const mark = row.correct ? '✅' : '❌';
    console.log(`${mark} position ${row.position}: predicted "${row.predicted}", actual "${row.actual}"`);
  }
  const score = rows.filter((r) => r.correct).length;
  console.log(`\nScore: ${score}/${rows.length}`);
}

module.exports = { diffOrder, printDiff };
```

Update `time-machine.js` to use it — add this to the bottom of the `async` block, after the two `console.log` lines:

```javascript
  const { diffOrder, printDiff } = require('./diff');
  printDiff(diffOrder(predicted, actual));
```

Run it again with a real guess:

```bash
node time-machine.js
```

**Why** grading position-by-position (not just "did you get all 5 right") is what turns a single pass/fail into a concrete, visible map of exactly where your mental model diverged from Node's real behavior — position 2 wrong tells you something different than position 4 wrong.

**What you should see:** a ✅/❌ line for each of the 5 positions, plus a final score like `Score: 2/5` — try running it a few times with different guesses (including a deliberately "obvious" wrong guess like predicting `setTimeout` first) to see the score change.

> **Gotcha worth noticing:** run this a few times and look closely at the `actual` array — you may see `promise` fire _before_ `process.nextTick`, which looks like it contradicts Task 2. It doesn't; it's context, not a broken rule. In Task 2, `nextTick` and the promise were registered from a clean top-level script. Here, `runAndCapture()` is called _after_ `await askPrediction(...)` resolves — and that resumption is itself running as a Promise microtask. V8 doesn't hand control back to Node between each item in its own microtask queue; it keeps draining that queue until it's empty, including brand-new entries added _during_ the same drain. So the freshly-registered `promise` callback gets swept up in that same pass, while `process.nextTick` sits in Node's separate queue waiting for V8 to finish and hand control back. Same rule, different starting point in the call stack — a good reminder that "always" in event-loop rules usually means "always, given where you're standing when you register it."

## Validation
Run through each check and confirm the actual behavior, not just that the script ran without errors:

- [ ] Task 0: `data.txt` exists on disk with real, non-empty content.
- [ ] Task 1: `sync start`/`sync end` always print first, in order; `process.nextTick`/`promise` always print before the other three.
- [ ] Task 2: both `nextTick` lines print before both `promise` lines, and `timer` prints last of all.
- [ ] Task 3: the `[inside I/O]` pair reliably prints `setImmediate` before `setTimeout` on every run; the `[top-level]` pair may vary.
- [ ] Task 4: `demo-logger.js` prints one array of exactly 5 labels.
- [ ] Task 5: `demo-predict.js` rejects an invalid label (like `zabin`) and an incomplete guess, re-prompting each time, and only accepts and echoes back a complete, valid 5-label guess.
- [ ] Task 6: `time-machine.js` prints both a `predicted` and an `actual` array of the same 5 labels.
- [ ] Task 7: the diff prints 5 ✅/❌ rows and a score that changes correctly when you try different guesses.

## References & further learning
*   Node.js docs: The Node.js Event Loop, Timers, and `process.nextTick()`: [https://nodejs.org/en/learn/asynchronous-work/event-loop-timers-and-nexttick](https://nodejs.org/en/learn/asynchronous-work/event-loop-timers-and-nexttick)
*   Node.js docs: `timers` module: [https://nodejs.org/api/timers.html](https://nodejs.org/api/timers.html)
*   Node.js docs: `process.nextTick()`: [https://nodejs.org/api/process.html#processnexttickcallback-args](https://nodejs.org/api/process.html#processnexttickcallback-args)
*   Node.js docs: `fs.readFile`: [https://nodejs.org/api/fs.html#fsreadfilepath-options-callback](https://nodejs.org/api/fs.html#fsreadfilepath-options-callback)
*   Node.js docs: `readline` module: [https://nodejs.org/api/readline.html](https://nodejs.org/api/readline.html)
*   MDN: microtasks and the event loop (general JS background): [https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide/Using\_promises#microtasks](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide/Using_promises#microtasks)

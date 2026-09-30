#!/usr/bin/env bash
set -euo pipefail

node make-sample-file.js
cat data.txt

node observe-baseline.js

node microtask-battle.js

node timeout-vs-immediate.js
node timeout-vs-immediate.js
node timeout-vs-immediate.js

node demo-logger.js

node demo-predict.js

node time-machine.js

node time-machine.js

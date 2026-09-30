#!/usr/bin/env bash
set -euo pipefail

node calibrate.js

node server-healthy.js

curl -s -o /dev/null -w 'health: %{time_total}s\n' localhost:3000/health

node server-blocking.js

curl -s -o /dev/null -w 'health alone: %{time_total}s\n' localhost:3000/health
curl -s -o /dev/null -w 'hash alone:   %{time_total}s\n' localhost:3000/hash
curl -s -o /dev/null -w 'hash: %{time_total}s\n' localhost:3000/hash & sleep 0.02; curl -s -o /dev/null -w 'health during hash: %{time_total}s\n' localhost:3000/health; wait

node server-healthy.js

node loadtest.js

node server-blocking.js

node loadtest.js --hammer

node server-monitored.js

node loadtest.js --hammer

node server-fixed.js

node loadtest.js --hammer

nproc

UV_THREADPOOL_SIZE=1 node server-fixed.js

node loadtest.js --hammer

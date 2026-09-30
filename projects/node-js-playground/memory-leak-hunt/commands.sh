#!/usr/bin/env bash
set -euo pipefail

node --expose-gc leaky-server.js

node --expose-gc leaky-server.js

curl http://localhost:3000/stats

curl http://localhost:3000/stats
node load-client.js compute-same 300
curl http://localhost:3000/stats
node load-client.js compute-unique 300
curl http://localhost:3000/stats
node load-client.js compute-unique 300
curl http://localhost:3000/stats

# Ctrl+C to stop, then:
node --expose-gc leaky-server.js

node load-client.js subscribe 20
curl http://localhost:3000/stats
node load-client.js subscribe 500
curl http://localhost:3000/stats

curl "http://localhost:3000/snapshot?name=baseline"
node load-client.js compute-same 300
curl "http://localhost:3000/snapshot?name=after-neutral"

curl "http://localhost:3000/snapshot?name=cache-before"
node load-client.js compute-unique 300
curl "http://localhost:3000/snapshot?name=cache-after"

curl "http://localhost:3000/snapshot?name=listeners-before"
node load-client.js subscribe 300
curl "http://localhost:3000/snapshot?name=listeners-after"

node --inspect --expose-gc leaky-server.js

node --expose-gc fixed-server.js

curl http://localhost:3000/stats
node load-client.js compute-unique 300
curl http://localhost:3000/stats
node load-client.js compute-unique 300
curl http://localhost:3000/stats
node load-client.js subscribe 300
curl http://localhost:3000/stats

node --expose-gc leaky-server.js

node memory-trend.js &
node load-client.js compute-unique 800

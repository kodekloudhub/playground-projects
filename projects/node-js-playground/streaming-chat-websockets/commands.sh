#!/usr/bin/env bash
set -euo pipefail

node http-server.js

node upgrade-detect.js

node handshake.js

node frame-parser.js

node frame-buffer.js

node encode-frame.js

#!/usr/bin/env bash
set -euo pipefail

curl -s -o /dev/null -w "%{http_code} %{content_type}\n" \
  "https://<your-playground-host>/webhook/resumeradar"

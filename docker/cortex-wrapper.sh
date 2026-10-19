#!/bin/sh
# `cortex` inside the container: the Terminal, with the address and the API key of the server this container runs, so that
# `docker exec <name> cortex monitor --once`, `cortex status` and `cortex connect opencode` work without typing either.
# A key or address you set yourself (CORTEX_API_KEY, CORTEX_URL, --url) always wins.
KEY_FILE="${CORTEX_KEY_FILE:-/data/state/api-key}"
if [ -z "${CORTEX_API_KEY:-}" ] && [ -r "$KEY_FILE" ]; then
  CORTEX_API_KEY=$(cat "$KEY_FILE"); export CORTEX_API_KEY
fi
CORTEX_URL="${CORTEX_URL:-http://127.0.0.1:${PORT:-8080}}"; export CORTEX_URL
exec /opt/cortex/terminal/bin/cortex "$@"

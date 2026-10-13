#!/bin/sh
# Probe the web dashboard, resolving the port the same way the entrypoint does.
set -eu

DATA_DIR="${DATA_DIR:-/data}"
port="${UIPORT:-}"

if [ -z "${port}" ] && [ -f "${DATA_DIR}/config.json" ]; then
    port="$(sed -n 's/.*"uiport"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${DATA_DIR}/config.json" | head -n1)"
fi
port="${port:-11211}"

wget -q -O /dev/null "http://127.0.0.1:${port}/" || exit 1

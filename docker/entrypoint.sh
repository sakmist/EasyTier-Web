#!/usr/bin/env bash
#
# EasyTier-Web container entrypoint.
#
# Runs the two processes the original fnOS package supervised:
#   1. easytier-web-embed  - web dashboard + REST API + config server
#   2. easytier-core       - the EasyTier networking daemon, which pulls its
#                            config from the web process over udp://127.0.0.1
#
# This script is PID 1: it starts both children, forwards SIGTERM/SIGINT to
# them, and exits when either one dies so the restart policy can take over.
#
set -euo pipefail

SERVER_DIR="/app/server"

DATA_DIR="${DATA_DIR:-/data}"
LOG_DIR="${LOG_DIR:-${DATA_DIR}/logs}"
CONFIG_SERVER_PORT="${CONFIG_SERVER_PORT:-22020}"
CONFIG_SERVER_PROTOCOL="${CONFIG_SERVER_PROTOCOL:-udp}"
NO_TUN="${NO_TUN:-0}"
ET_WEB_EXTRA_ARGS="${ET_WEB_EXTRA_ARGS:-}"
ET_CORE_EXTRA_ARGS="${ET_CORE_EXTRA_ARGS:-}"

CONFIG_FILE="${DATA_DIR}/config.json"
DB_FILE="${DATA_DIR}/et.db"

log() { printf '%s [entrypoint] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

mkdir -p "${DATA_DIR}" "${LOG_DIR}"
cd "${SERVER_DIR}"

# --- first run: drop a default config.json, mirroring the fnOS package layout
if [ ! -f "${CONFIG_FILE}" ]; then
    log "no config found, creating default: ${CONFIG_FILE}"
    printf '{\n  "uiport": "11211"\n}\n' > "${CONFIG_FILE}"
fi

# --- resolve the web port: UIPORT env wins, then config.json, then 11211
UIPORT_RESOLVED="${UIPORT:-}"
if [ -z "${UIPORT_RESOLVED}" ]; then
    if command -v jq >/dev/null 2>&1; then
        UIPORT_RESOLVED="$(jq -r '.uiport // empty' "${CONFIG_FILE}" 2>/dev/null || true)"
    fi
    if [ -z "${UIPORT_RESOLVED}" ]; then
        UIPORT_RESOLVED="$(sed -n 's/.*"uiport"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${CONFIG_FILE}" | head -n1)"
    fi
fi
UIPORT_RESOLVED="${UIPORT_RESOLVED:-11211}"

is_true() {
    case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
        1|true|yes|on) return 0 ;;
        *) return 1 ;;
    esac
}

# --- 1. web dashboard / REST API / config server
log "starting easytier-web-embed (web+api port=${UIPORT_RESOLVED}, config server=${CONFIG_SERVER_PROTOCOL}://0.0.0.0:${CONFIG_SERVER_PORT}, db=${DB_FILE})"
# shellcheck disable=SC2086
"${SERVER_DIR}/easytier-web-embed" \
    --db "${DB_FILE}" \
    --api-server-port "${UIPORT_RESOLVED}" \
    --config-server-port "${CONFIG_SERVER_PORT}" \
    --config-server-protocol "${CONFIG_SERVER_PROTOCOL}" \
    --file-log-dir "${LOG_DIR}" \
    ${ET_WEB_EXTRA_ARGS} &
WEB_PID=$!

# --- 2. wait for the config server to accept connections before starting core
for _ in $(seq 1 30); do
    if ! kill -0 "${WEB_PID}" 2>/dev/null; then
        log "ERROR: easytier-web-embed exited during startup"
        exit 1
    fi
    if (exec 3<>"/dev/tcp/127.0.0.1/${UIPORT_RESOLVED}") 2>/dev/null; then
        exec 3>&- 2>/dev/null || true
        log "web dashboard is up on port ${UIPORT_RESOLVED}"
        break
    fi
    sleep 1
done

# --- 3. EasyTier core, wired to the local config server
CORE_ARGS=(
    --config-server "${CONFIG_SERVER_PROTOCOL}://127.0.0.1:${CONFIG_SERVER_PORT}/admin"
    --file-log-dir "${LOG_DIR}"
)
if is_true "${NO_TUN}"; then
    log "NO_TUN is set: easytier-core will not create a TUN device"
    CORE_ARGS+=(--no-tun)
fi

log "starting easytier-core"
# shellcheck disable=SC2086
"${SERVER_DIR}/easytier-core" "${CORE_ARGS[@]}" ${ET_CORE_EXTRA_ARGS} &
CORE_PID=$!

shutdown() {
    log "shutting down"
    trap '' TERM INT
    kill -TERM "${CORE_PID}" "${WEB_PID}" 2>/dev/null || true
    wait "${CORE_PID}" 2>/dev/null || true
    wait "${WEB_PID}" 2>/dev/null || true
    log "stopped"
    exit 0
}
trap shutdown TERM INT QUIT

set +e
wait -n "${WEB_PID}" "${CORE_PID}"
rc=$?
set -e
log "a managed process exited (rc=${rc})"
shutdown

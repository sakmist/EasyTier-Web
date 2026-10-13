#!/usr/bin/env bash
#
# Build and start EasyTier-Web with docker compose, then wait for the web
# dashboard to answer. Run this on the Docker host (e.g. the NAS).
#
#   sudo ./scripts/deploy.sh              # build + start
#   sudo ./scripts/deploy.sh --no-build   # start an already-built image
#
set -euo pipefail

cd "$(dirname "$0")/.."

IMAGE="${IMAGE:-easytier-web:2.4.5}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"
BUILD=1
for arg in "$@"; do
    case "${arg}" in
        --no-build) BUILD=0 ;;
        -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: ${arg}" >&2; exit 2 ;;
    esac
done

command -v docker >/dev/null 2>&1 || { echo "docker not found" >&2; exit 1; }

if ! docker info >/dev/null 2>&1; then
    echo "cannot talk to the Docker daemon - are you root / in the docker group?" >&2
    exit 1
fi

# Resolve the compose command (v2 plugin preferred, v1 fallback).
if docker compose version >/dev/null 2>&1; then
    DC=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
    DC=(docker-compose)
else
    echo "docker compose not found" >&2
    exit 1
fi

mkdir -p data
chmod 0755 data 2>/dev/null || true

if [ "${BUILD}" = "1" ]; then
    echo "==> building ${IMAGE}"
    docker build -t "${IMAGE}" .
fi

echo "==> starting stack (${COMPOSE_FILE})"
"${DC[@]}" -f "${COMPOSE_FILE}" up -d

# --- wait for the dashboard to come up
port="$(sed -n 's/.*"uiport"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' data/config.json 2>/dev/null | head -n1)"
port="${UIPORT:-${port:-11211}}"

echo "==> waiting for the web dashboard on port ${port}"
ok=0
for _ in $(seq 1 30); do
    if curl -fsS -o /dev/null "http://127.0.0.1:${port}/" 2>/dev/null; then
        ok=1
        break
    fi
    sleep 1
done

host_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
if [ "${ok}" = "1" ]; then
    echo
    echo "EasyTier-Web is up."
    echo "  URL:      http://${host_ip:-<host-ip>}:${port}"
    echo "  user/pw:  admin / admin"
    echo "  logs:     ${DC[*]} -f ${COMPOSE_FILE} logs -f"
else
    echo "dashboard did not answer within 30s - check: ${DC[*]} -f ${COMPOSE_FILE} logs" >&2
    exit 1
fi

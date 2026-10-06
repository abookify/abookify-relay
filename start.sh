#!/usr/bin/env bash
# Start the nullbore tunnel with the server's install UUID as the slug.
# Run this AFTER `docker compose up server` so the UUID exists.
set -euo pipefail

cd "$(dirname "$0")/../server"

# Load relay env
set -a
. ../relay/.env
set +a

if [ -z "${NULLBORE_API_KEY:-}" ]; then
  echo "error: NULLBORE_API_KEY not set in engineering/relay/.env" >&2
  exit 1
fi

# Wait for the server to be reachable at all (liveness, never auth-gated)
for i in $(seq 1 30); do
  curl -fsS http://localhost:7654/api/health >/dev/null 2>&1 && break
  sleep 1
done
if ! curl -fsS http://localhost:7654/api/health >/dev/null 2>&1; then
  echo "error: abookify server not responding on :7654 — start it first" >&2
  exit 1
fi

# Read the install UUID. /api/server-info is auth-gated when #197 auth is on
# (it 401s), so fall back to reading settings.server_install_id straight out of
# the SQLite file — that's the same value the endpoint returns. Without this
# fallback an auth-enabled server silently loses its tunnel across a reboot.
SERVER_ID=""
if info=$(curl -fsS http://localhost:7654/api/server-info 2>/dev/null); then
  SERVER_ID=$(echo "$info" | sed -n 's/.*"server_id":"\([^"]*\)".*/\1/p')
fi
if [ -z "$SERVER_ID" ] && [ -f data/abookify.db ]; then
  SERVER_ID=$(python3 -c "
import sqlite3,sys
c=sqlite3.connect('file:data/abookify.db?mode=ro',uri=True)
r=c.execute(\"select value from settings where key='server_install_id'\").fetchone()
sys.stdout.write(r[0] if r else '')
" 2>/dev/null || true)
  [ -n "$SERVER_ID" ] && echo "relay: server_info unavailable (auth on?) — read server_id from data/abookify.db"
fi
if [ -z "$SERVER_ID" ]; then
  echo "error: could not determine server_id (API 401/unreachable and DB read failed)" >&2
  exit 1
fi

# End-to-end mode (NULLBORE_E2E_DOMAIN set, e.g. abookify.e2e.nullbore.com): the
# relay forwards the phone's TLS bytes untouched into the server's TLS listener
# (:7655, self-signed, pinned by the pairing QR). The relay never holds a key
# for that hostname. Requires a paid NullBore plan (403 otherwise) and the
# v0.1.0-beta.23+ client vendored in ./client. Without it: the classic proxied
# path, which the relay (and Cloudflare in front of it) can read.
if [ -n "${NULLBORE_E2E_DOMAIN:-}" ]; then
  # Both paths side by side during migration: devices paired before the
  # end-to-end URL existed keep working on the proxied hostname. The relay
  # refuses two tunnels of one name, so the end-to-end one is "<id>-e2e"
  # (the server advertises the same: PublicURL → https://<id>-e2e.<domain>).
  echo "relay: END-TO-END — https://${SERVER_ID}-e2e.${NULLBORE_E2E_DOMAIN} → local :${ABOOKIFY_TLS_PORT:-7655} (TLS passthrough; relay cannot read it)"
  export NULLBORE_TUNNELS="server:7654:${SERVER_ID},server:${ABOOKIFY_TLS_PORT:-7655}:${SERVER_ID}-e2e+tls-passthrough"
else
  echo "relay: tunneling https://${SERVER_ID}.${NULLBORE_BASE_DOMAIN:-abookify.nullbore.com} → local :7654 (proxied; the relay terminates TLS)"
  export NULLBORE_TUNNELS="server:7654:${SERVER_ID}"
fi

# Include the GPU overlay when this host has an NVIDIA GPU. Without it, compose
# reconciles the whole project against the base file only and RECREATES whisper
# without its GPU config — silently dropping STT back to CPU (happened after the
# 2026-07-28 reboot). The overlay must match however the stack was brought up.
COMPOSE_FILES=(-f docker-compose.yml)
if nvidia-smi -L >/dev/null 2>&1; then
  COMPOSE_FILES+=(-f docker-compose.gpu.yml)
fi

exec docker compose "${COMPOSE_FILES[@]}" --profile relay up -d --no-deps --build nullbore
